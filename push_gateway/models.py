"""Data models for SGT VoIP Push Gateway."""

from typing import Optional, Literal
from pydantic import BaseModel, Field


class DeviceRegisterRequest(BaseModel):
    extension: str = Field(..., description="Extension number, e.g. 201 or 202")
    platform: Literal["android", "ios"] = Field(..., description="Target mobile OS")
    device_id: str = Field(..., description="Unique device installation ID")
    push_token: str = Field(..., description="FCM token or Apple VoIP device token")
    push_environment: Literal["development", "production"] = Field(
        default="production", description="APNs / FCM push environment"
    )
    app_version: Optional[str] = Field(default=None, description="App version string")


class DeviceRevokeRequest(BaseModel):
    extension: str
    device_id: str


class IncomingPushRequest(BaseModel):
    call_uuid: str = Field(..., description="Unique Call ID (from SIP / Asterisk)")
    caller_extension: str = Field(..., description="Caller extension, e.g. 201")
    caller_display_name: Optional[str] = Field(default=None, description="Caller display name")
    callee_extension: str = Field(..., description="Callee extension, e.g. 202")
    asterisk_uniqueid: Optional[str] = Field(default=None, description="Asterisk Channel Unique ID")
    ttl_seconds: int = Field(default=30, ge=5, le=120, description="Push and call TTL in seconds")


class CancelPushRequest(BaseModel):
    call_uuid: str = Field(..., description="Call UUID to cancel")
    reason: Optional[str] = Field(default="caller_hangup", description="Cancellation reason")


class CallEventRequest(BaseModel):
    call_uuid: str
    status: Literal["ringing", "answered", "declined", "cancelled", "expired", "failed"]
    details: Optional[str] = None


class ApiResponse(BaseModel):
    success: bool
    message: str
    data: Optional[dict] = None
