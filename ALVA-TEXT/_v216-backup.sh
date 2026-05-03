#!/usr/bin/env bash
# v2.1.6 Backup-Script — Defense-in-Depth
# Stage + Commit + Tag + Bundle + Push
#
# Aufruf:  bash ~/codex-work/alper-scheel/ALVA-TEXT/_v216-backup.sh
#
# Schritte:
#   1) Working tree → Stage → Commit (alva-v2.1.5 branch)
#   2) Tag v2.1.6 vom alten Commit auf neuen Commit verschieben (force)
#   3) Push branch + Tag zu origin (GitHub)
#   4) Git-Bundle auf ~/Desktop/alva-text-v2.1.6-YYYYMMDD-HHMM.bundle
#   5) Sync-Verifikation
#
# Sicherheit: bricht bei Fehler ab (set -e). Tag-Move ist --force.

set -e
set -u

REPO="$HOME/codex-work/alper-scheel"
DATE_TAG="$(date +%Y%m%d-%H%M)"
BUNDLE="$HOME/Desktop/alva-text-v2.1.6-${DATE_TAG}.bundle"
TAG="v2.1.6"
BRANCH="alva-v2.1.5"

cd "$REPO"

echo "════════════════════════════════════════════════════════════════"
echo "  v2.1.6 BACKUP — alper-scheel Repo"
echo "  $(date)"
echo "════════════════════════════════════════════════════════════════"

# 0) Stale Lock entfernen (falls von Sandbox-Versuchen übrig)
if [[ -f .git/index.lock ]]; then
  echo "→ Entferne stale .git/index.lock"
  rm -f .git/index.lock
fi

# 1) Pre-Flight: Branch + Status
echo ""
echo "──── 1. Pre-Flight ─────────────────────────────────────────────"
CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  echo "✘ ABBRUCH: Aktueller Branch ist '$CURRENT_BRANCH', erwartet '$BRANCH'"
  exit 1
fi
echo "✓ Branch: $BRANCH"
echo "✓ Working tree:"
git status --short | head -30

# 2) Stage v2.1.6 Änderungen
echo ""
echo "──── 2. Stage v2.1.6 Änderungen ────────────────────────────────"
git add ALVA-TEXT/ALVA_TEXT.xcodeproj/project.pbxproj \
        ALVA-TEXT/ALVA_TEXT.xcodeproj/xcshareddata \
        ALVA-TEXT/ALVA_TEXT/ActivationView.swift \
        ALVA-TEXT/ALVA_TEXT/AppCoordinator.swift \
        ALVA-TEXT/ALVA_TEXT/AppDelegate.swift \
        ALVA-TEXT/ALVA_TEXT/Info.plist \
        ALVA-TEXT/ALVA_TEXT/LicenseState.swift \
        ALVA-TEXT/ALVA_TEXT/OpenAIService.swift \
        ALVA-TEXT/ALVA_TEXT/SettingsView.swift \
        ALVA-TEXT/ROADMAP.md \
        ALVA-TEXT/_BUGS_AND_LEARNINGS.md \
        ALVA-TEXT/_TESTS_v2.1.6.md \
        ALVA-TEXT/_backup-now.sh \
        ALVA-TEXT/_check-openai-key.sh \
        ALVA-TEXT/_flatline.sh \
        ALVA-TEXT/_install-v213-from-github.sh \
        ALVA-TEXT/_revoke-devices.sh \
        ALVA-TEXT/_v214-build.sh \
        ALVA-TEXT/_v214-clean-install.sh \
        ALVA-TEXT/_v215-release-build.sh \
        ALVA-TEXT/_v216-backup.sh \
        ALVA-TEXT/_v216-clean-test-install.sh \
        ALVA-TEXT/_v216-release-build.sh \
        Projekt-Setup.md \
        services/adluna-platform-api/app/endpoints/license.py

echo "✓ Staged:"
git diff --cached --stat | tail -8

# 3) Commit
echo ""
echo "──── 3. Commit ─────────────────────────────────────────────────"
git commit -m "v2.1.6: Stable release — License-Gate + Wake-Persistence + Cloud-Timeout

Major Fixes (testing-validated 2026-05-02):
  #B3  License-Gate enforced: beginRecording + startReverseTranslate
       blocked when !LicenseState.shared.phase.isUsable
       (Phase.isUsable .loading → false, fixed race condition)
  #B-Wake  Sleep/Wake mode persistence: UserDefaults.synchronize() in
       transcriptionBackend.didSet + NSWorkspace.didWakeNotification
       handler in AppDelegate that re-hydrates user preferences
  #B-Cloud Cloud transcribe hang: URLSession timeoutInterval = 30
       (transcribe) / 12 (chat) — was using default 60s
  #B-Auto Auto-Restart loop on permission grant: scheduleAutoRestart()
       deactivated, replaced with user banner

