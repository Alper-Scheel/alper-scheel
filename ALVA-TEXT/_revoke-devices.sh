#!/bin/bash
# Schritt A: Device-Slots auf api.adluna.de für deine Mail freiräumen.
# Liest ADLUNA_ADMIN_TOKEN aus der lokalen Server-.env, ruft den Admin-DELETE
# auf, kaskadiert alle Devices/Codes/Checks für die Mail. Danach kannst du
# wieder als „neuer User" aktivieren.

set -u

ENV_FILE="/Users/AdPolis/codex-work/alper-scheel/services/adluna-platform-api/.env"
EMAIL="alper.scheel@gmail.com"
API="https://api.adluna.de"

echo ""
echo "════════════════════════════════════════════════════════"
echo " Server-Cleanup — Device-Slots freiräumen"
echo "════════════════════════════════════════════════════════"

# ── 1) Token aus .env lesen ───────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env nicht gefunden: $ENV_FILE"
    exit 1
fi

TOKEN=$(grep "^ADLUNA_ADMIN_TOKEN=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'")
if [ -z "$TOKEN" ]; then
    echo "❌ ADLUNA_ADMIN_TOKEN nicht in $ENV_FILE gefunden."
    exit 1
fi
echo "✓ Admin-Token aus .env geladen"

# ── 2) Aktuellen Stand zeigen ─────────────────────────────────
echo ""
echo "[1/3] Aktuelle Devices für $EMAIL …"
RESP=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API/v1/admin/user/$EMAIL")
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$API/v1/admin/user/$EMAIL")

if [ "$HTTP" = "404" ]; then
    echo "       ℹ User existiert nicht — keine Slots belegt. Aktivierung wird sauber durchlaufen."
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo " ✓ Server ist clean (kein Eintrag zu entfernen)"
    echo "════════════════════════════════════════════════════════"
    exit 0
elif [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
    echo "       ❌ Auth fehlgeschlagen (HTTP $HTTP) — Admin-Token in .env passt nicht zum Server."
    exit 1
elif [ "$HTTP" != "200" ]; then
    echo "       ⚠ Unerwarteter Status: HTTP $HTTP"
    echo "$RESP"
    exit 1
fi

# Device-Count aus JSON lesen
DEVICE_COUNT=$(echo "$RESP" | python3 -c "import sys, json; d = json.load(sys.stdin); print(len(d.get('devices', [])))" 2>/dev/null)
echo "       → $DEVICE_COUNT Device-Slots belegt"

if [ -n "$DEVICE_COUNT" ] && [ "$DEVICE_COUNT" -gt 0 ]; then
    echo "$RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for i, dev in enumerate(d.get('devices', []), 1):
    print(f'         {i}. {dev.get(\"device_name\", \"?\")} · {dev.get(\"platform\", \"?\")} · aktiviert {dev.get(\"activated_at\", \"?\")[:19] if dev.get(\"activated_at\") else \"?\"}')
" 2>/dev/null
fi

# ── 3) DELETE ─────────────────────────────────────────────────
echo ""
echo "[2/3] User-Eintrag löschen (kaskadiert Devices, Codes, Checks) …"
DEL_HTTP=$(curl -sS -o /tmp/alva-revoke-resp.txt -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "$API/v1/admin/user/$EMAIL")

if [ "$DEL_HTTP" = "204" ]; then
    echo "       ✓ HTTP 204 — User + alle Devices entfernt"
elif [ "$DEL_HTTP" = "404" ]; then
    echo "       • HTTP 404 — User existierte nicht mehr (auch ok)"
else
    echo "       ❌ HTTP $DEL_HTTP — unerwartet"
    cat /tmp/alva-revoke-resp.txt 2>/dev/null
    exit 1
fi

# ── 4) Verifikation ───────────────────────────────────────────
echo ""
echo "[3/3] Verifikation — User wirklich weg?"
VERIFY_HTTP=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$API/v1/admin/user/$EMAIL")
if [ "$VERIFY_HTTP" = "404" ]; then
    echo "       ✓ HTTP 404 — User ist weg, Slots sind frei"
else
    echo "       ⚠ HTTP $VERIFY_HTTP — User-Eintrag ist anscheinend noch da"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ Schritt A abgeschlossen — Server ist clean"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Du kannst jetzt mit Schritt B fortfahren:"
echo " v2.1.3-DMG von GitHub installieren."
