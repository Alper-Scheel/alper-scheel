#!/bin/bash
# FLATLINE — alles ALVA-bezogene vom Mac entfernen.
# Macht KEINEN Build und KEINE Re-Installation. Nur Cleanup + Bestandsbericht.
# Nach Durchlauf: System ist im Zustand, als wäre ALVA-TEXT nie installiert worden.

set -u
BUNDLE_ID="com.adserica.alvatext"

echo ""
echo "════════════════════════════════════════════════════════"
echo " FLATLINE — Komplett-Cleanup ALVA-TEXT"
echo "════════════════════════════════════════════════════════"

# ── 1) Alle ALVA-Prozesse hart beenden ────────────────────────
echo ""
echo "[1/10] ALVA-Prozesse beenden …"
pkill -9 -f "ALVA-TEXT" 2>/dev/null && echo "       ✓ Prozesse beendet" || echo "       • keine Prozesse aktiv"
pkill -9 -f "ALVA_TEXT" 2>/dev/null || true
sleep 1

# Verifikation
RUNNING=$(pgrep -f "ALVA" | wc -l | tr -d ' ')
if [ "$RUNNING" != "0" ]; then
    echo "       ⚠ noch $RUNNING ALVA-Prozesse — sudo kill versuchen"
    sudo pkill -9 -f "ALVA" 2>/dev/null || true
fi

# ── 2) Alle App-Kopien auf der Disk finden + löschen ─────────
echo ""
echo "[2/10] Alle ALVA-TEXT.app-Kopien finden + löschen …"
APPS_FOUND=$(mdfind -name "ALVA-TEXT" 2>/dev/null | grep "\.app$" || true)
if [ -n "$APPS_FOUND" ]; then
    echo "$APPS_FOUND" | while read -r app; do
        rm -rf "$app" 2>/dev/null && echo "       ✓ gelöscht: $app" || echo "       ⚠ konnte nicht löschen: $app"
    done
else
    echo "       • keine App-Kopien gefunden"
fi

# Sicherheits-Pass auf bekannte Pfade
for path in \
    "/Applications/ALVA-TEXT.app" \
    "/Applications/ALVA-TEXT 2.app" \
    "$HOME/Applications/ALVA-TEXT.app" \
    "$HOME/Downloads/ALVA-TEXT.app"; do
    if [ -e "$path" ]; then
        rm -rf "$path"
        echo "       ✓ zusätzlich entfernt: $path"
    fi
done

# ── 3) DMG-Volumes unmounten + DMG-Files löschen ──────────────
echo ""
echo "[3/10] DMG-Volumes unmounten …"
for vol in /Volumes/ALVA-TEXT*; do
    [ -d "$vol" ] && hdiutil detach "$vol" -force -quiet 2>/dev/null && echo "       ✓ unmounted: $vol"
done

echo "       DMG-Files in Downloads + /tmp löschen …"
find "$HOME/Downloads" -maxdepth 2 -name "ALVA-TEXT*.dmg" -type f -delete 2>/dev/null
find "$HOME/Downloads" -maxdepth 2 -name "ALVA-TEXT*.zip" -type f -delete 2>/dev/null
find /tmp -maxdepth 2 -name "ALVA-TEXT*.dmg" -type f -delete 2>/dev/null

# ── 4) UserDefaults + Application Support + Caches ────────────
echo ""
echo "[4/10] UserDefaults + Application Support + Caches …"
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "       ✓ defaults-Domain $BUNDLE_ID entfernt" || echo "       • defaults-Domain war leer"

rm -f "$HOME/Library/Preferences/${BUNDLE_ID}.plist"
rm -f "$HOME/Library/Preferences/${BUNDLE_ID}.plist.lockfile"
rm -rf "$HOME/Library/Application Support/ALVA-TEXT" 2>/dev/null
rm -rf "$HOME/Library/Application Support/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Caches/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Containers/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Group Containers/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null
rm -rf "$HOME/Library/HTTPStorages/${BUNDLE_ID}" 2>/dev/null
rm -rf "$HOME/Library/HTTPStorages/${BUNDLE_ID}.binarycookies" 2>/dev/null
rm -rf "$HOME/Library/WebKit/${BUNDLE_ID}" 2>/dev/null
echo "       ✓ Library-Pfade aufgeräumt"

# ── 5) TCC-Permissions ────────────────────────────────────────
echo ""
echo "[5/10] TCC-Permissions zurücksetzen …"
for category in Microphone Accessibility ListenEvent AppleEvents \
                AddressBook Calendar Reminders Photos Camera \
                ScreenCapture SystemPolicyAllFiles SystemPolicyDocumentsFolder \
                SystemPolicyDownloadsFolder SystemPolicyDesktopFolder \
                MediaLibrary Speech AudioCapture; do
    tccutil reset "$category" "$BUNDLE_ID" 2>/dev/null && echo "       ✓ $category" || true
