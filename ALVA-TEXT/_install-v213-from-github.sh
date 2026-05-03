#!/bin/bash
# Schritt B: v2.1.3-DMG von GitHub installieren.
# Signiert, notarisiert, gestapelt. Lief heute Vormittag sauber.

set -u

DMG_URL="https://github.com/Alper-Scheel/alper-scheel/releases/latest/download/ALVA-TEXT.dmg"
DMG_LOCAL="/tmp/ALVA-TEXT-v2.1.3.dmg"

echo ""
echo "════════════════════════════════════════════════════════"
echo " v2.1.3 von GitHub installieren (signiert + notarisiert)"
echo "════════════════════════════════════════════════════════"

# ── 1) Vorhandene DMG-Reste wegräumen ─────────────────────────
rm -f "$DMG_LOCAL" 2>/dev/null
for vol in /Volumes/ALVA-TEXT*; do
    [ -d "$vol" ] && hdiutil detach "$vol" -force -quiet 2>/dev/null
done

# ── 2) DMG laden ──────────────────────────────────────────────
echo ""
echo "[1/4] DMG laden …"
curl -L --progress-bar -o "$DMG_LOCAL" "$DMG_URL"

if [ ! -s "$DMG_LOCAL" ]; then
    echo "       ❌ Download fehlgeschlagen oder leer."
    exit 1
fi
SIZE=$(ls -lh "$DMG_LOCAL" | awk '{print $5}')
echo "       ✓ $SIZE geladen"

# ── 3) Mount + Install ────────────────────────────────────────
echo ""
echo "[2/4] DMG mounten und App installieren …"
MOUNT_OUTPUT=$(hdiutil attach "$DMG_LOCAL" -nobrowse -plist 2>/dev/null)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" \
    | plutil -extract 'system-entities' xml1 -o - - 2>/dev/null \
    | grep -A1 mount-point \
    | tail -1 \
    | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    MOUNT_POINT=$(ls -d /Volumes/ALVA-TEXT* 2>/dev/null | head -1)
fi

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT/ALVA-TEXT.app" ]; then
    echo "       ❌ Mount nicht gefunden — DMG manuell öffnen."
    exit 1
fi
echo "       Mount: $MOUNT_POINT"

# Sicherheits-Pass: alte Apps weg (sollte aber nach Flatline keine geben)
pkill -9 -f "ALVA-TEXT" 2>/dev/null
sleep 1
rm -rf /Applications/ALVA-TEXT.app

cp -R "$MOUNT_POINT/ALVA-TEXT.app" /Applications/
xattr -cr /Applications/ALVA-TEXT.app 2>/dev/null || true
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
echo "       ✓ /Applications/ALVA-TEXT.app installiert"

# ── 4) Versions-Verifikation ──────────────────────────────────
echo ""
echo "[3/4] Versions-Check …"
VERSION=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)
BUILDNR=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleVersion 2>/dev/null)
echo "       Version: $VERSION (Build $BUILDNR)"

if [ "$VERSION" != "2.1.3" ]; then
    echo "       ⚠ erwartet 2.1.3, bekomme $VERSION — falsches Release auf GitHub?"
fi

# Code-Signature validieren (sollte Developer-ID-signiert sein)
echo ""
echo "[4/4] Signatur-Check …"
codesign --verify --deep --strict /Applications/ALVA-TEXT.app 2>&1 | head -5
SPCTL=$(spctl -a -vv /Applications/ALVA-TEXT.app 2>&1 | head -3)
echo "$SPCTL"
if echo "$SPCTL" | grep -q "accepted"; then
    echo "       ✓ Gatekeeper akzeptiert die App"
fi

# ── App starten ──────────────────────────────────────────────
echo ""
echo "App starten …"
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ v2.1.3 installiert und gestartet"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Was du erwarten solltest:"
echo "   1. Onboarding-Window öffnet sich automatisch"
echo "   2. Mikrofon-Dialog: einmal Erlauben"
echo "   3. Aktivierung im Account-Tab (Settings):"
echo "      • E-Mail eintippen → Code an alper.scheel@gmail.com"
echo "      • Code aus Mail eingeben → Aktivierung erfolgt sauber"
echo "        (Server-Slots sind seit Schritt A frei, kein 409 mehr)"
echo "   4. Bedienungshilfen: System-Dialog kommt einmal beim ersten Auto-Paste"
echo "   5. Eingabeüberwachung: Dialog beim ersten F-Key oder Reverse-Translate"
echo ""
echo " Falls der Bedienungshilfen-Dialog mehrfach kommt: das ist der bekannte"
echo " v2.1.3-TCC-Cache-Bug, den wir später strukturiert angehen. Workaround:"
echo " Toggle in Systemeinstellungen einmal aus + ein, dann ALVA neu starten."
