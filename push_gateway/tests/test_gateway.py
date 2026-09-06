"""Unit tests for SGT VoIP Push Gateway endpoints, security, and provider handling."""

import os
import sys
import pytest
from httpx import AsyncClient, ASGITransport

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

test_db_path = "/tmp/test_sgt_gateway.db"
os.environ["GATEWAY_DB_PATH"] = test_db_path
os.environ["GATEWAY_TEST_MODE"] = "1"
os.environ["INTERNAL_API_SECRET"] = "test_internal_secret_123"
os.environ["DEVICE_AUTH_SECRET"] = "test_device_secret_456"

from database import init_db, get_connection
import main
from main import app

INTERNAL_HEADERS = {"X-Internal-Secret": "test_internal_secret_123"}
DEVICE_HEADERS = {"X-Device-Auth-Token": "test_device_secret_456"}


@pytest.fixture(autouse=True)
def setup_teardown_db():
    if os.path.exists(test_db_path):
        os.remove(test_db_path)
    init_db(test_db_path)
    # Ensure push_sender runs with test_mode
    main.push_sender.test_mode = True
    main.INTERNAL_API_SECRET = "test_internal_secret_123"
    main.DEVICE_AUTH_SECRET = "test_device_secret_456"
    yield
    if os.path.exists(test_db_path):
        os.remove(test_db_path)


@pytest.mark.anyio
async def test_health():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/health")
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["data"]["service"] == "sgt-push-gateway"
        assert "providers" in data["data"]
        assert "fcm" in data["data"]["providers"]
        assert "apns" in data["data"]["providers"]


@pytest.mark.anyio
async def test_device_auth_protection():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        payload = {
            "extension": "202",
            "platform": "android",
            "device_id": "pixel-phone-uuid-1",
            "push_token": "mock_fcm_token_202_abc_test",
        }
        # 1. Missing auth header -> 401
        res_no_auth = await ac.post("/api/v1/devices/register", json=payload)
        assert res_no_auth.status_code == 401

        # 2. Wrong auth header -> 403
        res_bad_auth = await ac.post(
            "/api/v1/devices/register",
            json=payload,
            headers={"X-Device-Auth-Token": "wrong_secret"},
        )
        assert res_bad_auth.status_code == 403

        # 3. Valid auth header -> 200
        res_ok = await ac.post(
            "/api/v1/devices/register",
            json=payload,
            headers=DEVICE_HEADERS,
        )
        assert res_ok.status_code == 200
        assert res_ok.json()["success"] is True


@pytest.mark.anyio
async def test_internal_auth_and_token_masking():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Register device with real-looking raw token
        raw_token = "fcm_very_secret_token_123456789_abcdef"
        await ac.post(
            "/api/v1/devices/register",
            json={
                "extension": "201",
                "platform": "ios",
                "device_id": "iphone-uuid-1",
                "push_token": raw_token,
            },
            headers=DEVICE_HEADERS,
        )

        # 1. Internal query without secret -> 401
        res_unauth = await ac.get("/api/v1/devices/tokens/201")
        assert res_unauth.status_code == 401

        # 2. Internal query with wrong secret -> 403
        res_forbidden = await ac.get(
            "/api/v1/devices/tokens/201",
            headers={"X-Internal-Secret": "invalid_secret"},
        )
        assert res_forbidden.status_code == 403

        # 3. Internal query with valid secret -> 200
        res_ok = await ac.get("/api/v1/devices/tokens/201", headers=INTERNAL_HEADERS)
        assert res_ok.status_code == 200
        tokens = res_ok.json()["data"]["tokens"]
        assert len(tokens) == 1
        # Token MUST be redacted/masked, never raw!
        assert tokens[0]["push_token"] != raw_token
        assert "..." in tokens[0]["push_token"]
        assert raw_token not in res_ok.text


@pytest.mark.anyio
async def test_incoming_call_push_flow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Register device for callee 202
        await ac.post(
            "/api/v1/devices/register",
            json={
                "extension": "202",
                "platform": "android",
                "device_id": "device-202-a",
                "push_token": "fcm_token_202_abcdef12345",
            },
            headers=DEVICE_HEADERS,
        )

        # Trigger incoming push from Asterisk with internal secret
        push_payload = {
            "call_uuid": "call-uuid-999-202",
            "caller_extension": "201",
            "caller_display_name": "Extension 201",
            "callee_extension": "202",
            "asterisk_uniqueid": "1725612345.1",
            "ttl_seconds": 45,
        }
        res = await ac.post("/api/v1/internal/push/incoming", json=push_payload, headers=INTERNAL_HEADERS)
        assert res.status_code == 200
        body = res.json()
        assert body["success"] is True
        assert body["data"]["sent_count"] == 1

        # Trigger cancel push (caller hung up)
        cancel_payload = {
            "call_uuid": "call-uuid-999-202",
            "reason": "caller_hangup",
        }
        cres = await ac.post("/api/v1/internal/push/cancel", json=cancel_payload, headers=INTERNAL_HEADERS)
        assert cres.status_code == 200
        assert cres.json()["success"] is True
        assert cres.json()["data"]["sent_count"] == 1


@pytest.mark.anyio
async def test_unconfigured_provider_does_not_claim_success():
    """In production mode without credentials, push must report provider_not_configured."""
    orig_creds = main.push_sender.firebase_credentials_path
    main.push_sender.test_mode = False
    main.push_sender.firebase_credentials_path = "/nonexistent/credentials.json"
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            await ac.post(
                "/api/v1/devices/register",
                json={
                    "extension": "202",
                    "platform": "android",
                    "device_id": "device-202-prod",
                    "push_token": "fcm_token_real_format_12345",
                },
                headers=DEVICE_HEADERS,
            )

            push_payload = {
                "call_uuid": "call-uuid-prod-test",
                "caller_extension": "201",
                "callee_extension": "202",
            }
            res = await ac.post("/api/v1/internal/push/incoming", json=push_payload, headers=INTERNAL_HEADERS)
            assert res.status_code == 200
            body = res.json()
            # NOT considered successful because credentials are missing
            assert body["success"] is False
            assert body["data"]["sent_count"] == 0
            delivery = body["data"]["deliveries"][0]
            assert delivery["status"] == "provider_not_configured"
    finally:
        main.push_sender.firebase_credentials_path = orig_creds
        main.push_sender.test_mode = True


