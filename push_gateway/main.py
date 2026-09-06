"""FastAPI application for SGT VoIP Push Gateway with authentication and security hardening."""

import os
import time
import logging
from contextlib import asynccontextmanager
from typing import Optional, Dict

from fastapi import FastAPI, Depends, HTTPException, Header, Request, Response, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from database import (
    init_db,
    upsert_device_token,
    revoke_device_token,
    get_active_tokens_for_extension,
    create_or_update_call,
    update_call_status,
    get_call,
    mask_token,
)
from models import (
    DeviceRegisterRequest,
    DeviceRevokeRequest,
    IncomingPushRequest,
    CancelPushRequest,
    CallEventRequest,
    ApiResponse,
)
from push_sender import PushSender

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("sgt_push_gateway")

# Secrets from environment or /etc/sgt-push-gateway/gateway.env
INTERNAL_API_SECRET = os.getenv("INTERNAL_API_SECRET", "sgt_internal_voip_secret_2026")
DEVICE_AUTH_SECRET = os.getenv("DEVICE_AUTH_SECRET", INTERNAL_API_SECRET)

push_sender = PushSender()


class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    """Prevent Denial-of-Service via oversized request payloads."""

    def __init__(self, app, max_bytes: int = 32768):
        super().__init__(app)
        self.max_bytes = max_bytes

    async def dispatch(self, request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > self.max_bytes:
            return Response(
                content='{"success": false, "message": "Payload exceeds maximum allowed size (32KB)"}',
                status_code=getattr(status, "HTTP_413_CONTENT_TOO_LARGE", 413),
                media_type="application/json",
            )
        return await call_next(request)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    logger.info("SGT VoIP Push Gateway initialized and ready on port 8085.")
    yield
    logger.info("SGT VoIP Push Gateway shutting down.")


app = FastAPI(
    title="SGT VoIP Push Gateway",
    version="1.1.0",
    description="Secure Push notification broker for SGT Softphone incoming calls (FCM & APNs)",
    lifespan=lifespan,
)

app.add_middleware(MaxBodySizeMiddleware, max_bytes=32768)


# =========================================================================
# Authentication Dependencies
# =========================================================================

async def verify_internal_auth(
    request: Request,
    x_internal_secret: Optional[str] = Header(None, alias="X-Internal-Secret"),
    authorization: Optional[str] = Header(None),
):
    """Authenticate internal Asterisk and system calls."""
    token = x_internal_secret
    if not token and authorization and authorization.startswith("Bearer "):
        token = authorization[7:].strip()

    if not token:
        logger.warning(f"Unauthorized internal access attempt from {request.client.host if request.client else 'unknown'}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing internal authentication credentials",
        )

    if token != INTERNAL_API_SECRET:
        logger.warning(f"Forbidden internal access attempt (invalid secret) from {request.client.host if request.client else 'unknown'}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid internal authentication credentials",
        )


async def verify_device_auth(
    request: Request,
    x_device_token: Optional[str] = Header(None, alias="X-Device-Auth-Token"),
    authorization: Optional[str] = Header(None),
):
    """Authenticate mobile device registrations to prevent unauthorized spoofing."""
    token = x_device_token
    if not token and authorization and authorization.startswith("Bearer "):
        token = authorization[7:].strip()

    # If DEVICE_AUTH_SECRET is configured, enforce matching
    if DEVICE_AUTH_SECRET:
        if not token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing device authentication token",
            )
        if token != DEVICE_AUTH_SECRET:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid device authentication token",
            )


# =========================================================================
# Public Endpoints
# =========================================================================

@app.get("/health", response_model=ApiResponse)
async def health_check():
    """Health check exposing overall service status and provider readiness."""
    providers_info = push_sender.get_provider_status()
    is_degraded = (
        providers_info["fcm"]["status"] != "configured"
        and providers_info["apns"]["status"] != "configured"
        and not push_sender.test_mode
    )

    return ApiResponse(
        success=True,
        message="SGT VoIP Push Gateway is running" + (" (providers degraded)" if is_degraded else ""),
        data={
            "service": "sgt-push-gateway",
            "status": "degraded" if is_degraded else "ok",
            "database": "connected",
            "providers": providers_info,
        },
    )


# =========================================================================
# Device Registration Endpoints (Protected by Device Auth)
# =========================================================================

@app.post("/api/v1/devices/register", response_model=ApiResponse, dependencies=[Depends(verify_device_auth)])
async def register_device(req: DeviceRegisterRequest):
    """Register or refresh mobile push token from mobile client."""
    try:
        upsert_device_token(
            extension=req.extension,
            platform=req.platform,
            device_id=req.device_id,
            push_token=req.push_token,
            push_environment=req.push_environment,
            app_version=req.app_version,
        )
        masked = mask_token(req.push_token)
        logger.info(
            f"Device token registered: ext={req.extension}, platform={req.platform}, device_id={req.device_id}, token={masked}"
        )
        return ApiResponse(
            success=True,
            message="Device push token registered successfully",
            data={
                "extension": req.extension,
                "platform": req.platform,
                "device_id": req.device_id,
            },
        )
    except Exception as ex:
        logger.error(f"Error registering device token: {ex}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to register token",
        )


