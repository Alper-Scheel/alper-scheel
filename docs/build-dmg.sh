#!/bin/bash
# build-dmg.sh — erstellt ein signiertes + notarisiertes DMG für ALVA-TEXT
#
# Voraussetzungen:
#   - create-dmg via Homebrew (brew install create-dmg)
#   - notarytool keychain-profile "alva-notary" eingerichtet
#   - Notarized App-Bundle in ~/Downloads/ALVA-TEXT.app
#     (kommt aus Xcode → Distribute App → Direct Distribution → Export)
#   - Developer ID Application Cert in Keychain (Team 4CU8CL46JX, AdPolis GmbH)
#
# Aufruf (Defaults):
#   bash ~/codex-work/alper-scheel/docs/build-dmg.sh
#
# Aufruf (mit Override):
#   VERSION=2.1.3 APP_PATH=/path/to/Other.app bash build-dmg.sh
#
# Output:
#   ~/Downloads/ALVA-TEXT.dmg  (signiert, notarisiert, stapled)

set -e

# --- Konfiguration ----------------------------------------------------

VERSION="${VERSION:-2.1.2}"
APP_PATH="${APP_PATH:-$HOME/Downloads/ALVA-TEXT.app}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Downloads}"
DMG_NAME="ALVA-TEXT.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
SIGNING_IDENTITY="Developer ID Application"
NOTARY_PROFILE="alva-notary"

# --- Banner -----------------------------------------------------------

echo "================================================"
echo "  ALVA-TEXT $VERSION — DMG-Build"
echo "================================================"
echo "  App-Bundle:    $APP_PATH"
echo "  DMG-Output:    $DMG_PATH"
echo "  Notary-Profil: $NOTARY_PROFILE"
echo "================================================"
echo ""

# --- Vorab-Checks -----------------------------------------------------

[[ -d "$APP_PATH" ]] \
    || { echo "ERROR: App-Bundle nicht gefunden: $APP_PATH"; exit 1; }
command -v create-dmg >/dev/null 2>&1 \
    || { echo "ERROR: create-dmg fehlt — brew install create-dmg"; exit 1; }
command -v xcrun >/dev/null 2>&1 \
    || { echo "ERROR: xcrun fehlt — Xcode Command Line Tools nötig"; exit 1; }

# Alte DMG entfernen, falls da
if [[ -f "$DMG_PATH" ]]; then
    echo "Lösche alte DMG: $DMG_PATH"
    rm "$DMG_PATH"
    echo ""
fi

# --- 1) DMG erzeugen --------------------------------------------------

echo "1) DMG erzeugen mit create-dmg ..."
create-dmg \
  --volname "ALVA-TEXT" \
  --window-pos 200 120 \
  --window-size 600 380 \
  --icon-size 100 \
  --icon "ALVA-TEXT.app" 175 190 \
  --hide-extension "ALVA-TEXT.app" \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"
echo "   ✅ DMG erstellt: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo ""

# --- 2) DMG signieren -------------------------------------------------

echo "2) DMG mit Developer ID signieren ..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
echo "   ✅ Signatur gesetzt"
echo ""

# --- 3) DMG notarisieren ----------------------------------------------

echo "3) DMG zu Apple Notary Service hochladen (5-15 Min, manchmal länger) ..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
echo "   ✅ Notarisiert"
echo ""

# --- 4) Notary-Stempel kleben ----------------------------------------

echo "4) Notary-Stempel auf DMG kleben (stapler) ..."
xcrun stapler staple "$DMG_PATH"
echo "   ✅ Stempel angebracht — DMG funktioniert ab jetzt offline"
echo ""

# --- 5) Gatekeeper-Verifikation --------------------------------------

echo "5) Gatekeeper-Verifikation ..."
if spctl -a -v -t open --context context:primary-signature "$DMG_PATH" 2>&1; then
    echo "   ✅ Gatekeeper akzeptiert die DMG"
else
    echo "   ⚠️  Gatekeeper-Check meldet Warnungen — siehe Output oben"
fi
echo ""

# --- Fertig -----------------------------------------------------------

echo "================================================"
echo "  ✅ DMG fertig"
echo "================================================"
echo "  Datei:   $DMG_PATH"
echo "  Größe:   $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "  Nächste Schritte:"
echo "    1) Lokal testen: Doppelklick → Drag in /Programme"
echo "    2) GitHub Release v$VERSION mit DMG ergänzen:"
echo "       gh release upload v$VERSION \"$DMG_PATH\" --repo Alper-Scheel/alper-scheel"
echo "    3) Landing-Page ggf. anpassen, wenn DMG das Primär-Asset werden soll"
echo "================================================"