@pytest.mark.anyio
async def test_request_size_limit():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Attempt sending oversized payload (> 32KB)
        huge_payload = {"huge_data": "A" * 35000}
        res = await ac.post("/api/v1/devices/register", json=huge_payload, headers=DEVICE_HEADERS)
        assert res.status_code == 413


@pytest.mark.anyio
async def test_webpush_subscribe_and_revoke():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        payload = {
            "extension": "202",
            "device_id": "iphone-safari-pwa-1",
            "endpoint": "https://web.push.apple.com/test-endpoint-sub-123",
            "p256dh": "BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvSoP10GLWnvw998Q4WfYnZMnGvNPE16OEPwAOWpGpxynoFXigWC8=",
            "auth": "tBHItJI5svbpez7KI4CCXg==",
        }
        # 1. Unauthorized access attempt without internal secret
        res_unauth = await ac.post("/api/v1/internal/webpush/subscribe", json=payload)
        assert res_unauth.status_code == 401

        # 2. Valid subscription
        res_sub = await ac.post("/api/v1/internal/webpush/subscribe", json=payload, headers=INTERNAL_HEADERS)
        assert res_sub.status_code == 200
        assert res_sub.json()["success"] is True

        # 3. Idempotent re-subscription
        res_sub2 = await ac.post("/api/v1/internal/webpush/subscribe", json=payload, headers=INTERNAL_HEADERS)
        assert res_sub2.status_code == 200

        # 4. Unsubscribe
        res_unsub = await ac.post(
            "/api/v1/internal/webpush/unsubscribe",
            json={"endpoint": payload["endpoint"]},
            headers=INTERNAL_HEADERS,
        )
        assert res_unsub.status_code == 200
        assert res_unsub.json()["data"]["revoked"] is True


@pytest.mark.anyio
async def test_webpush_incoming_call_flow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Register Web Push subscription for 202
        await ac.post(
            "/api/v1/internal/webpush/subscribe",
            json={
                "extension": "202",
                "device_id": "iphone-pwa-device-202",
                "endpoint": "https://web.push.apple.com/endpoint-202",
                "p256dh": "mock_p256dh_202_key",
                "auth": "mock_auth_202_secret",
            },
            headers=INTERNAL_HEADERS,
        )

        # Incoming call from 201 to 202
        call_payload = {
            "call_uuid": "call-webpush-uuid-456",
            "caller_extension": "201",
            "caller_display_name": "Sale 201",
            "callee_extension": "202",
            "ttl_seconds": 45,
        }
        res_call = await ac.post("/api/v1/internal/push/incoming", json=call_payload, headers=INTERNAL_HEADERS)
        assert res_call.status_code == 200
        body = res_call.json()
        assert body["success"] is True
        assert body["data"]["sent_count"] == 1
        assert body["data"]["deliveries"][0]["platform"] == "webpush"


@pytest.mark.anyio
async def test_call_state_and_expiration():
    from datetime import datetime, timezone, timedelta
    from database import get_connection

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        call_uuid = "call-expire-test-789"
        call_payload = {
            "call_uuid": call_uuid,
            "caller_extension": "201",
            "caller_display_name": "Sale 201",
            "callee_extension": "202",
            "ttl_seconds": 45,
        }
        # Register a token so trigger succeeds
        await ac.post(
            "/api/v1/internal/webpush/subscribe",
            json={
                "extension": "202",
                "device_id": "device-expire-test",
                "endpoint": "https://web.push.apple.com/endpoint-expire",
                "p256dh": "key",
                "auth": "auth",
            },
            headers=INTERNAL_HEADERS,
        )
        await ac.post("/api/v1/internal/push/incoming", json=call_payload, headers=INTERNAL_HEADERS)

        # 1. State while within deadline
        res_state1 = await ac.get(f"/api/v1/internal/call/state/{call_uuid}", headers=INTERNAL_HEADERS)
        assert res_state1.status_code == 200
        data1 = res_state1.json()["data"]
        assert data1["status"] == "ringing"
        assert data1["is_ringing"] is True
        assert data1["is_expired"] is False

        # 2. Simulate expired call by updating expires_at to 10 seconds ago
        past_time = (datetime.now(timezone.utc) - timedelta(seconds=10)).isoformat()
        with get_connection(test_db_path) as conn:
            conn.execute("UPDATE voip_calls SET expires_at=? WHERE call_uuid=?", (past_time, call_uuid))
            conn.commit()

        # 3. State after deadline
        res_state2 = await ac.get(f"/api/v1/internal/call/state/{call_uuid}", headers=INTERNAL_HEADERS)
        assert res_state2.status_code == 200
        data2 = res_state2.json()["data"]
        assert data2["status"] == "expired"
        assert data2["is_ringing"] is False
        assert data2["is_expired"] is True


@pytest.mark.anyio
async def test_vapid_public_key_endpoint():
    main.push_sender.vapid_public_key = "test_vapid_public_key_base64url_string"
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/api/v1/webpush/vapid-public-key")
        assert res.status_code == 200
        body = res.json()
        assert body["success"] is True
        assert body["data"]["public_key"] == "test_vapid_public_key_base64url_string"
