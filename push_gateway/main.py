"""FastAPI application for SGT VoIP Push Gateway."""

import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse

from database import (
    init_db,
    upsert_device_token,
    revoke_device_token,
    get_active_tokens_for_extension,
    create_or_update_call,
    update_call_status,
    get_call,
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

push_sender = PushSender()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: ensure tables exist
    init_db()
    logger.info("SGT VoIP Push Gateway initialized and ready on port 8085.")
    yield
    logger.info("SGT VoIP Push Gateway shutting down.")


app = FastAPI(
    title="SGT VoIP Push Gateway",
    version="1.0.0",
    description="Push notification broker for SGT Softphone incoming calls (FCM & APNs)",
    lifespan=lifespan,
)


@app.get("/health", response_model=ApiResponse)
async def health_check():
    return ApiResponse(
        success=True,
        message="SGT VoIP Push Gateway is running healthy",
        data={"status": "ok", "service": "sgt-push-gateway"},
    )


@app.post("/api/v1/devices/register", response_model=ApiResponse)
async def register_device(req: DeviceRegisterRequest):
    """Register or refresh mobile push token from Flutter client."""
    try:
        upsert_device_token(
            extension=req.extension,
            platform=req.platform,
            device_id=req.device_id,
            push_token=req.push_token,
            push_environment=req.push_environment,
            app_version=req.app_version,
        )
        logger.info(
            f"Device token registered: ext={req.extension}, platform={req.platform}, device_id={req.device_id}"
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
            detail=f"Failed to register token: {str(ex)}",
        )


@app.post("/api/v1/devices/revoke", response_model=ApiResponse)
async def revoke_device(req: DeviceRevokeRequest):
    """Revoke push token when user logs out."""
    revoked = revoke_device_token(extension=req.extension, device_id=req.device_id)
    logger.info(f"Device token revoked: ext={req.extension}, device_id={req.device_id}, status={revoked}")
    return ApiResponse(
        success=True,
        message="Device token revoked successfully" if revoked else "Token was not found or already inactive",
        data={"revoked": revoked},
    )


@app.get("/api/v1/devices/tokens/{extension}", response_model=ApiResponse)
async def get_extension_tokens(extension: str):
    """Query active tokens for an extension (diagnostic endpoint)."""
    tokens = get_active_tokens_for_extension(extension)
    return ApiResponse(
        success=True,
        message=f"Found {len(tokens)} active token(s) for extension {extension}",
        data={"extension": extension, "count": len(tokens), "tokens": tokens},
    )


@app.post("/api/v1/internal/push/incoming", response_model=ApiResponse)
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
    tokens = get_active_tokens_for_extension(req.callee_extension)
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

    sent_count = sum(1 for r in results if r.get("status") in ("sent", "delivered_sandbox"))
    logger.info(
        f"Incoming push dispatched for call_uuid={req.call_uuid}: {sent_count}/{len(tokens)} successful"
    )

    return ApiResponse(
        success=True,
        message=f"Dispatched push to {sent_count} device(s)",
        data={
            "call_uuid": req.call_uuid,
            "target_extension": req.callee_extension,
            "sent_count": sent_count,
            "deliveries": results,
        },
    )


@app.post("/api/v1/internal/push/cancel", response_model=ApiResponse)
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
    tokens = get_active_tokens_for_extension(callee_ext) if callee_ext else []

    results = []
    for token_info in tokens:
        res = await push_sender.send_cancel_call_push(
            token_info=token_info,
            call_uuid=req.call_uuid,
            reason=req.reason,
        )
        results.append(res)

    sent_count = sum(1 for r in results if r.get("status") in ("sent", "delivered_sandbox"))
    return ApiResponse(
        success=True,
        message=f"Dispatched cancellation push to {sent_count} device(s)",
        data={"call_uuid": req.call_uuid, "sent_count": sent_count, "deliveries": results},
    )


@app.post("/api/v1/internal/call/event", response_model=ApiResponse)
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
