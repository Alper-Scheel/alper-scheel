"""Laufender License-Check + Device-Verwaltung."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.auth import client_ip, require_device_token
from app.config import get_settings
from app.database import get_db
from app.models import Device, License, LicenseCheck
from app.schemas import (
    DeviceListRequest,
    DeviceListResponse,
    DeviceInfo,
    DeviceRevokeRequest,
    LicenseCheckRequest,
    LicenseCheckResponse,
)


router = APIRouter()
settings = get_settings()


def _utcnow() -> datetime:
    return datetime.now(tz=timezone.utc).replace(tzinfo=None)


def _resolve_status(device: Device) -> tuple[str, str, str]:
    """Kill-Switch-Logik: was antwortet der Server diesem Device?

    Reihenfolge:
      1. License revoked → status=revoked
      2. beta_mode_global + nicht revoked → status=beta, tier=full
      3. License paid → status=active, tier=paid
      4. License trial + nicht abgelaufen → status=trial, tier=full
      5. Sonst → status=expired, tier=limited
    """
    lic = device.license
    if lic is None:
        return ("invalid", "limited", "No license record. Please re-activate.")

    if lic.status == "revoked":
        return ("revoked", "limited", "This device has been revoked.")

    if settings.beta_mode_global:
        return ("beta", "full", "Beta access active. Thanks for testing!")

    if lic.status == "active" and lic.tier == "paid":
        return ("active", "paid", "Thank you for your purchase.")

    if lic.status == "trial" and lic.trial_expires_at and lic.trial_expires_at > _utcnow():
        return ("trial", "full", "Trial active.")

    return ("expired", "limited", "Trial expired. Please purchase to continue.")


@router.post(
    "/license/check",
    response_model=LicenseCheckResponse,
    summary="Laufender Status-Check (App pingt täglich)",
)
def license_check(
    payload: LicenseCheckRequest,
    request: Request,
    db: Session = Depends(get_db),
    device: Device = Depends(require_device_token),
):
    # device_uuid + product müssen zum Token passen (anti-replay)
    if device.device_uuid != payload.device_uuid or device.product_id != payload.product:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not match provided device/product",
        )

    # Last-check-Felder aktualisieren
    device.last_check_at = _utcnow()
    device.last_check_ip = client_ip(request)
    if payload.app_version:
        device.app_version = payload.app_version

    status_str, tier_str, message = _resolve_status(device)

    # Audit-Log
    db.add(LicenseCheck(
        device_id=device.id,
        status_returned=status_str,
        ip_address=client_ip(request),
        app_version=payload.app_version,
    ))
    db.commit()

    return LicenseCheckResponse(
        status=status_str,  # type: ignore[arg-type]
        tier=tier_str,  # type: ignore[arg-type]
        message=message,
        check_again_in=settings.license_check_ttl_seconds,
        trial_expires_at=device.license.trial_expires_at if device.license else None,
    )


@router.post(
    "/device/list",
    response_model=DeviceListResponse,
    summary="Alle Devices eines Nutzers für ein Produkt",
)
def list_devices(
    payload: DeviceListRequest,
    db: Session = Depends(get_db),
    caller: Device = Depends(require_device_token),
):
    """Gibt Liste aller Geräte zum gleichen Account+Product zurück.

    Der Caller muss sich mit einem Device-Token desselben Users+Products
    authentifizieren. So kann der Nutzer über die App andere Geräte
    sehen und via `/device/revoke` entfernen.
    """
    # Sicherheit: nur eigene User-Daten dürfen abgerufen werden
    if caller.user.email != str(payload.email) or caller.product_id != payload.product:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Token does not authorize access to requested data",
        )

    devices = (
        db.query(Device)
        .filter(Device.user_id == caller.user_id, Device.product_id == payload.product)
        .all()
    )

    infos = []
    for d in devices:
        infos.append(DeviceInfo(
            device_uuid=d.device_uuid,
            device_name=d.device_name,
            platform=d.platform,
            activated_at=d.activated_at,
            last_check_at=d.last_check_at,
            status=d.license.status if d.license else "unknown",
            tier=d.license.tier if d.license else "unknown",
        ))
    return DeviceListResponse(devices=infos)


@router.post(
    "/device/revoke",
    summary="Device-Zugang widerrufen (setzt License auf revoked)",
)
def revoke_device(
    payload: DeviceRevokeRequest,
    db: Session = Depends(get_db),
    caller: Device = Depends(require_device_token),
):
    """Setzt License-Status = revoked. Token wird beim nächsten Check abgelehnt."""
    target = (
        db.query(Device)
        .filter(
            Device.user_id == caller.user_id,
            Device.product_id == payload.product,
            Device.device_uuid == payload.device_uuid,
        )
        .first()
    )
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found",
        )
    if target.license is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Device has no license record",
        )
    target.license.status = "revoked"
    target.license.revoked_at = _utcnow()
    target.license.revoked_reason = "User-initiated revoke"
    db.commit()
    return {"ok": True, "message": f"Device {payload.device_uuid[:12]}… revoked."}
