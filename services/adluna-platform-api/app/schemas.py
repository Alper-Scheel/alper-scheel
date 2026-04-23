"""Pydantic Request/Response-Modelle.

Separat von SQLAlchemy-Modellen, damit Serialization und DB-Layer
unabhängig voneinander evolvieren können.
"""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field


# ----- /v1/activation/* -----

class ActivationRequest(BaseModel):
    email: EmailStr
    product: str = Field(..., min_length=1, max_length=64)
    device_uuid: str = Field(..., min_length=1, max_length=128)
    device_name: str | None = Field(None, max_length=128)
    platform: str | None = Field(None, max_length=32)
    app_version: str | None = Field(None, max_length=32)


class ActivationRequestResponse(BaseModel):
    ok: bool
    message: str


class ActivationVerify(BaseModel):
    email: EmailStr
    product: str
    code: str = Field(..., min_length=6, max_length=16)
    device_uuid: str


class ActivationVerifyResponse(BaseModel):
    ok: bool
    token: str
    status: Literal["beta", "trial", "active"]
    tier: Literal["full", "limited", "paid"]
    message: str


# ----- /v1/license/check -----

class LicenseCheckRequest(BaseModel):
    product: str
    device_uuid: str
    app_version: str | None = None


class LicenseCheckResponse(BaseModel):
    status: Literal["beta", "trial", "active", "expired", "revoked", "invalid"]
    tier: Literal["full", "limited", "paid"]
    message: str
    check_again_in: int = Field(..., description="Sekunden bis zum nächsten Check")
    trial_expires_at: datetime | None = None


# ----- /v1/device/* -----

class DeviceInfo(BaseModel):
    device_uuid: str
    device_name: str | None
    platform: str | None
    activated_at: datetime
    last_check_at: datetime | None
    status: str
    tier: str

    model_config = {"from_attributes": True}


class DeviceListRequest(BaseModel):
    email: EmailStr
    product: str


class DeviceListResponse(BaseModel):
    devices: list[DeviceInfo]


class DeviceRevokeRequest(BaseModel):
    device_uuid: str
    product: str


# ----- Admin -----

class UserSummary(BaseModel):
    email: EmailStr
    verified: bool
    device_count: int
    first_activated_at: datetime | None
    last_check_at: datetime | None

    model_config = {"from_attributes": True}


class AdminStatsResponse(BaseModel):
    total_users: int
    verified_users: int
    active_devices: int
    checks_last_24h: int
    products: list[str]


# ----- Generic Health/Error -----

class HealthResponse(BaseModel):
    ok: Literal[True] = True
    service: str = "adluna-platform-api"
    version: str
    env: str


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
