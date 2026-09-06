"""Tests for SGT VoIP Push Gateway endpoints and state handling."""

import os
import sys
import pytest
from httpx import AsyncClient, ASGITransport

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Set temporary database path for testing
test_db_path = "/tmp/test_sgt_gateway.db"
os.environ["GATEWAY_DB_PATH"] = test_db_path

from database import init_db
from main import app


@pytest.fixture(autouse=True)
def setup_teardown_db():
    if os.path.exists(test_db_path):
        os.remove(test_db_path)
    init_db(test_db_path)
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


@pytest.mark.anyio
async def test_register_and_query_device_token():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Register Android device for 202
        payload = {
            "extension": "202",
            "platform": "android",
            "device_id": "pixel-phone-uuid-1",
            "push_token": "mock_fcm_token_202_abc",
            "push_environment": "production",
            "app_version": "1.0.0",
        }
        res = await ac.post("/api/v1/devices/register", json=payload)
        assert res.status_code == 200
        assert res.json()["success"] is True

        # Query tokens for 202
        qres = await ac.get("/api/v1/devices/tokens/202")
        assert qres.status_code == 200
        qdata = qres.json()["data"]
        assert qdata["count"] == 1
        assert qdata["tokens"][0]["device_id"] == "pixel-phone-uuid-1"
        assert qdata["tokens"][0]["push_token"] == "mock_fcm_token_202_abc"


@pytest.mark.anyio
async def test_revoke_device_token():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # Register
        await ac.post(
            "/api/v1/devices/register",
            json={
                "extension": "201",
                "platform": "ios",
                "device_id": "iphone-uuid-123",
                "push_token": "mock_apns_token_201_xyz",
            },
        )
        # Verify active
        tokens = (await ac.get("/api/v1/devices/tokens/201")).json()["data"]
        assert tokens["count"] == 1

        # Revoke
        rres = await ac.post(
            "/api/v1/devices/revoke",
            json={"extension": "201", "device_id": "iphone-uuid-123"},
        )
        assert rres.status_code == 200
        assert rres.json()["data"]["revoked"] is True

        # Verify no longer active
        tokens_after = (await ac.get("/api/v1/devices/tokens/201")).json()["data"]
        assert tokens_after["count"] == 0


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
                "push_token": "fcm_token_202",
            },
        )

        # Trigger incoming push from Asterisk
        push_payload = {
            "call_uuid": "call-uuid-999-202",
            "caller_extension": "201",
            "caller_display_name": "Extension 201",
            "callee_extension": "202",
            "asterisk_uniqueid": "1725612345.1",
            "ttl_seconds": 30,
        }
        res = await ac.post("/api/v1/internal/push/incoming", json=push_payload)
        assert res.status_code == 200
        body = res.json()
        assert body["success"] is True
        assert body["data"]["sent_count"] == 1

        # Trigger cancel push (caller hung up)
        cancel_payload = {
            "call_uuid": "call-uuid-999-202",
            "reason": "caller_hangup",
        }
        cres = await ac.post("/api/v1/internal/push/cancel", json=cancel_payload)
        assert cres.status_code == 200
        assert cres.json()["success"] is True
        assert cres.json()["data"]["sent_count"] == 1


@pytest.mark.anyio
async def test_incoming_call_push_no_devices():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        push_payload = {
            "call_uuid": "call-uuid-empty",
            "caller_extension": "201",
            "callee_extension": "299",  # No device registered
        }
        res = await ac.post("/api/v1/internal/push/incoming", json=push_payload)
        assert res.status_code == 200
        body = res.json()
        assert body["success"] is False
        assert body["data"]["sent_count"] == 0
