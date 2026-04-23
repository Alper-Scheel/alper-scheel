"""Auth-Utilities: Token-Erzeugung, Bearer-Auth-Dependency, Admin-Guard."""
from __future__ import annotations

import secrets

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.models import Device

_bearer = HTTPBearer(auto_error=False)


def generate_token() -> str:
    """Erzeuge ein 64-Byte URL-safe Token für Device-Auth."""
    return secrets.token_urlsafe(64)


def generate_activation_code() -> str:
    """Erzeuge einen 6-stelligen Einmal-Code (nur Ziffern, gut vorlesbar)."""
    # 6 Zeichen, jeweils 0-9 — das ist 1:1_000_000, ausreichend sicher für
    # 15-min-TTL + Rate-Limiting.
    return "".join(secrets.choice("0123456789") for _ in range(6))


def require_device_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Device:
    """FastAPI-Dependency: validiert Bearer-Token, liefert zugehöriges Device."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer token required",
        )
    device = db.query(Device).filter(Device.token == credentials.credentials).first()
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or revoked token",
        )
    return device


def require_admin_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> None:
    """FastAPI-Dependency: prüft, ob Bearer-Token === ADLUNA_ADMIN_TOKEN.

    Nutzt `secrets.compare_digest` für konstante Zeitvergleich (timing-safe).
    """
    settings = get_settings()
    expected = settings.adluna_admin_token

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Admin bearer token required",
        )

    if not secrets.compare_digest(credentials.credentials.encode(), expected.encode()):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin token",
        )


def client_ip(request: Request) -> str:
    """Ermittelt Client-IP unter Beachtung von Cloudflare/Reverse-Proxy-Headern."""
    # Cloudflare setzt CF-Connecting-IP (am vertrauenswürdigsten auf Tunnel)
    cf_ip = request.headers.get("cf-connecting-ip")
    if cf_ip:
        return cf_ip
    # Generic X-Forwarded-For
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    # Fallback: direkter Client
    return request.client.host if request.client else "unknown"
