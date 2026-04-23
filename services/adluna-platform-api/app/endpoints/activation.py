"""Aktivierungs-Flow: Email → Code per Mail → Code eintragen → Device-Token."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from loguru import logger
from sqlalchemy.orm import Session

from app.auth import client_ip, generate_activation_code, generate_token
from app.config import get_settings
from app.database import get_db
from app.emailer import send_activation_code
from app.models import ActivationCode, Device, License, Product, User
from app.schemas import (
    ActivationRequest,
    ActivationRequestResponse,
    ActivationVerify,
    ActivationVerifyResponse,
)


router = APIRouter()
settings = get_settings()


def _utcnow() -> datetime:
    return datetime.now(tz=timezone.utc).replace(tzinfo=None)


@router.post(
    "/activation/request",
    response_model=ActivationRequestResponse,
    summary="Aktivierungscode anfordern",
)
def request_activation(
    payload: ActivationRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Sendet einen 6-stelligen Einmal-Code an die Email.

    Rate-Limit: max. 3 Codes pro (Email, Product) in 60 Minuten. Wer das
    überreizt, bekommt `429 Too Many Requests` — brute-force unattraktiv.
    """
    # Product existiert & aktiv?
    product = (
        db.query(Product)
        .filter(Product.id == payload.product, Product.active == 1)
        .first()
    )
    if product is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product '{payload.product}' not found or inactive",
        )

    # User finden oder neu anlegen
    user = db.query(User).filter(User.email == str(payload.email)).first()
    if user is None:
        user = User(email=str(payload.email))
        db.add(user)
        db.flush()  # user.id verfügbar machen

    # Rate-Limit
    cutoff = _utcnow() - timedelta(hours=1)
    recent_count = (
        db.query(ActivationCode)
        .filter(
            ActivationCode.user_id == user.id,
            ActivationCode.product_id == product.id,
            ActivationCode.created_at > cutoff,
        )
        .count()
    )
    if recent_count >= 3:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many activation requests. Please try again in an hour.",
        )

    # Neuen Code erzeugen
    code = generate_activation_code()
    expires = _utcnow() + timedelta(minutes=settings.activation_code_ttl_minutes)
    entry = ActivationCode(
        user_id=user.id,
        product_id=product.id,
        code=code,
        device_uuid=payload.device_uuid,
        expires_at=expires,
        ip_address=client_ip(request),
    )
    db.add(entry)
    db.commit()

    # Mail schicken
    sent = send_activation_code(
        to_email=user.email,
        code=code,
        product_id=product.id,
        expires_in_minutes=settings.activation_code_ttl_minutes,
    )
    if not sent:
        logger.warning(f"Code created for {user.email}/{product.id} but mail send failed")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Email provider unavailable. Please try again shortly.",
        )

    return ActivationRequestResponse(
        ok=True,
        message=f"Code sent to {user.email}. Valid for {settings.activation_code_ttl_minutes} minutes.",
    )


@router.post(
    "/activation/verify",
    response_model=ActivationVerifyResponse,
    summary="Aktivierungscode einlösen, Device registrieren",
)
def verify_activation(
    payload: ActivationVerify,
    db: Session = Depends(get_db),
):
    """Lösst den 6-stelligen Code ein und registriert das Gerät.

    Ergebnis: Server-Token, das die App im Keychain speichert und bei
    jedem nachfolgenden `/license/check` als Bearer-Auth mitschickt.
    """
    # User + Code-Paar finden
    user = db.query(User).filter(User.email == str(payload.email)).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unknown email")

    product = db.query(Product).filter(Product.id == payload.product).first()
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Unknown product")

    entry = (
        db.query(ActivationCode)
        .filter(
            ActivationCode.user_id == user.id,
            ActivationCode.product_id == product.id,
            ActivationCode.code == payload.code,
            ActivationCode.device_uuid == payload.device_uuid,
            ActivationCode.used_at.is_(None),
            ActivationCode.expires_at > _utcnow(),
        )
        .order_by(ActivationCode.created_at.desc())
        .first()
    )
    if entry is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid, expired, or already-used code",
        )

    # User verifizieren
    if user.verified_at is None:
        user.verified_at = _utcnow()

    # Device-Limit pro (User, Product) prüfen — Default: max 3
    max_devices = 3
    existing_device_count = (
        db.query(Device)
        .filter(Device.user_id == user.id, Device.product_id == product.id)
        .count()
    )
    # Check ob das Device bereits existiert (Reaktivierung)
    existing_device = (
        db.query(Device)
        .filter(
            Device.user_id == user.id,
            Device.product_id == product.id,
            Device.device_uuid == payload.device_uuid,
        )
        .first()
    )
    if existing_device is None and existing_device_count >= max_devices:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Device limit ({max_devices}) reached for this product. Revoke an existing device first.",
        )

    # Device anlegen oder Token rotieren
    token = generate_token()
    if existing_device is None:
        device = Device(
            user_id=user.id,
            product_id=product.id,
            device_uuid=payload.device_uuid,
            token=token,
        )
        db.add(device)
        db.flush()
        license_entry = License(
            device_id=device.id,
            status="beta" if settings.beta_mode_global else "trial",
            tier="full",
            trial_expires_at=(
                None if settings.beta_mode_global
                else _utcnow() + timedelta(days=product.default_trial_days or settings.default_trial_days)
            ),
        )
        db.add(license_entry)
    else:
        existing_device.token = token
        device = existing_device

    # Code als verwendet markieren
    entry.used_at = _utcnow()
    db.commit()
    db.refresh(device)

    status_str = device.license.status if device.license else "beta"
    tier_str = device.license.tier if device.license else "full"

    logger.info(
        f"Activation verified: user={user.email} product={product.id} "
        f"device={payload.device_uuid[:12]}… status={status_str}"
    )

    return ActivationVerifyResponse(
        ok=True,
        token=token,
        status=status_str,  # type: ignore[arg-type]
        tier=tier_str,  # type: ignore[arg-type]
        message="Device activated successfully.",
    )
