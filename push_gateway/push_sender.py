"""Production-grade Push Notification Sender for Android (FCM v1) and iOS (APNs VoIP)."""

import os
import time
import json
import logging
from typing import Dict, Any, Optional

import httpx
import jwt

from database import disable_push_token, mask_token

logger = logging.getLogger("sgt_push_gateway.push_sender")


class PushSender:
    def __init__(self):
        self.firebase_credentials_path = os.getenv(
            "FIREBASE_SERVICE_ACCOUNT_JSON",
            "/etc/sgt-push-gateway/firebase-service-account.json",
        )
        self.apns_key_path = os.getenv(
            "APNS_KEY_PATH",
            "/etc/sgt-push-gateway/apns_key.p8",
        )
        self.apns_key_id = os.getenv("APNS_KEY_ID", "")
        self.apns_team_id = os.getenv("APNS_TEAM_ID", "")
        self.apns_bundle_id = os.getenv("APNS_BUNDLE_ID", "com.sgt.voip.flutterSipSoftphone")

        # Test mode flag (only allowed via explicit env var in automated tests)
        self.test_mode = os.getenv("GATEWAY_TEST_MODE") == "1"

        # Token caching
        self._fcm_token: Optional[str] = None
        self._fcm_token_expiry: float = 0.0
        self._apns_jwt: Optional[str] = None
        self._apns_jwt_expiry: float = 0.0

    def get_provider_status(self) -> Dict[str, Any]:
        """Expose actual provider configuration and readiness."""
        fcm_configured = os.path.isfile(self.firebase_credentials_path)
        apns_configured = (
            os.path.isfile(self.apns_key_path)
            and bool(self.apns_key_id)
            and bool(self.apns_team_id)
        )
        return {
            "fcm": {
                "status": "configured" if fcm_configured else "not_configured",
                "mode": "mock_test" if self.test_mode else "production",
                "credentials_file_found": fcm_configured,
            },
            "apns": {
                "status": "configured" if apns_configured else "not_configured",
                "mode": "mock_test" if self.test_mode else "production",
                "key_file_found": os.path.isfile(self.apns_key_path),
                "key_id_set": bool(self.apns_key_id),
                "team_id_set": bool(self.apns_team_id),
            },
        }

    async def send_incoming_call_push(
        self,
        token_info: Dict[str, Any],
        call_uuid: str,
        caller_extension: str,
        caller_display_name: str,
        callee_extension: str,
        ttl_seconds: int = 30,
    ) -> Dict[str, Any]:
        """Dispatch high-priority incoming call push to an individual device."""
        platform = token_info.get("platform", "android")
        push_token = token_info.get("push_token", "")
        device_id = token_info.get("device_id", "")
        push_env = token_info.get("push_environment", "production")

        data = {
            "action": "incoming_call",
            "call_uuid": call_uuid,
            "caller_extension": caller_extension,
            "caller_display_name": caller_display_name or f"Extension {caller_extension}",
            "callee_extension": callee_extension,
            "ttl_seconds": str(ttl_seconds),
            "timestamp": str(int(time.time())),
        }

        if platform == "android":
            return await self._send_fcm(push_token, device_id, data, ttl_seconds)
        elif platform == "ios":
            return await self._send_apns(push_token, device_id, data, ttl_seconds, push_env)
        else:
            return {
                "device_id": device_id,
                "platform": platform,
                "status": "failed",
                "error": f"Unknown platform: {platform}",
            }

    async def send_cancel_call_push(
        self,
        token_info: Dict[str, Any],
        call_uuid: str,
        reason: str = "caller_hangup",
    ) -> Dict[str, Any]:
        """Dispatch call cancellation push to an individual device."""
        platform = token_info.get("platform", "android")
        push_token = token_info.get("push_token", "")
        device_id = token_info.get("device_id", "")
        push_env = token_info.get("push_environment", "production")

        data = {
            "action": "cancel_call",
            "call_uuid": call_uuid,
            "reason": reason,
            "timestamp": str(int(time.time())),
        }

        if platform == "android":
            return await self._send_fcm(push_token, device_id, data, ttl_seconds=10)
        elif platform == "ios":
            return await self._send_apns(push_token, device_id, data, ttl_seconds=10, push_env=push_env)
        else:
            return {
                "device_id": device_id,
                "platform": platform,
                "status": "failed",
                "error": f"Unknown platform: {platform}",
            }

    async def _get_fcm_access_token(self, service_account: dict) -> str:
        """Obtain or return cached Google OAuth2 access token for FCM v1."""
        now = time.time()
        if self._fcm_token and now < self._fcm_token_expiry - 120:
            return self._fcm_token

        client_email = service_account["client_email"]
        private_key = service_account["private_key"]
        token_uri = service_account.get("token_uri", "https://oauth2.googleapis.com/token")

        payload = {
            "iss": client_email,
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": token_uri,
            "iat": int(now),
            "exp": int(now + 3600),
        }

        signed_jwt = jwt.encode(payload, private_key, algorithm="RS256")

        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                token_uri,
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion": signed_jwt,
                },
            )
            if resp.status_code != 200:
                raise RuntimeError(f"Failed to obtain FCM access token: HTTP {resp.status_code} - {resp.text}")
            result = resp.json()
            self._fcm_token = result["access_token"]
            self._fcm_token_expiry = now + result.get("expires_in", 3600)
            return self._fcm_token

    async def _send_fcm(
        self,
        push_token: str,
        device_id: str,
        data: Dict[str, str],
        ttl_seconds: int,
    ) -> Dict[str, Any]:
        """Send high-priority data message via FCM HTTP v1."""
        masked = mask_token(push_token)

        # Check credentials existence
        if not os.path.isfile(self.firebase_credentials_path):
            if self.test_mode:
                logger.info(f"[FCM MOCK_TEST] device={device_id} token={masked} action={data.get('action')}")
                return {
                    "device_id": device_id,
                    "platform": "android",
                    "status": "test_mock_dispatched",
                    "message_id": f"mock_fcm_{data.get('call_uuid')}_{device_id}",
                }
            logger.warning(
                f"[FCM NOT CONFIGURED] Credentials file missing at {self.firebase_credentials_path}. Push to {masked} skipped."
            )
            return {
                "device_id": device_id,
                "platform": "android",
                "status": "provider_not_configured",
                "error": f"FCM credentials missing at {self.firebase_credentials_path}",
            }

        try:
            with open(self.firebase_credentials_path, "r", encoding="utf-8") as f:
                service_account = json.load(f)
            project_id = service_account["project_id"]
            access_token = await self._get_fcm_access_token(service_account)

            fcm_url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
            payload = {
                "message": {
                    "token": push_token,
                    "data": data,
                    "android": {
                        "priority": "high",
                        "ttl": f"{ttl_seconds}s",
                    },
                }
            }

            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.post(
                    fcm_url,
                    json=payload,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json",
                    },
                )

                if resp.status_code == 200:
                    body = resp.json()
                    message_id = body.get("name", "")
                    logger.info(f"[FCM SENT] device={device_id} message_id={message_id}")
                    return {
                        "device_id": device_id,
                        "platform": "android",
                        "status": "sent",
                        "message_id": message_id,
                    }

                # Handle token expiration / unregistration
                error_body = resp.text
                if resp.status_code in (404, 400) or "UNREGISTERED" in error_body or "NOT_FOUND" in error_body:
                    logger.warning(f"[FCM UNREGISTERED] Token {masked} is invalid or expired. Disabling in DB.")
                    disable_push_token(push_token)
                    return {
                        "device_id": device_id,
                        "platform": "android",
                        "status": "unregistered",
                        "error": "Device token is unregistered or invalid",
                    }

                logger.error(f"[FCM ERROR] HTTP {resp.status_code} for device={device_id}: {error_body}")
                return {
                    "device_id": device_id,
                    "platform": "android",
                    "status": "provider_error",
                    "status_code": resp.status_code,
                    "error": error_body,
                }

        except Exception as ex:
            logger.error(f"[FCM EXCEPTION] Failed to dispatch to {device_id}: {ex}")
            return {
                "device_id": device_id,
                "platform": "android",
                "status": "failed",
                "error": str(ex),
            }

    def _get_apns_jwt(self) -> str:
        """Generate or return cached JWT token for Apple APNs ES256 authentication."""
        now = time.time()
        if self._apns_jwt and now < self._apns_jwt_expiry - 120:
            return self._apns_jwt

        with open(self.apns_key_path, "r", encoding="utf-8") as f:
            private_key = f.read()

        payload = {
            "iss": self.apns_team_id,
            "iat": int(now),
        }
        headers = {
            "alg": "ES256",
            "kid": self.apns_key_id,
        }

        self._apns_jwt = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
        self._apns_jwt_expiry = now + 3000
        return self._apns_jwt

    async def _send_apns(
        self,
        push_token: str,
        device_id: str,
        data: Dict[str, str],
        ttl_seconds: int,
        push_env: str,
    ) -> Dict[str, Any]:
        """Send VoIP push via Apple APNs HTTP/2."""
        masked = mask_token(push_token)

        # Check credentials existence
        apns_ready = (
            os.path.isfile(self.apns_key_path)
            and bool(self.apns_key_id)
            and bool(self.apns_team_id)
        )
        if not apns_ready:
            if self.test_mode:
                logger.info(f"[APNs MOCK_TEST] device={device_id} token={masked} action={data.get('action')}")
                return {
                    "device_id": device_id,
                    "platform": "ios",
                    "status": "test_mock_dispatched",
                    "message_id": f"mock_apns_{data.get('call_uuid')}_{device_id}",
                }
            logger.warning(
                f"[APNs NOT CONFIGURED] .p8 key file or KEY_ID missing. Push to {masked} skipped."
            )
            return {
                "device_id": device_id,
                "platform": "ios",
                "status": "provider_not_configured",
                "error": "APNs credentials (.p8 key or Team/Key ID) not configured",
            }

        try:
            token_jwt = self._get_apns_jwt()
            base_url = (
                "https://api.sandbox.push.apple.com"
                if push_env == "development"
                else "https://api.push.apple.com"
            )
            url = f"{base_url}/3/device/{push_token}"

            expiration = str(int(time.time() + ttl_seconds))
            headers = {
                "authorization": f"bearer {token_jwt}",
                "apns-push-type": "voip",
                "apns-topic": f"{self.apns_bundle_id}.voip",
                "apns-priority": "10",
                "apns-expiration": expiration,
            }

            payload = {
                "aps": {},
                "call_uuid": data.get("call_uuid"),
                "caller_extension": data.get("caller_extension"),
                "caller_display_name": data.get("caller_display_name"),
                "callee_extension": data.get("callee_extension"),
                "action": data.get("action"),
                "ttl_seconds": ttl_seconds,
            }

            # APNs requires HTTP/2
            async with httpx.AsyncClient(http2=True, timeout=5.0) as client:
                resp = await client.post(url, json=payload, headers=headers)
                apns_id = resp.headers.get("apns-id", "")

                if resp.status_code == 200:
                    logger.info(f"[APNs SENT] device={device_id} apns_id={apns_id}")
                    return {
                        "device_id": device_id,
                        "platform": "ios",
                        "status": "sent",
                        "apns_id": apns_id,
                    }

                error_body = resp.text
                if resp.status_code in (400, 410):
                    logger.warning(f"[APNs INVALID] Token {masked} rejected ({resp.status_code}). Disabling in DB.")
                    disable_push_token(push_token)
                    return {
                        "device_id": device_id,
                        "platform": "ios",
                        "status": "unregistered",
                        "error": f"APNs rejected token: {error_body}",
                    }

                if resp.status_code == 403 and "ExpiredProviderToken" in error_body:
                    # Invalidate cached JWT token
                    self._apns_jwt = None
                    self._apns_jwt_expiry = 0.0

                logger.error(f"[APNs ERROR] HTTP {resp.status_code} for device={device_id}: {error_body}")
                return {
                    "device_id": device_id,
                    "platform": "ios",
                    "status": "provider_error",
                    "status_code": resp.status_code,
                    "error": error_body,
                }

        except Exception as ex:
            logger.error(f"[APNs EXCEPTION] Failed to dispatch to {device_id}: {ex}")
            return {
                "device_id": device_id,
                "platform": "ios",
                "status": "failed",
                "error": str(ex),
            }
