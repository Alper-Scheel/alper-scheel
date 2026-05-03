#!/bin/bash
# v2.1.4 Hotfix: License-Gates + TCC-Prompt-Cooldown.
# Build → Commit → Tag → Install → Start.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

echo ""
echo "════════════════════════════════════════════════════════"
echo " v2.1.4 — Hotfix Build (License-Gates + TCC-Cooldown)"
echo "════════════════════════════════════════════════════════"

# ── 1) Scheme ermitteln ────────────────────────────────────────
SCHEME=$(xcodebuild -project ALVA_TEXT.xcodeproj -list 2>/dev/null \
    | awk '/Schemes:/ {flag=1; next} flag && NF {print $1; exit}')
if [ -z "$SCHEME" ]; then
    echo "❌ Kein Scheme gefunden. In Xcode: Product → Scheme → Manage Schemes →"
    echo "   ALVA-TEXT mit „Shared\" anhaken, dann Skript erneut starten."
    exit 1
fi
echo "[1/6] Scheme: $SCHEME"

# ── 2) Build ───────────────────────────────────────────────────
echo "[2/6] Build Debug …"
BUILD_LOG=$(mktemp /tmp/alva-build-v214.XXXXXX.log)
xcodebuild \
  -project ALVA_TEXT.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath /tmp/alva-build-v214 \
  build > "$BUILD_LOG" 2>&1

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo "❌ BUILD FAILED — letzte 60 Zeilen:"
    tail -60 "$BUILD_LOG"
    echo ""
    echo "Vollständiges Log: $BUILD_LOG"
    exit 1
fi
echo "      ✓ BUILD SUCCEEDED"

# ── 3) App + Version verifizieren ──────────────────────────────
APP=$(find /tmp/alva-build-v214/Build/Products/Debug -name "ALVA-TEXT.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "❌ App nicht im Build-Output gefunden"
    exit 1
fi
VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
BUILDNR=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null)
echo "[3/6] Version: $VERSION (Build $BUILDNR)"
if [ "$VERSION" != "2.1.4" ]; then
    echo "❌ Falsche Version (erwarte 2.1.4, bekomme $VERSION)"
    exit 1
fi
echo "      ✓ Version stimmt"

# ── 4) Git commit + tag (auf eigenem Branch alva-v2.1.4) ───────
echo "[4/6] Git commit auf Branch alva-v2.1.4 …"
git checkout -b alva-v2.1.4 2>/dev/null && echo "      ✓ neuer Branch alva-v2.1.4" || git checkout alva-v2.1.4
git add ALVA_TEXT/AppCoordinator.swift \
        ALVA_TEXT/LicenseState.swift \
        ALVA_TEXT/Info.plist \
        ALVA_TEXT.xcodeproj/project.pbxproj
git commit -m "v2.1.4: License-Gates + TCC-Prompt-Cooldown

- License-Guard in beginRecording (Hotkey-Aufnahme blockt ohne Aktivierung)
- License-Guard in startReverseTranslate (Cloud-Pfad geblockt ohne Lizenz)
- LicenseState.isUsable: .loading → false (sicherer Default, kein Race-Window)
- 5s-Cooldown auf requestAccessibilityPrompt verhindert TCC-Dialog-Endlosschleife
- Versionsbump 2.1.2 → 2.1.4 (Build 21 → 24)" 2>/dev/null && echo "      ✓ committed" || echo "      • bereits committed"

git tag -f v2.1.4 && echo "      ✓ Tag v2.1.4 gesetzt"

# ── 5) Install ─────────────────────────────────────────────────
echo "[5/6] Installation …"
pkill -f ALVA-TEXT 2>/dev/null && sleep 1 || true
rm -rf /Applications/ALVA-TEXT.app
cp -R "$APP" /Applications/
defaults write com.adserica.alvatext hasSeenOnboarding -bool false
echo "      ✓ /Applications/ALVA-TEXT.app aktualisiert + Onboarding-Flag reset"

# ── 6) Start ───────────────────────────────────────────────────
echo "[6/6] App starten …"
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ v2.1.4 läuft (Debug-Build, lokal)"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Test-Plan (bitte durchgehen):"
echo "   1. Onboarding läuft sauber bis zum Aktivierungs-Schritt"
echo "   2. OHNE Aktivierungscode: Hotkey ⌃ drücken → Aufnahme blockt,"
echo "      Settings öffnen sich automatisch im Account-Tab"
echo "   3. Aktivierungscode eintragen (Server-Limit ggf. vorher reset)"
echo "   4. Mit Aktivierung: Hotkey ⌃ → Aufnahme läuft normal"
echo "   5. Permission-Test: Toggle in Bedienungshilfen entfernen + neu setzen,"
echo "      Klick auf „Erlaubnis erteilen\" → Dialog kommt EINMAL,"
echo "      weitere Klicks innerhalb 5 s → KEIN neuer Dialog (Cooldown)"
echo ""
echo " Wenn alles passt, push + Release morgen:"
echo "   git push origin alva-v2.1.4 v2.1.4"
echo "   gh release create v2.1.4 --title \"v2.1.4 Hotfix\" --notes-file …"