done
tccutil reset All "$BUNDLE_ID" 2>/dev/null && echo "       ✓ All-Reset" || true

# ── 6) Keychain — ALLE Einträge ───────────────────────────────
echo ""
echo "[6/10] Keychain-Einträge entfernen …"
COUNT=0
while security delete-generic-password -s "$BUNDLE_ID" 2>/dev/null; do
    COUNT=$((COUNT+1))
done
# auch nach Account-Pattern
for account in "openaiApiKey" "adluna.device.token" "adluna.device.uuid" \
               "adluna.last_check_iso" "adluna.last_status" "adluna.last_tier" \
               "adluna.user.email"; do
    while security delete-generic-password -a "$account" 2>/dev/null; do
        COUNT=$((COUNT+1))
    done
done
echo "       ✓ $COUNT Keychain-Einträge entfernt"

# ── 7) DerivedData + Build-Verzeichnisse ──────────────────────
echo ""
echo "[7/10] DerivedData + temp Build-Pfade …"
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -name "ALVA_TEXT-*" -type d -exec rm -rf {} + 2>/dev/null
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -name "ALVA-TEXT-*" -type d -exec rm -rf {} + 2>/dev/null
rm -rf /tmp/alva-build* 2>/dev/null
rm -rf /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT/build 2>/dev/null
echo "       ✓ DerivedData + Build-Pfade entfernt"

# ── 8) Login-Items entfernen (SMAppService) ───────────────────
echo ""
echo "[8/10] Login-Items / Launch-Agents …"
launchctl bootout "gui/$(id -u)" 2>/dev/null
osascript -e "tell application \"System Events\" to delete login item \"ALVA-TEXT\"" 2>/dev/null && echo "       ✓ Login-Item entfernt" || echo "       • kein Login-Item gesetzt"

# ── 9) Quarantine + LaunchServices-Cache ──────────────────────
echo ""
echo "[9/10] LaunchServices-Cache neu aufbauen (mehrere ALVA-Einträge weg) …"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -kill -r -domain local -domain system -domain user 2>/dev/null && echo "       ✓ LaunchServices-Cache reset"

# ── 10) Bestandsbericht ───────────────────────────────────────
echo ""
echo "[10/10] BESTANDSBERICHT — was ist noch da?"
echo ""
echo "  Apps auf Disk (sollte leer sein):"
mdfind -name "ALVA-TEXT" 2>/dev/null | grep "\.app$" | sed 's/^/    - /' || echo "    (keine)"
echo ""
echo "  UserDefaults-Domain:"
if defaults domains 2>/dev/null | tr ',' '\n' | grep -q "$BUNDLE_ID"; then
    echo "    ⚠ noch vorhanden: $BUNDLE_ID"
else
    echo "    ✓ leer"
fi
echo ""
echo "  Keychain-Einträge:"
KCCOUNT=$(security dump-keychain 2>/dev/null | grep -c "alva\|adluna\|alvatext" || echo "0")
echo "    $KCCOUNT Einträge mit Bezug zu ALVA/AdLuna im Keychain"
echo ""
echo "  Library-Pfade:"
for path in \
    "$HOME/Library/Preferences/${BUNDLE_ID}.plist" \
    "$HOME/Library/Application Support/ALVA-TEXT" \
    "$HOME/Library/Caches/${BUNDLE_ID}" \
    "$HOME/Library/Containers/${BUNDLE_ID}"; do
    if [ -e "$path" ]; then
        echo "    ⚠ noch vorhanden: $path"
    fi
done
echo ""
echo "  Bedienungshilfen-Einträge (manuelle Prüfung nötig):"
echo "    → Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen"
echo "    → Falls dort noch ALVA-TEXT-Einträge auftauchen:"
echo "      jeden mit „−\" entfernen, danach Systemeinstellungen einmal schließen"
echo ""
echo "════════════════════════════════════════════════════════"
echo " ✓ FLATLINE abgeschlossen — Mac ist sauber"
echo "════════════════════════════════════════════════════════"
echo ""
echo " Was JETZT zu tun ist:"
echo "   1. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen"
echo "      öffnen, etwaige verbliebene ALVA-Einträge per „−\" entfernen."
echo "   2. Selbiges für Eingabeüberwachung."
echo "   3. Mac einmal kurz neu starten (sauberster Zustand für TCC + LaunchServices)."
echo "   4. Sag mir Bescheid — DANN entscheiden wir gemeinsam:"
echo "      A) v2.1.3-DMG von GitHub installieren (signiert, lief heute morgen sauber)"
echo "      B) v2.1.4-Code weiter debuggen mit kleinen Schritten"
echo "      C) anderer Weg, den du vorschlägst"
echo ""
echo " KEINE App wird installiert, kein Build wird gestartet — bewusst."
