#!/usr/bin/env bash
# ALVA-TEXT — Session-Handover
# Erzeugt von Cowork am 22.04.2026 (Abend-Session-Kompression)
#
# Macht in einem Rutsch:
#   1. Stale Git-Lock entfernen (Cowork-Sandbox-Artefakt)
#   2. git add aller relevanten Dateien (inkl. neuer Files)
#   3. Commit mit vorbereiteter Message
#   4. Push nach GitHub (origin/alva-fixes-live)
#   5. rsync-Backup nach MS 512
#
# Ausführung auf dem Mac:
#   bash ~/codex-work/alper-scheel/docs/handover.sh
#
# Oder direkt (falls im Repo):
#   bash docs/handover.sh

set -euo pipefail

# ---- Konfiguration ----
REPO_ROOT="${REPO_ROOT:-$HOME/codex-work/alper-scheel}"
BRANCH="alva-fixes-live"
BACKUP_HOST="ms512@100.101.8.27"
BACKUP_PATH="~/backups/alper-scheel"

cyan()   { printf "\033[0;36m%s\033[0m\n" "$*"; }
green()  { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[0;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[0;31m%s\033[0m\n" "$*"; }

cd "$REPO_ROOT"

# ---- Schritt 1: Stale Git-Lock entfernen ----
cyan "▶ [1/5] Prüfe auf stale .git/index.lock"
if [[ -f .git/index.lock ]]; then
  yellow "  Lock gefunden — entferne."
  rm -f .git/index.lock
else
  green  "  Kein Lock vorhanden."
fi

# ---- Schritt 2: git add ----
cyan "▶ [2/5] git add"
git add \
  ALVA-TEXT/ALVA_TEXT.xcodeproj/project.pbxproj \
  ALVA-TEXT/ALVA_TEXT/AppCoordinator.swift \
  ALVA-TEXT/ALVA_TEXT/AppDelegate.swift \
  ALVA-TEXT/ALVA_TEXT/AudioRecorder.swift \
  ALVA-TEXT/ALVA_TEXT/HotkeyManager.swift \
  ALVA-TEXT/ALVA_TEXT/Info.plist \
  ALVA-TEXT/ALVA_TEXT/OpenAIService.swift \
  ALVA-TEXT/ALVA_TEXT/SettingsView.swift \
  ALVA-TEXT/ALVA_TEXT/StatusMenuController.swift \
  ALVA-TEXT/ALVA_TEXT/ALVA_TEXT.entitlements \
  ALVA-TEXT/ALVA_TEXT/LocalWhisperTranscriber.swift \
  ALVA-TEXT/ALVA_TEXT/PrivacyInfo.xcprivacy \
  docs/

# Xcode-User-Daten sind Projekt-lokaler Müll — NICHT committen.
# Falls git sie wegen alter Einträge trotzdem trackt, hier rausnehmen.
git reset -- \
  'ALVA-TEXT/ALVA_TEXT.xcodeproj/project.xcworkspace/xcuserdata' \
  'ALVA-TEXT/ALVA_TEXT.xcodeproj/xcuserdata' 2>/dev/null || true

git status --short

# ---- Schritt 3: Commit ----
cyan "▶ [3/5] git commit"
git commit -m "$(cat <<'EOF'
Chunks 5a-5g + Phase 5: local Whisper, cost tracking, permission UX, menu-bar language reference

- Phase 5: WhisperKit integration (openai_whisper-small ~466MB) as default backend;
  Cloud/Local/Auto switch in Settings; Whisper translate-task for local EN translation
- Chunk 5a: hallucination filter (regex + phrase list for [Musik], *seufzt*, subtitle stamps)
- Chunk 5b: permission UX simplified (auto-poll every 2s, Settings window surfaces,
  "Open System Settings" replaces unreliable IOHID prompt)
- Chunk 5c: API-cost tracking per call (transcription per second, chat per token),
  visible in Settings / Allgemein tab
- Chunk 5d: permission intro banner + stale-detection (auto-expand help after 4s)
- Chunk 5e: CGEventTap auto-reinstall on live permission grant (no restart needed)
- Chunk 5f: accessory-app window fix for Reverse-Translate-Popup + History
  (activation-policy trick + .floating level + orderFrontRegardless)
- Chunk 5g: menu-bar dropdown shows dynamic language quick-reference at the bottom
  (Fn+F1 → Englisch, …), rebuilt on menuWillOpen
- New files: LocalWhisperTranscriber.swift, ALVA_TEXT.entitlements,
  PrivacyInfo.xcprivacy, docs/PHASE_4_APP_STORE.md, docs/PHASE_5_LOCAL_WHISPER.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

# ---- Schritt 4: Push ----
cyan "▶ [4/5] git push origin $BRANCH"
git push origin "$BRANCH"

# ---- Schritt 5: Backup nach MS 512 ----
cyan "▶ [5/5] rsync-Backup nach $BACKUP_HOST:$BACKUP_PATH"
# Erst Zielordner anlegen (idempotent).
ssh "$BACKUP_HOST" "mkdir -p $BACKUP_PATH"

# Dann spiegeln. Git-Interna mit, DerivedData/xcuserdata nicht.
rsync -avh --delete \
  --exclude='.DS_Store' \
  --exclude='DerivedData/' \
  --exclude='**/xcuserdata/' \
  --exclude='**/project.xcworkspace/xcuserdata/' \
  "$REPO_ROOT/" \
  "$BACKUP_HOST:$BACKUP_PATH/"

green "✓ Fertig. Commit, Push, Backup alle durch."
echo
echo "Stand in GitHub:   https://github.com/Alper-Scheel/alper-scheel/tree/$BRANCH"
echo "Stand auf MS 512:  $BACKUP_HOST:$BACKUP_PATH"
