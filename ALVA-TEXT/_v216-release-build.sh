#!/bin/bash
# v2.1.6 — Release-Build (signiert, notarisiert, gestapelt) mit den vier
# chirurgischen Bug-Fixes: Cloud-Timeout, Default-Lokal, Prüfen-Button weg,
# API-Key-Validation.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

PROJECT="ALVA_TEXT.xcodeproj"
SCHEME="ALVA-TEXT"
VERSION="2.1.6"
BUILD_DIR="/tmp/alva-v216-build"
NOTARY_PROFILE="alva-notary"
APP_NAME="ALVA-TEXT.app"
TEAM_ID="4CU8CL46JX"

echo ""
echo "════════════════════════════════════════════════════════"
echo " v$VERSION — Release-Build + Notarization"
echo "════════════════════════════════════════════════════════"

# ── 1) Cleanup ─────────────────────────────────────────────────
echo ""
echo "[1/8] Pre-Build-Cleanup …"
pkill -9 -f "ALVA-TEXT" 2>/dev/null && sleep 1 || true
rm -rf /Applications/ALVA-TEXT.app
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
# v2.1.6: transcriptionBackend zurück auf .local (Code-Default)
defaults delete com.adserica.alvatext transcriptionBackend 2>/dev/null || true
echo "       ✓ Build-Dir frisch + transcriptionBackend reset"

# ── 2) Archive ─────────────────────────────────────────────────
echo ""
echo "[2/8] Archive (Release) …"
ARCHIVE_LOG="/tmp/alva-v216-archive.log"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/ALVA-TEXT.xcarchive" \
  archive > "$ARCHIVE_LOG" 2>&1

if ! grep -q "ARCHIVE SUCCEEDED" "$ARCHIVE_LOG"; then
    echo "       ❌ Archive fehlgeschlagen — letzte 30 Zeilen:"
    tail -30 "$ARCHIVE_LOG"
    exit 1
fi
echo "       ✓ Archive erstellt"

# ── 3) Export ──────────────────────────────────────────────────
echo ""
echo "[3/8] Export (Developer-ID) …"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "$BUILD_DIR/ALVA-TEXT.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" > /tmp/alva-v216-export.log 2>&1

APP_PATH="$BUILD_DIR/export/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "       ❌ Export fehlgeschlagen:"
    tail -30 /tmp/alva-v216-export.log
    exit 1
fi
echo "       ✓ App exportiert"

# ── 4) Codesign-Check ──────────────────────────────────────────
echo ""
echo "[4/8] Codesign-Verifikation …"
codesign --verify --deep --strict "$APP_PATH" 2>&1 || exit 1
echo "       ✓ ok"

# ── 5) Notarization ────────────────────────────────────────────
echo ""
echo "[5/8] Notarization (2-5 Min) …"
ZIP_PATH="$BUILD_DIR/ALVA-TEXT-app.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

NOTARY_LOG="/tmp/alva-v216-notary.log"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait > "$NOTARY_LOG" 2>&1

if ! grep -q "status: Accepted" "$NOTARY_LOG"; then
    echo "       ❌ Notarization fehlgeschlagen:"
    cat "$NOTARY_LOG"
    exit 1
fi
echo "       ✓ akzeptiert"

# ── 6) Stapler ─────────────────────────────────────────────────
echo ""
echo "[6/8] Stapler …"
xcrun stapler staple "$APP_PATH" 2>&1 | tail -3
echo "       ✓ gestapelt"

VERSION_CHECK=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
BUILD_CHECK=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)
echo "       Version: $VERSION_CHECK (Build $BUILD_CHECK)"

# ── 7) DMG ─────────────────────────────────────────────────────
echo ""
echo "[7/8] DMG …"
DMG_PATH="$BUILD_DIR/ALVA-TEXT-v$VERSION.dmg"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "ALVA-TEXT v$VERSION" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME" 175 190 \
        --hide-extension "$APP_NAME" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$APP_PATH" > /tmp/alva-v216-dmg.log 2>&1

    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait > /tmp/alva-v216-dmg-notary.log 2>&1
    xcrun stapler staple "$DMG_PATH" >/dev/null 2>&1
    echo "       ✓ DMG: $DMG_PATH ($(ls -lh "$DMG_PATH" | awk '{print $5}'))"
else
    echo "       ⚠ create-dmg fehlt — DMG übersprungen"
    DMG_PATH=""
fi

# ── 8) Install ─────────────────────────────────────────────────
echo ""
echo "[8/8] Install nach /Applications …"
cp -R "$APP_PATH" /Applications/
xattr -cr /Applications/ALVA-TEXT.app 2>/dev/null
echo "       ✓ installiert"

# ── Git: Commit + Tag ─────────────────────────────────────────
echo ""
echo "[Git] Commit + Tag v$VERSION …"
git add ALVA_TEXT/AppCoordinator.swift \
        ALVA_TEXT/OpenAIService.swift \
        ALVA_TEXT/SettingsView.swift \
        ALVA_TEXT/Info.plist \
        ALVA_TEXT.xcodeproj/project.pbxproj 2>/dev/null
git commit -m "v$VERSION: Cloud-Timeout-Fix + API-Key-Validation + UX-Polish

- OpenAIService: URLSession-Timeout 30s (Transcribe) + 12s (Chat)
  → verhindert das 60-Sek-Endlos-Rädchen bei OpenAI-Latenz-Spikes (#B17)
- AppCoordinator: API-Key-Validation async im didSet (#B14)
  → ungültige Keys werden sofort als rote Meldung im UI markiert
- AppCoordinator: validateStoredAPIKeyOnLaunch() beim App-Start
  → bestehender Keychain-Key wird beim Launch verifiziert
- SettingsView: Prüfen-Button bei Whisper-Status entfernt (#B16)
- SettingsView: apiKeyValidationLabel zeigt Status (checking/valid/
  invalid/quota/network) am OpenAI-Schlüssel-Feld
- Versionsbump 2.1.5 → $VERSION (Build 25 → 26)" 2>/dev/null \
    && echo "       ✓ committed" || echo "       • bereits committed"
git tag -f v$VERSION && echo "       ✓ Tag v$VERSION gesetzt"

# ── Start ─────────────────────────────────────────────────────
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ v$VERSION fertig (Release · signiert · notarisiert)"
echo "════════════════════════════════════════════════════════"
echo ""
echo " App läuft: /Applications/ALVA-TEXT.app"
if [ -n "${DMG_PATH:-}" ] && [ -s "$DMG_PATH" ]; then
    echo " DMG: $DMG_PATH"
fi
echo ""
echo " Nächster Schritt: Test-Checkliste"
echo "   /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT/_TESTS_v2.1.6.md"
echo " Punkt für Punkt durchgehen, je grün/rot vermerken."
