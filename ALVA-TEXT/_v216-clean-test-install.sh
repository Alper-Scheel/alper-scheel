#!/bin/bash
# v2.1.6 — Jungfräuliche Test-Installation aus dem fertigen DMG.
# Kombiniert Flatline-Cleanup mit DMG-Mount + App-Install — exakt wie
# ein neuer Tester die App zum ersten Mal aufsetzen würde.

set -u
BUNDLE_ID="com.adserica.alvatext"
DMG_PATH="/tmp/alva-v216-build/ALVA-TEXT-v2.1.6.dmg"

echo ""
echo "════════════════════════════════════════════════════════"
echo " v2.1.6 — Jungfräuliche Test-Installation"
echo "════════════════════════════════════════════════════════"

# ── 1) Flatline (alles ALVA weg) ──────────────────────────────
echo ""
echo "[1/4] Flatline — alle ALVA-Reste entfernen …"
pkill -9 -f "ALVA-TEXT" 2>/dev/null && sleep 1 || true

# Apps
mdfind -name "ALVA-TEXT" 2>/dev/null | grep "\.app$" | while read app; do
    rm -rf "$app" 2>/dev/null
done
rm -rf /Applications/ALVA-TEXT.app

# DMG-Volumes
for vol in /Volumes/ALVA-TEXT*; do
    [ -d "$vol" ] && hdiutil detach "$vol" -force -quiet 2>/dev/null
done

# UserDefaults + Library-Pfade
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/${BUNDLE_ID}.plist"
rm -rf "$HOME/Library/Application Support/ALVA-TEXT" 2>/dev/null
rm -rf "$HOME/Library/Caches/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Containers/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null
rm -rf "$HOME/Library/HTTPStorages/${BUNDLE_ID}" 2>/dev/null

# TCC-Permissions
for category in Microphone Accessibility ListenEvent AppleEvents; do
    tccutil reset "$category" "$BUNDLE_ID" 2>/dev/null
done
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

# Keychain
COUNT=0
while security delete-generic-password -s "$BUNDLE_ID" 2>/dev/null; do
    COUNT=$((COUNT+1))
done

# LaunchServices-Cache
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -kill -r -domain local -domain system -domain user 2>/dev/null

echo "       ✓ App-Reste, UserDefaults, TCC, Keychain ($COUNT Einträge), LaunchServices weg"

# ── 2) DMG mounten ────────────────────────────────────────────
echo ""
echo "[2/4] DMG mounten ($DMG_PATH) …"
if [ ! -f "$DMG_PATH" ]; then
    echo "       ❌ DMG nicht gefunden: $DMG_PATH"
    echo "       Bitte zuerst _v216-release-build.sh laufen lassen."
    exit 1
fi

MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -plist 2>/dev/null \
    | plutil -extract 'system-entities' xml1 -o - - 2>/dev/null \
    | grep -A1 mount-point \
    | tail -1 \
    | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT/ALVA-TEXT.app" ]; then
    MOUNT_POINT=$(ls -d /Volumes/ALVA-TEXT* 2>/dev/null | head -1)
fi

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT/ALVA-TEXT.app" ]; then
    echo "       ❌ Mount nicht gefunden"
    exit 1
fi
echo "       ✓ Mount: $MOUNT_POINT"

# ── 3) App nach /Applications ─────────────────────────────────
echo ""
echo "[3/4] App in /Applications kopieren …"
cp -R "$MOUNT_POINT/ALVA-TEXT.app" /Applications/
xattr -cr /Applications/ALVA-TEXT.app 2>/dev/null
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null

VERSION=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleShortVersionString)
BUILDNR=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleVersion)
echo "       ✓ /Applications/ALVA-TEXT.app — Version $VERSION (Build $BUILDNR)"

# ── 4) Starten — Onboarding kommt jetzt frisch ───────────────
echo ""
echo "[4/4] App starten …"
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ Jungfräuliche Installation läuft"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Was du jetzt erleben solltest:"
echo "   1. Onboarding-Window startet auf Schritt 1 (Welcome)"
echo "   2. Schritt 2 (OpenAI-Schlüssel): Feld leer, du kannst Key einfügen"
echo "      → grünes Validation-Label sollte sofort erscheinen"
echo "   3. Schritt 3 (Bedienungshilfen): TCC-Dialog kommt EINMAL"
echo "      → Toggle in Systemeinstellungen setzen → grüner Haken"
echo "   4. Schritt 4 (Eingabeüberwachung): gleiche Prozedur"
echo "   5. „Fertig\" → Settings → Account → Aktivierung mit Code"
echo "      → KEIN „Beta access active\"-Text mehr (siehe Sanitizer #B12)"
echo "      → KEIN roter „Server-Antwort 500\" am Bottom"
echo ""
echo " Test-Checkliste: _TESTS_v2.1.6.md"
echo " Block A → B → C → D → E → F → G der Reihe nach."
