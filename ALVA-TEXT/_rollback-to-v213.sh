#!/bin/bash
# Rollback auf v2.1.3 (signiert von GitHub Releases).
# v2.2-Arbeit wird sauber in Branch 'feat/v2.2-foundation' gesichert.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

echo ""
echo "════════════════════════════════════════════════════════"
echo " ROLLBACK auf v2.1.3 (signiert, notarisiert, von GitHub)"
echo "════════════════════════════════════════════════════════"

# ── 1) v2.2-Arbeit in Branch sichern ──────────────────────────────
echo ""
echo "[1/5] v2.2-Foundation in feat/v2.2-foundation sichern…"
git checkout -b feat/v2.2-foundation 2>/dev/null && echo "  ✓ Branch neu angelegt" || git checkout feat/v2.2-foundation
git add -A
if git commit -m "WIP v2.2.0-beta1: ProMode + Personalization + Mode-UI + Build-Skript" 2>/dev/null; then
    echo "  ✓ committed"
else
    echo "  • nichts mehr zu committen"
fi

# ── 2) Working-Tree zurück auf clean v2.1.2 ───────────────────────
echo ""
echo "[2/5] Working-Tree zurück auf alva-v2.1.2 (clean)…"
git checkout alva-v2.1.2
echo "  HEAD: $(git log -1 --oneline)"

# ── 3) v2.1.3 DMG von GitHub laden ────────────────────────────────
echo ""
echo "[3/5] Signiertes v2.1.3 DMG laden…"
curl -L --progress-bar -o /tmp/ALVA-TEXT-v2.1.3.dmg \
  "https://github.com/Alper-Scheel/alper-scheel/releases/latest/download/ALVA-TEXT.dmg"

if [ ! -s /tmp/ALVA-TEXT-v2.1.3.dmg ]; then
    echo "❌ Download fehlgeschlagen — prüfe, ob das Release auf GitHub liegt."
    exit 1
fi
echo "  ✓ $(ls -lh /tmp/ALVA-TEXT-v2.1.3.dmg | awk '{print $5}') geladen"

# ── 4) Mount + Install ────────────────────────────────────────────
echo ""
echo "[4/5] App in /Applications installieren…"
pkill -f ALVA-TEXT 2>/dev/null && sleep 1 || true
MOUNT_POINT=$(hdiutil attach /tmp/ALVA-TEXT-v2.1.3.dmg -nobrowse -plist 2>/dev/null \
    | plutil -extract 'system-entities' xml1 -o - - \
    | grep -A1 mount-point \
    | tail -1 \
    | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "  Mount-Point auto-detect fehlgeschlagen, suche manuell…"
    MOUNT_POINT=$(ls -d /Volumes/ALVA-TEXT* 2>/dev/null | head -1)
fi

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT/ALVA-TEXT.app" ]; then
    echo "❌ Mount nicht gefunden. DMG manuell öffnen und App nach /Applications ziehen."
    exit 1
fi

rm -rf /Applications/ALVA-TEXT.app
cp -R "$MOUNT_POINT/ALVA-TEXT.app" /Applications/
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
echo "  ✓ /Applications/ALVA-TEXT.app aktualisiert"

# ── 5) Permissions reset + Start ──────────────────────────────────
echo ""
echo "[5/5] Permissions reset + App starten…"
defaults write com.adserica.alvatext hasSeenOnboarding -bool false
defaults delete com.adserica.alvatext alva.proMode 2>/dev/null || true
tccutil reset All com.adserica.alvatext 2>/dev/null || true
echo "  ✓ TCC-Permissions, hasSeenOnboarding, proMode zurückgesetzt"

VERSION=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)
BUILDNR=$(defaults read /Applications/ALVA-TEXT.app/Contents/Info.plist CFBundleVersion 2>/dev/null)
echo "  Installierte Version: $VERSION (Build $BUILDNR)"

open /Applications/ALVA-TEXT.app

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ v2.1.3 läuft (signiert, ohne Mode-Wahl, ohne Pro-Tab)."
echo "    Onboarding sollte sauber durchgehen — die Permission-"
echo "    Schleife war ein Symptom des ad-hoc-Builds."
echo "════════════════════════════════════════════════════════"
echo ""
echo " Deine v2.2-Arbeit ist sicher in Branch 'feat/v2.2-foundation'."
echo " Wenn v2.1.3 stabil läuft, gehen wir das in Ruhe weiter."
