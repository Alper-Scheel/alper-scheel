"""Admin-Endpunkte (Bearer-Auth via ADLUNA_ADMIN_TOKEN).

Minimales Set für Phase 1. Spätere Web-Dashboard-Integration kann auf
diesen Endpunkten aufbauen.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.auth import require_admin_token
from app.database import get_db
from app.models import Device, LicenseCheck, Product, User
from app.schemas import AdminStatsResponse


router = APIRouter(dependencies=[Depends(require_admin_token)])


def _utcnow() -> datetime:
    return datetime.now(tz=timezone.utc).replace(tzinfo=None)


@router.get("/stats", response_model=AdminStatsResponse)
def get_stats(db: Session = Depends(get_db)):
    """High-level Überblick."""
    total_users = db.query(func.count(User.id)).scalar() or 0
    verified_users = db.query(func.count(User.id)).filter(User.verified_at.isnot(None)).scalar() or 0
    active_devices = db.query(func.count(Device.id)).scalar() or 0

    last_24h = _utcnow() - timedelta(hours=24)
    checks_last_24h = (
        db.query(func.count(LicenseCheck.id))
        .filter(LicenseCheck.timestamp > last_24h)
        .scalar() or 0
    )

    products = [p.id for p in db.query(Product.id).all()]

    return AdminStatsResponse(
        total_users=total_users,
        verified_users=verified_users,
        active_devices=active_devices,
        checks_last_24h=checks_last_24h,
        products=products,
    )


@router.get("/users")
def list_users(product: str | None = None, db: Session = Depends(get_db)):
    """Alle Nutzer, optional gefiltert nach Produkt."""
    if product:
        users_q = (
            db.query(User)
            .join(Device, Device.user_id == User.id)
            .filter(Device.product_id == product)
            .distinct()
        )
    else:
        users_q = db.query(User)
    users = users_q.all()
    return [
        {
            "email": u.email,
            "verified": u.verified_at is not None,
            "created_at": u.created_at,
            "device_count": len(u.devices),
        }
        for u in users
    ]


@router.get("/user/{email}")
def get_user(email: str, db: Session = Depends(get_db)):
    """Detailansicht eines Users inkl. aller Devices und deren Lizenzen."""
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return {
        "email": user.email,
        "verified_at": user.verified_at,
        "created_at": user.created_at,
        "notes": user.notes,
        "devices": [
            {
                "device_uuid": d.device_uuid,
                "device_name": d.device_name,
                "platform": d.platform,
                "product_id": d.product_id,
                "activated_at": d.activated_at,
                "last_check_at": d.last_check_at,
                "app_version": d.app_version,
                "license": {
                    "status": d.license.status,
                    "tier": d.license.tier,
                    "trial_expires_at": d.license.trial_expires_at,
                    "paid_at": d.license.paid_at,
                    "revoked_at": d.license.revoked_at,
                } if d.license else None,
            }
            for d in user.devices
        ],
    }


@router.delete("/user/{email}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(email: str, db: Session = Depends(get_db)):
    """DSGVO-Löschung: kaskadiert Devices + Codes + Checks."""
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    db.delete(user)
    db.commit()
    return None
