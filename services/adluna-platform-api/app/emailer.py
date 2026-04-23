"""Resend-Integration für Transaktionsmails.

Kapselt den Resend-Client und stellt typisierte Send-Funktionen bereit.
Jede Funktion ist idempotent und loggt Erfolge/Fehler via loguru.
"""
from __future__ import annotations

import resend
from loguru import logger

from app.config import get_settings


_settings = get_settings()
resend.api_key = _settings.resend_api_key


def _product_display_name(product_id: str) -> str:
    """Produkt-ID → nutzerfreundlicher Name für Mail-Texte."""
    mapping = {
        "alva-text": "ALVA-TEXT",
        "alva-macos": "ALVA (macOS)",
        "alva-voice-ios": "ALVA Voice (iOS)",
    }
    return mapping.get(product_id, product_id)


def send_activation_code(
    to_email: str,
    code: str,
    product_id: str,
    expires_in_minutes: int,
) -> bool:
    """Schickt einen Aktivierungscode an den Nutzer.

    Gibt `True` bei Erfolg zurück, `False` bei Fehler (logged).
    """
    product_name = _product_display_name(product_id)

    subject = f"Dein {product_name}-Aktivierungscode"

    html = f"""\
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; color: #111; max-width: 560px; margin: 40px auto; padding: 20px; line-height: 1.55;">
  <h2 style="margin-top: 0;">Dein {product_name}-Aktivierungscode</h2>
  <p>Hallo,</p>
  <p>dein Aktivierungscode lautet:</p>
  <p style="font-size: 32px; letter-spacing: 4px; font-weight: 600; font-family: 'SF Mono', Menlo, monospace; background: #f4f4f6; padding: 16px 24px; border-radius: 8px; text-align: center;">{code}</p>
  <p>Der Code ist <strong>{expires_in_minutes} Minuten</strong> gültig. Bitte in {product_name} eingeben.</p>
  <p style="color: #666; font-size: 14px; margin-top: 32px;">Falls du diesen Code nicht angefordert hast, kannst du diese E-Mail ignorieren.</p>
  <hr style="border: none; border-top: 1px solid #eee; margin-top: 32px;">
  <p style="color: #888; font-size: 12px;">AdLuna GmbH — Berlin<br>Diese Nachricht ist eine automatisierte Transaktionsmail.</p>
</body></html>
"""

    plaintext = f"""\
Dein {product_name}-Aktivierungscode

Hallo,

dein Aktivierungscode lautet: {code}

Der Code ist {expires_in_minutes} Minuten gültig. Bitte in {product_name} eingeben.

Falls du diesen Code nicht angefordert hast, kannst du diese E-Mail ignorieren.

—
AdLuna GmbH — Berlin
Automatisierte Transaktionsmail
"""

    try:
        resp = resend.Emails.send({
            "from": f"{_settings.resend_from_name} <{_settings.resend_from_email}>",
            "to": [to_email],
            "subject": subject,
            "html": html,
            "text": plaintext,
        })
        logger.info(f"Activation code sent to {to_email} for {product_id} (message_id={resp.get('id')})")
        return True
    except Exception as e:
        logger.error(f"Failed to send activation code to {to_email}: {e}")
        return False


def send_payment_confirmation(
    to_email: str,
    product_id: str,
    amount_eur: float,
) -> bool:
    """Schickt eine Kauf-Bestätigung nach erfolgreicher Paddle-Zahlung."""
    product_name = _product_display_name(product_id)
    subject = f"Kaufbestätigung: {product_name}"

    html = f"""\
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif; color: #111; max-width: 560px; margin: 40px auto; padding: 20px; line-height: 1.55;">
  <h2 style="margin-top: 0;">Vielen Dank für deinen Kauf</h2>
  <p>Hallo,</p>
  <p>dein Kauf von <strong>{product_name}</strong> für <strong>{amount_eur:.2f} EUR</strong> ist erfolgreich bestätigt.</p>
  <p>Die App sollte ab sofort ohne Einschränkungen funktionieren. Falls nicht: beende sie einmal, starte sie neu.</p>
  <p>Fragen? Antworte einfach auf diese Mail.</p>
  <hr style="border: none; border-top: 1px solid #eee; margin-top: 32px;">
  <p style="color: #888; font-size: 12px;">AdLuna GmbH — Berlin</p>
</body></html>
"""

    plaintext = f"""\
Vielen Dank für deinen Kauf

Hallo,

dein Kauf von {product_name} für {amount_eur:.2f} EUR ist erfolgreich bestätigt.

Die App sollte ab sofort ohne Einschränkungen funktionieren.
Falls nicht: beende sie einmal und starte sie neu.

Fragen? Antworte einfach auf diese Mail.

—
AdLuna GmbH — Berlin
"""

    try:
        resp = resend.Emails.send({
            "from": f"{_settings.resend_from_name} <{_settings.resend_from_email}>",
            "to": [to_email],
            "subject": subject,
            "html": html,
            "text": plaintext,
        })
        logger.info(f"Payment confirmation sent to {to_email} for {product_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to send payment confirmation: {e}")
        return False