@app.post("/api/v1/devices/revoke", response_model=ApiResponse, dependencies=[Depends(verify_device_auth)])
async def revoke_device(req: DeviceRevokeRequest):
    """Revoke push token when user logs out."""
    revoked = revoke_device_token(extension=req.extension, device_id=req.device_id)
    logger.info(f"Device token revoked: ext={req.extension}, device_id={req.device_id}, status={revoked}")
    return ApiResponse(
        success=True,
        message="Device token revoked successfully" if revoked else "Token was not found or already inactive",
        data={"revoked": revoked},
    )


@app.get("/api/v1/devices/tokens/{extension}", response_model=ApiResponse, dependencies=[Depends(verify_internal_auth)])
async def get_extension_tokens(extension: str):
    """Query active tokens for an extension (Internal/Diagnostic only, tokens masked)."""
    tokens = get_active_tokens_for_extension(extension, redact_tokens=True)
    return ApiResponse(
        success=True,
        message=f"Found {len(tokens)} active token(s) for extension {extension}",
        data={"extension": extension, "count": len(tokens), "tokens": tokens},
    )


# =========================================================================
# Internal Asterisk Dialplan Endpoints (Protected by Internal Secret)
# =========================================================================

@app.post("/api/v1/internal/push/incoming", response_model=ApiResponse, dependencies=[Depends(verify_internal_auth)])
async def trigger_incoming_push(req: IncomingPushRequest):
    """Trigger incoming call push notification (called by Asterisk dialplan / AGI)."""
    logger.info(
        f"Incoming call push request: call_uuid={req.call_uuid}, from={req.caller_extension} to={req.callee_extension}"
    )

    # 1. Track call in SQLite
    call_record = create_or_update_call(
        call_uuid=req.call_uuid,
        caller_extension=req.caller_extension,
        caller_display_name=req.caller_display_name,
        callee_extension=req.callee_extension,
        asterisk_uniqueid=req.asterisk_uniqueid,
        status="ringing",
        ttl_seconds=req.ttl_seconds,
    )

    # 2. Look up active device tokens for callee
    tokens = get_active_tokens_for_extension(req.callee_extension, redact_tokens=False)
    if not tokens:
        logger.warning(f"No active device tokens found for callee extension {req.callee_extension}")
        return ApiResponse(
            success=False,
            message=f"No active push tokens registered for extension {req.callee_extension}",
            data={"call_uuid": req.call_uuid, "sent_count": 0, "call_record": call_record},
        )

    # 3. Dispatch push to all active devices of callee
    results = []
    for token_info in tokens:
        res = await push_sender.send_incoming_call_push(
            token_info=token_info,
            call_uuid=req.call_uuid,
            caller_extension=req.caller_extension,
            caller_display_name=req.caller_display_name or f"Extension {req.caller_extension}",
            callee_extension=req.callee_extension,
            ttl_seconds=req.ttl_seconds,
        )
        results.append(res)

    sent_count = sum(1 for r in results if r.get("status") in ("sent", "test_mock_dispatched"))
    logger.info(
        f"Incoming push dispatched for call_uuid={req.call_uuid}: {sent_count}/{len(tokens)} successful"
    )

    return ApiResponse(
        success=sent_count > 0,
        message=f"Dispatched push to {sent_count}/{len(tokens)} device(s)",
        data={
            "call_uuid": req.call_uuid,
            "target_extension": req.callee_extension,
            "sent_count": sent_count,
            "deliveries": results,
        },
    )


@app.post("/api/v1/internal/push/cancel", response_model=ApiResponse, dependencies=[Depends(verify_internal_auth)])
async def trigger_cancel_push(req: CancelPushRequest):
    """Trigger call cancellation push (called by Asterisk hangup handler when caller aborts)."""
    logger.info(f"Call cancel push request: call_uuid={req.call_uuid}, reason={req.reason}")

    # 1. Update call record status
    call_record = get_call(req.call_uuid)
    if not call_record:
        logger.warning(f"Call record for UUID {req.call_uuid} not found for cancellation")
        return ApiResponse(
            success=True,
            message="Call record not found, nothing to cancel",
            data={"call_uuid": req.call_uuid},
        )

    update_call_status(req.call_uuid, "cancelled")

    # 2. Dispatch cancel push to callee's devices
    callee_ext = call_record.get("callee_extension")
    tokens = get_active_tokens_for_extension(callee_ext, redact_tokens=False) if callee_ext else []

    results = []
    for token_info in tokens:
        res = await push_sender.send_cancel_call_push(
            token_info=token_info,
            call_uuid=req.call_uuid,
            reason=req.reason,
        )
        results.append(res)

    sent_count = sum(1 for r in results if r.get("status") in ("sent", "test_mock_dispatched"))
    return ApiResponse(
        success=True,
        message=f"Dispatched cancellation push to {sent_count} device(s)",
        data={"call_uuid": req.call_uuid, "sent_count": sent_count, "deliveries": results},
    )


@app.post("/api/v1/internal/call/event", response_model=ApiResponse, dependencies=[Depends(verify_internal_auth)])
async def update_call_event(req: CallEventRequest):
    """Update call state from client or Asterisk."""
    updated = update_call_status(req.call_uuid, req.status)
    return ApiResponse(
        success=updated,
        message=f"Call {req.call_uuid} state updated to {req.status}" if updated else "Call not found",
        data={"call_uuid": req.call_uuid, "status": req.status},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8085, reload=False)
