#!/bin/bash
# v2.1.4 — Sauberes Install-Verfahren.
# Killt alle ALVA-Prozesse, löscht App + UserDefaults + TCC + Keychain + DerivedData,
# baut frisch, installiert, startet. Onboarding läuft komplett von vorne.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

BUNDLE_ID="com.adserica.alvatext"

echo ""
echo "════════════════════════════════════════════════════════"
echo " v2.1.4 — CLEAN INSTALL (kompletter Reset + Neuaufbau)"
echo "════════════════════════════════════════════════════════"

# ── 1) Alle ALVA-Prozesse hart beenden ───────────────────────
echo ""
echo "[1/9] Alle ALVA-Prozesse beenden …"
pkill -9 -f "ALVA-TEXT" 2>/dev/null && echo "      ✓ Prozesse beendet" || echo "      • keine Prozesse aktiv"
sleep 1

# Verifikation: nichts läuft mehr
RUNNING=$(pgrep -f "ALVA-TEXT" | wc -l | tr -d ' ')
if [ "$RUNNING" != "0" ]; then
    echo "      ⚠ noch $RUNNING Prozesse aktiv, härter killen…"
    sudo pkill -9 -f "ALVA-TEXT" 2>/dev/null || true
    sleep 2
fi

# ── 2) App aus /Applications löschen ─────────────────────────
echo ""
echo "[2/9] App aus /Applications entfernen …"
rm -rf /Applications/ALVA-TEXT.app
echo "      ✓ /Applications/ALVA-TEXT.app gelöscht"

# ── 3) UserDefaults komplett wegblasen ────────────────────────
echo ""
echo "[3/9] UserDefaults zurücksetzen …"
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "      ✓ Domain $BUNDLE_ID entfernt" || echo "      • Domain war leer"

# Auch die Plist-Datei direkt löschen, falls cached
rm -f ~/Library/Preferences/${BUNDLE_ID}.plist
rm -f ~/Library/Containers/${BUNDLE_ID} 2>/dev/null
rm -rf ~/Library/Application\ Support/ALVA-TEXT 2>/dev/null
rm -rf ~/Library/Caches/${BUNDLE_ID} 2>/dev/null
echo "      ✓ Caches + Application Support entfernt"

# ── 4) TCC-Permissions zurücksetzen ───────────────────────────
echo ""
echo "[4/9] TCC-Permissions zurücksetzen …"
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null && echo "      ✓ Microphone reset" || echo "      • Microphone bereits leer"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null && echo "      ✓ Accessibility reset" || echo "      • Accessibility bereits leer"
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null && echo "      ✓ ListenEvent reset" || echo "      • ListenEvent bereits leer"
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null && echo "      ✓ AppleEvents reset" || echo "      • AppleEvents bereits leer"
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

# ── 5) Keychain-Einträge löschen ──────────────────────────────
echo ""
echo "[5/9] Keychain-Einträge entfernen …"
for ACCOUNT in "openaiApiKey" "adluna.device.token" "adluna.device.uuid" \
               "adluna.last_check_iso" "adluna.last_status" "adluna.last_tier" \
               "adluna.user.email"; do
    security delete-generic-password -s "$BUNDLE_ID" -a "$ACCOUNT" 2>/dev/null && echo "      ✓ $ACCOUNT entfernt" || true
done
# Falls noch generische Einträge übrig sind, alle für $BUNDLE_ID:
while security delete-generic-password -s "$BUNDLE_ID" 2>/dev/null; do
    echo "      ✓ weiterer $BUNDLE_ID-Eintrag entfernt"
done

# ── 6) DerivedData für ALVA löschen ───────────────────────────
echo ""
echo "[6/9] DerivedData für ALVA-TEXT löschen …"
find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "ALVA_TEXT-*" -type d -exec rm -rf {} + 2>/dev/null
rm -rf /tmp/alva-build-v214
echo "      ✓ DerivedData + /tmp/alva-build-v214 gelöscht"

# ── 7) Build (Debug, sauberer Pfad) ───────────────────────────
echo ""
echo "[7/9] Frischer Build (Debug) …"
# Wir nutzen -scheme — das shared xcscheme-File haben wir mit angelegt.
# xcodebuild verlangt -scheme zwingend, sobald -derivedDataPath gesetzt ist.
SCHEME="ALVA-TEXT"
echo "      Scheme: $SCHEME"

