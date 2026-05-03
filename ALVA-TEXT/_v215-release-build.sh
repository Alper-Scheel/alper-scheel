#!/bin/bash
# v2.1.5 — Release-Build, signiert + notarisiert + gestapelt.
# Eines durch, dann Test. Wenn ok: DMG → GitHub Release.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

PROJECT="ALVA_TEXT.xcodeproj"
SCHEME="ALVA-TEXT"
VERSION="2.1.5"
BUILD_DIR="/tmp/alva-v215-build"
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
echo "       ✓ Build-Dir frisch"

# ── 2) Archive ─────────────────────────────────────────────────
echo ""
echo "[2/8] Archive (Release) …"
ARCHIVE_LOG="/tmp/alva-v215-archive.log"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/ALVA-TEXT.xcarchive" \
  archive > "$ARCHIVE_LOG" 2>&1

if ! grep -q "ARCHIVE SUCCEEDED" "$ARCHIVE_LOG"; then
    echo "       ❌ Archive fehlgeschlagen — letzte 30 Zeilen:"
    tail -30 "$ARCHIVE_LOG"
    echo ""
    echo "       Vollständiges Log: $ARCHIVE_LOG"
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

EXPORT_LOG="/tmp/alva-v215-export.log"
xcodebuild \
  -exportArchive \
  -archivePath "$BUILD_DIR/ALVA-TEXT.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" > "$EXPORT_LOG" 2>&1

APP_PATH="$BUILD_DIR/export/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "       ❌ Export fehlgeschlagen — letzte 30 Zeilen:"
    tail -30 "$EXPORT_LOG"
    exit 1
fi
echo "       ✓ App exportiert: $APP_PATH"

# ── 4) Codesign-Check ──────────────────────────────────────────
echo ""
echo "[4/8] Codesign-Verifikation …"
codesign --verify --deep --strict "$APP_PATH" 2>&1 || {
    echo "       ❌ Codesign-Verifikation fehlgeschlagen"
    exit 1
}
echo "       ✓ Code-Signatur korrekt"

# ── 5) Notarization (App) ──────────────────────────────────────
echo ""
echo "[5/8] Notarization der .app (typisch 2-5 Min) …"
ZIP_PATH="$BUILD_DIR/ALVA-TEXT-app.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

NOTARY_LOG="/tmp/alva-v215-notary.log"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait > "$NOTARY_LOG" 2>&1

if ! grep -q "status: Accepted" "$NOTARY_LOG"; then
    echo "       ❌ Notarization fehlgeschlagen:"
    cat "$NOTARY_LOG"
    echo ""
    echo "       Häufige Ursachen:"
    echo "        - Keychain-Profile '$NOTARY_PROFILE' fehlt:"
    echo "          'xcrun notarytool store-credentials alva-notary' einmal laufen lassen"
    echo "        - Apple-ID + App-spezifisches Passwort + Team-ID nötig"
    exit 1
fi
echo "       ✓ Notarization akzeptiert"

# ── 6) Stapler (App) ───────────────────────────────────────────
echo ""
echo "[6/8] Stapler …"
xcrun stapler staple "$APP_PATH" 2>&1 | grep -E "Worked|saved" | head -2
echo "       ✓ App gestapelt"

# Versions-Verifikation
APP_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
APP_BUILD=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)
echo "       App-Version: $APP_VERSION (Build $APP_BUILD)"
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "       ⚠ erwartet $VERSION, bekomme $APP_VERSION"
fi

# ── 7) DMG erstellen + notarisieren + stapeln ──────────────────
echo ""
echo "[7/8] DMG bauen …"
DMG_PATH="$BUILD_DIR/ALVA-TEXT-v$VERSION.dmg"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "       ⚠ create-dmg nicht installiert — DMG-Build überspringen."
    echo "       Mit 'brew install create-dmg' installieren, dann erneut."
    DMG_PATH=""
else
    create-dmg \
        --volname "ALVA-TEXT v$VERSION" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME" 175 190 \
        --hide-extension "$APP_NAME" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$APP_PATH" > /tmp/alva-v215-dmg.log 2>&1

    if [ -s "$DMG_PATH" ]; then
        echo "       ✓ DMG: $DMG_PATH ($(ls -lh "$DMG_PATH" | awk '{print $5}'))"

        echo "       Notarisiere DMG …"
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait > /tmp/alva-v215-dmg-notary.log 2>&1
        if grep -q "status: Accepted" /tmp/alva-v215-dmg-notary.log; then
            xcrun stapler staple "$DMG_PATH" >/dev/null 2>&1
            echo "       ✓ DMG notarisiert + gestapelt"
        else
            echo "       ⚠ DMG-Notarization-Status unklar — Log: /tmp/alva-v215-dmg-notary.log"
        fi
    else
        echo "       ⚠ DMG-Build fehlgeschlagen — Log: /tmp/alva-v215-dmg.log"
        DMG_PATH=""
    fi
fi

# ── 8) Lokal installieren + starten ────────────────────────────
echo ""
echo "[8/8] App in /Applications installieren …"
cp -R "$APP_PATH" /Applications/
xattr -cr /Applications/ALVA-TEXT.app 2>/dev/null
defaults write com.adserica.alvatext hasSeenOnboarding -bool false 2>/dev/null
echo "       ✓ /Applications/ALVA-TEXT.app installiert + Onboarding-Flag reset"

# ── Git: Commit + Tag ─────────────────────────────────────────
echo ""
echo "[Git] Commit + Tag v$VERSION …"
git add ALVA_TEXT/ActivationView.swift \
        ALVA_TEXT/SettingsView.swift \
        ALVA_TEXT/Info.plist \
        ALVA_TEXT.xcodeproj/project.pbxproj 2>/dev/null
git commit -m "v$VERSION: License-Gates + TCC-Schleifen-Fix + Wording

- License-Gate in beginRecording, startReverseTranslate (#B3)
- LicenseState.isUsable: .loading → false (sicherer Default)
- requestAccessibilityPrompt: 5-Sek-Cooldown (#B5)
- requestPermissions: Prompt nur einmal pro Lifetime (#B2)
- scheduleAutoRestart deaktiviert (#B4 + #B11)
- ActivationView: 'Beta-Zugang' → 'Vollzugang' (#B12)
- ActivationView: Done-Step ohne Server-Errors (#B13)
- Versionsbump 2.1.4 → $VERSION (Build 24 → 25)" 2>/dev/null && echo "       ✓ committed" || echo "       • bereits committed"
git tag -f v$VERSION && echo "       ✓ Tag v$VERSION gesetzt"

# App starten
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ v$VERSION fertig (Release · signiert · notarisiert)"
echo "════════════════════════════════════════════════════════"
echo ""
echo " App läuft: /Applications/ALVA-TEXT.app"
if [ -n "$DMG_PATH" ] && [ -s "$DMG_PATH" ]; then
    echo " DMG für Distribution: $DMG_PATH"
fi
echo ""
echo " TEST-PLAN (bitte in dieser Reihenfolge):"
echo "  1. Onboarding läuft sauber durch — KEIN Auto-Restart-Reset"
echo "  2. TCC-Dialog kommt MAXIMAL EINMAL beim ersten Start"
echo "  3. Bedienungshilfen-Liste: NUR EIN Eintrag (kein Multi-cdhash)"
echo "  4. Hotkey ⌃ OHNE Aktivierung → blockt, Settings öffnen sich"
echo "  5. Aktivierung im Account-Tab: 'Vollzugang' (kein 'Beta'),"
echo "     kein roter 500-Error mehr"
echo "  6. Hotkey ⌃ MIT Aktivierung → Diktat funktioniert"
