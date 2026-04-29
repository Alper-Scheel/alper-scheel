#!/bin/bash
# v2.2.0-beta1 — auto-detect Scheme, build, install, start.
# Bricht nicht ab wenn ein Schritt fehlschlägt — gibt am Ende einen klaren Status.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

echo ""
echo "════════════════════════════════════════════════════════"
echo " v2.2.0-beta1 — Build & Install"
echo "════════════════════════════════════════════════════════"

# 1) Schemes auflisten
echo ""
echo "[1/5] Schemes ermitteln…"
LIST_OUT=$(xcodebuild -project ALVA_TEXT.xcodeproj -list 2>&1)
echo "$LIST_OUT" | sed -n '/Schemes:/,/^$/p'

SCHEME=$(echo "$LIST_OUT" | awk '/Schemes:/ {flag=1; next} flag && NF {print $1; exit}')
if [ -z "$SCHEME" ]; then
    echo ""
    echo "❌ Kein Scheme gefunden. In Xcode: Product → Scheme → Manage Schemes →"
    echo "   ALVA-TEXT mit „Shared\" anhaken, dann Skript erneut starten."
    exit 1
fi
echo "→ verwendet: $SCHEME"

# 2) Build
echo ""
echo "[2/5] Build (Debug) …"
BUILD_LOG=$(mktemp /tmp/alva-build.XXXXXX.log)
xcodebuild \
  -project ALVA_TEXT.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath /tmp/alva-build \
  build > "$BUILD_LOG" 2>&1

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
    echo "❌ BUILD FAILED — letzte 60 Zeilen:"
    tail -60 "$BUILD_LOG"
    echo ""
    echo "Vollständiges Log: $BUILD_LOG"
    exit 1
fi
echo "→ ✅ BUILD SUCCEEDED"

# 3) App finden + Version verifizieren
echo ""
echo "[3/5] App finden + Version prüfen…"
APP=$(find /tmp/alva-build/Build/Products/Debug -name "ALVA-TEXT.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    APP=$(find /tmp/alva-build -name "ALVA-TEXT.app" -type d 2>/dev/null | grep -v Index.noindex | head -1)
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "❌ App nicht im Build-Output gefunden."
    exit 1
fi
echo "→ App: $APP"

VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
BUILDNR=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "?")
echo "→ Version: $VERSION (Build $BUILDNR)"

if [ "$VERSION" != "2.2.0-beta1" ]; then
    echo ""
    echo "⚠️  Erwartet 2.2.0-beta1, bekomme $VERSION — Info.plist/pbxproj prüfen."
fi

# 4) Alte App raus, neue rein
echo ""
echo "[4/5] Installation…"
pkill -f ALVA-TEXT 2>/dev/null && echo "  alte Instanz beendet" || echo "  keine laufende Instanz"
sleep 1
rm -rf /Applications/ALVA-TEXT.app
cp -R "$APP" /Applications/
echo "→ /Applications/ALVA-TEXT.app aktualisiert"

# 5) Clean-State + Start
echo ""
echo "[5/5] Clean-State + Start…"
defaults write com.adserica.alvatext hasSeenOnboarding -bool false
defaults delete com.adserica.alvatext alva.proMode 2>/dev/null || true
echo "→ hasSeenOnboarding=false, proMode reset"

open /Applications/ALVA-TEXT.app
echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ Fertig — Onboarding mit Mode-Wahl sollte jetzt starten."
echo "════════════════════════════════════════════════════════"
