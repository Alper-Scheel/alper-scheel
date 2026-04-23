"""Seed-Skript: Initiale Produkt-Einträge + Server-Config.

Wird einmal nach erstem `alembic upgrade head` ausgeführt:

    python -m seed

Idempotent: vorhandene Einträge werden nicht überschrieben.
"""
from __future__ import annotations

from datetime import datetime

from loguru import logger

from app.database import SessionLocal
from app.models import Product, ServerConfig


PRODUCTS: list[dict] = [
    {
        "id": "alva-text",
        "name": "ALVA-TEXT",
        "slug": "alva-text",
        "default_trial_days": 14,
        "paddle_product_id": None,  # wird bei Monetarisierungs-Phase gefüllt
        "price_eur": None,          # initial kostenlos / Beta
        "active": 1,
    },
    # Platzhalter für kommende Produkte (inaktiv bis Launch):
    # {
    #     "id": "alva-macos",
    #     "name": "ALVA (macOS Full)",
    #     "slug": "alva-macos",
    #     "default_trial_days": 14,
    #     "active": 0,
    # },
]

SERVER_CONFIG: list[tuple[str, str]] = [
    ("beta_mode_global", "true"),
    ("seeded_at", datetime.utcnow().isoformat()),
]


def seed() -> None:
    db = SessionLocal()
    try:
        # Products
        for p in PRODUCTS:
            existing = db.query(Product).filter(Product.id == p["id"]).first()
            if existing is None:
                db.add(Product(**p))
                logger.info(f"Product created: {p['id']}")
            else:
                logger.info(f"Product already exists, skipping: {p['id']}")

        # Server-Config
        for key, value in SERVER_CONFIG:
            existing = db.query(ServerConfig).filter(ServerConfig.key == key).first()
            if existing is None:
                db.add(ServerConfig(key=key, value=value))
                logger.info(f"ServerConfig created: {key}={value}")
            else:
                logger.info(f"ServerConfig already exists, skipping: {key}")

        db.commit()
        logger.success("Seed complete.")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed()
