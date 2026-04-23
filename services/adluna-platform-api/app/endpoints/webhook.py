"""Paddle-Webhook: Zahlung eingegangen → License auf paid schalten.

Dieses Modul ist ein STUB für Phase 2. Sobald Paddle als Payment-Provider
live ist, wird die Signatur-Verifikation aktiviert und die Payload gemappt.
"""
from __future__ import annotations

from fastapi import APIRouter, Request, status
from loguru import logger


router = APIRouter()


@router.post("/webhook/paddle", status_code=status.HTTP_202_ACCEPTED)
async def paddle_webhook(request: Request):
    """Akzeptiert Paddle-Events und loggt sie (Phase 1: nur Logging).

    In Phase 2:
      1. Paddle-Signature aus `Paddle-Signature` Header via HMAC verifizieren
      2. Event-Type parsen (`transaction.completed`)
      3. Email aus `data.customer.email` extrahieren
      4. Paddle-Product-ID → product_id mappen
      5. Alle `devices` des Users bei diesem Produkt → `licenses.status=paid`
      6. Bestätigungsmail senden
    """
    payload = await request.json()
    logger.info(f"Paddle webhook received (stub): {payload.get('event_type', 'unknown')}")
    return {"ok": True, "note": "Stub — full handling implemented in monetization phase"}
