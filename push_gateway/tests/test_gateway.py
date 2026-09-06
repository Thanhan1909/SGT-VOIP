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
            "ttl_seconds": 30,
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
    main.push_sender.test_mode = False
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


@pytest.mark.anyio
async def test_request_size_limit():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Attempt sending oversized payload (> 32KB)
        huge_payload = {"huge_data": "A" * 35000}
        res = await ac.post("/api/v1/devices/register", json=huge_payload, headers=DEVICE_HEADERS)
        assert res.status_code == 413
