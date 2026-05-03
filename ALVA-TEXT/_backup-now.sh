#!/bin/bash
# Vollständiges Backup: GitHub-Push aller offenen Branches + lokales Git-Bundle.

set -u
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

echo ""
echo "════════════════════════════════════════════════════════"
echo " BACKUP — GitHub-Push + lokales Bundle"
echo "════════════════════════════════════════════════════════"

echo ""
echo "[1/4] Push feat/v2.2-foundation auf GitHub (kritisch)…"
git push -u origin feat/v2.2-foundation

echo ""
echo "[2/4] Push alva-fixes-live (1 Commit ahead)…"
git push origin alva-fixes-live

echo ""
echo "[3/4] Push aller Tags…"
git push origin --tags

echo ""
echo "[4/4] Lokales Bundle-Backup auf Desktop…"
TS=$(date +%Y%m%d-%H%M)
BACKUP="/Users/AdPolis/Desktop/alva-text-backup-${TS}.bundle"
git bundle create "$BACKUP" --all
SIZE=$(ls -lh "$BACKUP" | awk '{print $5}')

echo ""
echo "=== Verifikation: Branches synchron mit GitHub ==="
git fetch origin --quiet
git branch -avv | grep -E "alva-v2.1.2|feat/v2.2|alva-fixes-live" | head -10

echo ""
echo "════════════════════════════════════════════════════════"
echo " ✅ Backup komplett"
echo "════════════════════════════════════════════════════════"
echo ""
echo " GitHub-Backup:"
echo "   • alva-v2.1.2          (stable, online auf adluna.de via Release)"
echo "   • feat/v2.2-foundation (deine v2.2-Arbeit, jetzt remote-gesichert)"
echo "   • alva-fixes-live      (1 commit synced)"
echo "   • Tags                 (v2.1.2)"
echo ""
echo " Lokales Bundle (Defense-in-Depth):"
echo "   $BACKUP  ($SIZE)"
echo ""
echo " → Empfehlung: Bundle auf NAS-4 (cold-storage) oder ins"
echo "   Brain-Vault verschieben. Mit dem Bundle lässt sich das"
echo "   gesamte Repo notfalls auf jedem anderen Mac per"
echo "   'git clone <bundle-pfad> ALVA-TEXT-restore' wiederherstellen."
