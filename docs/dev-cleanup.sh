#!/usr/bin/env bash
#
# dev-cleanup.sh — Saubere Reinitialisierung der ALVA-TEXT Dev-Umgebung
#
# Wann verwenden?
# - Wenn mehrere ALVA-TEXT-Builds (Xcode Debug, Distribution-ZIP, .dmg)
#   gleichzeitig auf der Festplatte liegen und macOS-Permissions sich
#   gegenseitig stören.
# - Wenn der Schlüsselbund-Dialog ("Immer erlauben") nach jedem Rebuild
#   wiederkommt (alte ACLs für alte Code-Signaturen).
# - Wenn die TCC-Datenbank (Bedienungshilfen / Eingabeüberwachung)
#   alte App-Einträge enthält, die mit dem aktuellen Build kollidieren.
#
# Was passiert?
# 1) Sucht alle ALVA-TEXT.app-Bundles auf der Disk und löscht sie nach
#    Bestätigung.
# 2) Löscht den Xcode-DerivedData-Ordner für ALVA_TEXT.
# 3) Reset der TCC-Permissions für com.adserica.alvatext.
# 4) Löscht alle Keychain-Einträge mit Service com.adserica.alvatext.
# 5) Löscht UserDefaults der App.
#
# Was passiert NICHT?
# - Der GitHub-Release wird nicht angefasst. ZIPs in ~/Downloads bleiben
#   liegen — die kannst du selbst löschen, wenn du willst.
# - Quellcode bleibt unberührt.
#
# Nach Lauf: Aus Xcode bauen (⌘B), Build-Output (~/Library/Developer/
# Xcode/DerivedData/ALVA_TEXT-*/Build/Products/Debug/ALVA-TEXT.app) nach
# /Applications kopieren, von dort starten — saubere First-Run-Erfahrung.

set -e

BUNDLE_ID="com.adserica.alvatext"
APP_NAME="ALVA-TEXT.app"

echo "============================================================"
echo "  ALVA-TEXT Dev-Cleanup"
echo "============================================================"
echo ""

# 1) ALVA-TEXT.app-Bundles finden
echo "1) Suche ALVA-TEXT.app-Bundles auf der Disk ..."
echo ""

# mdfind ist Spotlight-basiert — kennt auch indexierte Bundles
# außerhalb der Standard-Pfade. DerivedData filtern wir raus, weil
# Xcode dort nach Lauf eh frisch baut.
APPS=()
while IFS= read -r line; do
    APPS+=("$line")
done < <(mdfind -name "$APP_NAME" 2>/dev/null \
    | grep -v "DerivedData" \
    | grep -v "Trash" \
    | grep -v "Time Machine Backups" \
    | grep -v ".Spotlight-V100" \
    | grep -v "com.apple")

if [[ ${#APPS[@]} -eq 0 ]]; then
    echo "   → Keine Bundles gefunden außerhalb von DerivedData."
else
    for app in "${APPS[@]}"; do
        echo "   → $app"
    done
fi
echo ""

if [[ ${#APPS[@]} -gt 0 ]]; then
    read -r -p "   Alle gelisteten Bundles löschen? (y/N) " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        for app in "${APPS[@]}"; do
            if [[ -d "$app" ]]; then
                echo "   rm -rf: $app"
                rm -rf "$app"
            fi
        done
        echo "   ✅ Bundles entfernt."
    else
        echo "   ⏭️  übersprungen."
    fi
    echo ""
fi

# 2) Xcode-DerivedData
echo "2) Lösche Xcode-DerivedData für ALVA_TEXT ..."
DD_DIR="$HOME/Library/Developer/Xcode/DerivedData"
if compgen -G "$DD_DIR/ALVA_TEXT-*" > /dev/null; then
    rm -rf "$DD_DIR"/ALVA_TEXT-*
    echo "   ✅ DerivedData geleert."
else
    echo "   → Kein DerivedData für ALVA_TEXT vorhanden."
fi
echo ""

# 3) TCC-Permissions
echo "3) Reset TCC-Permissions für $BUNDLE_ID ..."
# tccutil reset All gibt 0 zurück selbst wenn Bundle unbekannt
if tccutil reset All "$BUNDLE_ID" 2>/dev/null; then
    echo "   ✅ TCC zurückgesetzt (Bedienungshilfen, Eingabeüberwachung,"
    echo "      Mikrofon, AppleEvents). Beim nächsten Start kommen die"
    echo "      Permission-Dialoge frisch."
else
    echo "   ⚠️  tccutil-Reset fehlgeschlagen (Bundle evtl. nie registriert)."
fi
echo ""

# 4) Keychain-Einträge
echo "4) Lösche Keychain-Einträge für Service $BUNDLE_ID ..."
deleted=0
# Loop bis security mit "not found" zurückkommt
while security delete-generic-password -s "$BUNDLE_ID" >/dev/null 2>&1; do
    deleted=$((deleted + 1))
done
if [[ $deleted -eq 0 ]]; then
    echo "   → Keine Keychain-Einträge gefunden."
else
    echo "   ✅ $deleted Eintrag/Einträge gelöscht."
fi
echo ""

# 5) UserDefaults — robust: erst App killen, dann delete, dann cfprefsd
#    neu starten (sonst schreibt der Cache-Daemon die alten Werte zurück)
echo "5) Lösche UserDefaults (robust mit cfprefsd-Reset) ..."

# 5a) Laufende ALVA-TEXT-Instanzen hart beenden — sonst persistiert macOS
#     beim Beenden die alten UserDefaults-Werte wieder.
killall -KILL "ALVA-TEXT" 2>/dev/null && \
    echo "   → ALVA-TEXT-Prozess(e) beendet." || \
    echo "   → Kein laufender ALVA-TEXT-Prozess."

DEFAULTS_DELETED=0
for domain in "$BUNDLE_ID" "com.AdPolis.ALVA-TEXT"; do
    if defaults read "$domain" >/dev/null 2>&1; then
        defaults delete "$domain" 2>/dev/null && {
            echo "   ✅ Domain $domain entfernt."
            DEFAULTS_DELETED=$((DEFAULTS_DELETED + 1))
        }
    fi
done
if [[ $DEFAULTS_DELETED -eq 0 ]]; then
    echo "   → Keine UserDefaults-Domain für ALVA-TEXT gefunden."
fi

# 5b) cfprefsd ist macOS' Cache-Daemon für UserDefaults. Ohne Reset würde
#     er beim nächsten App-Start seine gecachten alten Werte ausliefern,
#     selbst nachdem `defaults delete` die plist-Datei entfernt hat.
killall cfprefsd 2>/dev/null && \
    echo "   ✅ cfprefsd neu gestartet (UserDefaults-Cache geleert)." || \
    echo "   ⚠️  cfprefsd-Kill fehlgeschlagen."

echo ""

echo "============================================================"
echo "  ✅ Cleanup abgeschlossen."
echo "============================================================"
echo ""
echo "Nächste Schritte:"
echo "  1) Xcode öffnen: ALVA-TEXT.xcodeproj"
echo "  2) ⌘⇧K (Clean Build Folder)"
echo "  3) ⌘B (Build) — erzeugt frisches Bundle in DerivedData"
echo "  4) Build-Output finden:"
echo "       Product → Show Build Folder → Products/Debug/ALVA-TEXT.app"
echo "  5) Drag&Drop nach /Applications"
echo "  6) Aus /Applications starten (NICHT direkt aus Xcode mit ⌘R)"
echo "  7) Permissions frisch granten"
echo "  8) Keychain einmalig 'Immer erlauben' — bleibt für diese"
echo "     Build-Signatur stabil"
echo ""
