"""Data models for SGT VoIP Push Gateway with security validation."""

from typing import Optional, Literal, Dict, Any
from pydantic import BaseModel, Field, constr


class DeviceRegisterRequest(BaseModel):
    extension: constr(strip_whitespace=True, min_length=2, max_length=10, pattern=r"^[0-9]+$") = Field(
        ..., description="Numeric extension number, e.g. 201 or 202"
    )
    platform: Literal["android", "ios"] = Field(..., description="Target mobile OS")
    device_id: constr(strip_whitespace=True, min_length=4, max_length=128) = Field(
        ..., description="Unique device installation ID"
    )
    push_token: constr(strip_whitespace=True, min_length=10, max_length=512) = Field(
        ..., description="FCM token or Apple VoIP device token"
    )
    push_environment: Literal["development", "production"] = Field(
        default="production", description="APNs / FCM push environment"
    )
    app_version: Optional[str] = Field(default=None, max_length=32, description="App version string")
    auth_token: Optional[str] = Field(default=None, description="Client authentication credential")


class DeviceRevokeRequest(BaseModel):
    extension: constr(strip_whitespace=True, min_length=2, max_length=10, pattern=r"^[0-9]+$")
    device_id: constr(strip_whitespace=True, min_length=4, max_length=128)
    auth_token: Optional[str] = Field(default=None, description="Client authentication credential")


class IncomingPushRequest(BaseModel):
    call_uuid: constr(strip_whitespace=True, min_length=4, max_length=128) = Field(
        ..., description="Canonical Call ID (from SIP / Asterisk)"
    )
    caller_extension: constr(strip_whitespace=True, min_length=2, max_length=32) = Field(
        ..., description="Caller extension or number"
    )
    caller_display_name: Optional[str] = Field(default=None, max_length=64, description="Caller display name")
    callee_extension: constr(strip_whitespace=True, min_length=2, max_length=32) = Field(
        ..., description="Callee extension or number"
    )
    asterisk_uniqueid: Optional[str] = Field(default=None, max_length=64, description="Asterisk Channel Unique ID")
    ttl_seconds: int = Field(default=30, ge=5, le=120, description="Push and call TTL in seconds")


class CancelPushRequest(BaseModel):
    call_uuid: constr(strip_whitespace=True, min_length=4, max_length=128) = Field(
        ..., description="Call UUID to cancel"
    )
    reason: Optional[str] = Field(default="caller_hangup", max_length=64, description="Cancellation reason")


class CallEventRequest(BaseModel):
    call_uuid: constr(strip_whitespace=True, min_length=4, max_length=128)
    status: Literal["ringing", "answered", "declined", "cancelled", "expired", "failed"]
    details: Optional[str] = Field(default=None, max_length=256)


class ApiResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