# Deterministisch unique pro Sekunde — vermeidet mktemp-Pattern-Probleme.
rm -f /tmp/alva-build-v214-*.log 2>/dev/null
BUILD_LOG="/tmp/alva-build-v214-$(date +%s).log"
xcodebuild \
  -project ALVA_TEXT.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath /tmp/alva-build-v214 \
  clean build > "$BUILD_LOG" 2>&1

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo "      ❌ BUILD FAILED — letzte 60 Zeilen:"
    tail -60 "$BUILD_LOG"
    echo ""
    echo "Vollständiges Log: $BUILD_LOG"
    exit 1
fi
echo "      ✓ BUILD SUCCEEDED"

APP=$(find /tmp/alva-build-v214/Build/Products/Debug -name "ALVA-TEXT.app" -type d | head -1)
VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
BUILDNR=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null)
echo "      ✓ App gebaut: $VERSION (Build $BUILDNR)"

if [ "$VERSION" != "2.1.4" ]; then
    echo "      ❌ Falsche Version $VERSION (erwarte 2.1.4)"
    exit 1
fi

# ── 8) Install nach /Applications ─────────────────────────────
echo ""
echo "[8/9] Installation nach /Applications …"
cp -R "$APP" /Applications/
# Quarantine-Attribute entfernen, sonst meckert Gatekeeper
xattr -cr /Applications/ALVA-TEXT.app 2>/dev/null || true
echo "      ✓ /Applications/ALVA-TEXT.app installiert"

# ── 9) Git commit + tag (auf alva-v2.1.4) ─────────────────────
echo ""
echo "[9/9] Git commit + tag v2.1.4 …"
git checkout -b alva-v2.1.4 2>/dev/null && echo "      ✓ neuer Branch alva-v2.1.4" || git checkout alva-v2.1.4
git add ALVA_TEXT/AppCoordinator.swift \
        ALVA_TEXT/AppDelegate.swift \
        ALVA_TEXT/LicenseState.swift \
        ALVA_TEXT/SettingsView.swift \
        ALVA_TEXT/Info.plist \
        ALVA_TEXT.xcodeproj/project.pbxproj \
        ALVA_TEXT.xcodeproj/xcshareddata/
git commit -m "v2.1.4: Linearer Onboarding-Flow + License-Gates + TCC-Schleifen-Fix

Onboarding-Restrukturierung (5 Schritte, ein Fenster, eine Aktion):
1. Welcome
2. Aktivierung (Pflicht-Hürde, integriert direkt im Onboarding,
   kein Spring zum Settings-Account-Tab mehr)
3. OpenAI-Schlüssel (optional)
4. Bedienungshilfen (Permission-Prompt nur hier)
5. Eingabeüberwachung (Permission-Prompt nur hier)

Lifecycle-Fixes:
- AppDelegate startet kein automatisches TCC-Prompt mehr beim Launch
- AppCoordinator.requestPermissions: nur Mikrofon, kein TCC mehr
- AppCoordinator.openSettings: blockt während Onboarding aktiv
- Onboarding kommt auch bei fehlender Aktivierung erneut hoch

Vorhandene v2.1.4-Patches:
- License-Gate in beginRecording, startReverseTranslate
- LicenseState.isUsable .loading → false
- requestAccessibilityPrompt: 5s-Cooldown
- scheduleAutoRestart deaktiviert
- Versionsbump 2.1.2 → 2.1.4 (Build 21 → 24)" 2>/dev/null \
    && echo "      ✓ committed" || echo "      • bereits committed"
git tag -f v2.1.4 && echo "      ✓ Tag v2.1.4 gesetzt"

# ── App starten ──────────────────────────────────────────────
echo ""
echo "Starte ALVA-TEXT (frisch, ohne Permissions, ohne Aktivierung) …"
open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ Clean-Install v2.1.4 abgeschlossen"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Was du JETZT erleben solltest:"
echo "   1. Onboarding-Window kommt frisch hoch (vom ersten Schritt)"
echo "   2. Mikrofon-Dialog: einmal erlauben"
echo "   3. Bedienungshilfen-Dialog: EINMAL — danach NIE wieder automatisch"
echo "   4. Eingabeüberwachung-Dialog: EINMAL"
echo "   5. Aktivierung: 6-stelliger Code aus Mail eingeben"
echo "   6. Hotkey ⌃ ohne Aktivierung → blockt + Settings öffnen sich"
echo "   7. Hotkey ⌃ mit Aktivierung → Diktat funktioniert"
echo ""
echo " Falls Bedienungshilfen-Dialog NACH dem Klick wiederkommt:"
echo "   • Toggle in Systemeinstellungen prüfen (sollte grün sein)"
echo "   • ALVA manuell beenden (Menübar → Beenden)"
echo "   • App über /Applications wieder öffnen"
echo "   • Sollte dann ohne Dialog laufen — der Auto-Restart-Loop"
echo "     ist deaktiviert, kein Endlos-Karussell mehr."