UX/Wording Cleanup:
  #B16  'Prüfen' button removed from API-Key UI
  #B17  Server message: 'Beta access active' → 'Vollzugang aktiv'
  #B18  Defense-in-depth: client-side currentMessage sanitizer
        filters Beta strings
  ActivationView: 'Beta-Zugang' → 'Vollzugang', error suppression
        in done-step

API Key Validation:
  APIKeyValidation enum + async validateAPIKey()
  validateStoredAPIKeyOnLaunch() at startup
  apiKey.didSet triggers async validation
  apiKeyValidationLabel ViewBuilder in SettingsView

Build/Version:
  CFBundleShortVersionString: 2.1.5 → 2.1.6
  CFBundleVersion: 27 → 28
  MARKETING_VERSION + CURRENT_PROJECT_VERSION analog im pbxproj
  Shared xcscheme für reproducible -derivedDataPath builds

Documentation:
  ROADMAP.md     — Hardware-Tier-Strategie für v3.0 lokales LLM
  Projekt-Setup.md — Engineering-Playbook (12 Sektionen)
  _BUGS_AND_LEARNINGS.md — persistenter Bug-Tracker (#B1-#B18)
  _TESTS_v2.1.6.md — Test-Checkliste (alle grün)

Server (services/adluna-platform-api):
  license.py — alle englischen Strings übersetzt (revoked,
  expired, trial, beta→Vollzugang)

Tested: License-Gate ✓, Wake/Sleep persistence ✓,
        Cloud timeout ✓, alle 4 Hotkey-Modi ✓
        (Control, Option, Control+Option, Option+Command)
"

echo "✓ Commit erstellt:"
git log -1 --oneline

# 4) Tag verschieben
echo ""
echo "──── 4. Tag v2.1.6 verschieben ────────────────────────────────"
NEW_HEAD="$(git rev-parse HEAD)"
OLD_TAG_TARGET="$(git rev-parse $TAG 2>/dev/null || echo 'none')"
echo "  Alt: $TAG → $OLD_TAG_TARGET"
echo "  Neu: $TAG → $NEW_HEAD"
git tag -d "$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "v2.1.6 — Stable release

License-Gate enforced, Sleep/Wake persistence, Cloud-timeout fix.
All systematic tests passed 2026-05-02.

See commit message for full changelog."
echo "✓ Tag $TAG verschoben"

# 5) Lokales Bundle (Defense-in-Depth)
echo ""
echo "──── 5. Lokales Git-Bundle ─────────────────────────────────────"
git bundle create "$BUNDLE" --all
BUNDLE_SIZE="$(du -h "$BUNDLE" | cut -f1)"
echo "✓ Bundle erstellt: $BUNDLE ($BUNDLE_SIZE)"

# 6) Push (Branch + Tag --force für Tag-Move)
echo ""
echo "──── 6. Push zu origin (GitHub) ───────────────────────────────"
echo "→ git push origin $BRANCH"
git push origin "$BRANCH"
echo "→ git push origin $TAG --force (Tag-Move)"
git push origin "$TAG" --force

# 7) Verifikation
echo ""
echo "──── 7. Verifikation ──────────────────────────────────────────"
LOCAL_HEAD="$(git rev-parse $BRANCH)"
REMOTE_HEAD="$(git rev-parse origin/$BRANCH)"
LOCAL_TAG="$(git rev-parse $TAG)"
REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"

echo "  Branch local:  $LOCAL_HEAD"
echo "  Branch remote: $REMOTE_HEAD"
echo "  Tag local:     $LOCAL_TAG"
echo "  Tag remote:    $REMOTE_TAG"

if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] && [[ "$LOCAL_TAG" == "$REMOTE_TAG" ]]; then
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  ✓ BACKUP ERFOLGREICH"
  echo "════════════════════════════════════════════════════════════════"
  echo "  Branch:  $BRANCH @ $LOCAL_HEAD"
  echo "  Tag:     $TAG"
  echo "  Bundle:  $BUNDLE ($BUNDLE_SIZE)"
  echo "  GitHub:  https://github.com/Alper-Scheel/alper-scheel/tree/$BRANCH"
  echo "  Release: https://github.com/Alper-Scheel/alper-scheel/releases/tag/$TAG"
  echo "════════════════════════════════════════════════════════════════"
else
  echo ""
  echo "✘ WARNUNG: Sync nicht vollständig. Bitte manuell prüfen."
  exit 2
fi
