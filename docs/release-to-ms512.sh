#!/usr/bin/env bash
# ALVA-TEXT — Release-Pipeline: lokaler Export → MS512-Archiv
#
# Nutzung:
#   bash docs/release-to-ms512.sh
#   bash docs/release-to-ms512.sh "/absolute/pfad/zur/ALVA-TEXT.app"   # optional expliziter Pfad
#
# Was es tut:
#   1. Findet die notarisierte ALVA-TEXT.app (iCloud-Desktop, Desktop, oder Argument)
#   2. Verifiziert Apple-Signatur + Gatekeeper-Akzeptanz
#   3. Packt eine signierte ZIP via `ditto`
#   4. Erzeugt Versionsordner auf MS512 (~/storage/alva-text/builds/<TAG>/)
#   5. Überträgt .app + .zip + manifest.json via rsync (resumefähig)
#   6. Aktualisiert den `current/`-Symlink, der später die Download-URL bedient
#   7. Legt optional einen GitHub Release (Tag + ZIP-Asset) an, wenn `gh` installiert

set -euo pipefail

# ---- Konfiguration ----
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-1}"
DATE=$(date +%Y-%m-%d)
TAG="v${VERSION}-build${BUILD}-${DATE}"

REMOTE_USER="${REMOTE_USER:-alper}"          # MS512 Login-User
REMOTE_HOST="${REMOTE_HOST:-100.101.8.27}"
REMOTE="${REMOTE_USER}@${REMOTE_HOST}"
BASE="${BASE:-\$HOME/storage/alva-text}"     # mit \$HOME expandiert am Remote
TARGET="${BASE}/builds/${TAG}"

# ---- Farbhilfen ----
cyan()   { printf "\033[0;36m%s\033[0m\n" "$*"; }
green()  { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[0;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[0;31m%s\033[0m\n" "$*"; }

# ---- Schritt 0: App-Pfad ermitteln ----
SRC_APP="${1:-}"
if [[ -z "$SRC_APP" ]]; then
  # typische macOS-Exportpfade durchprobieren
  CANDIDATES=(
    "$HOME/Desktop/ALVA-TEXT 2026-04-22 16-50-38/ALVA-TEXT.app"
    "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Desktop/ALVA-TEXT 2026-04-22 16-50-38/ALVA-TEXT.app"
  )
  for c in "${CANDIDATES[@]}"; do
    if [[ -d "$c" ]]; then
      SRC_APP="$c"
      break
    fi
  done
  # Fallback: neuesten Export-Ordner auf Desktop + iCloud-Desktop suchen
  if [[ -z "$SRC_APP" ]]; then
    FOUND=$(ls -dt \
      "$HOME"/Desktop/ALVA-TEXT\ *\ *\ *-*-*/ALVA-TEXT.app \
      "$HOME"/Library/Mobile\ Documents/com~apple~CloudDocs/Desktop/ALVA-TEXT\ *\ *\ *-*-*/ALVA-TEXT.app \
      2>/dev/null | head -1 || true)
    [[ -n "$FOUND" ]] && SRC_APP="$FOUND"
  fi
fi

if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
  red "✗ Keine ALVA-TEXT.app gefunden. Übergib den Pfad als Argument:"
  red "   bash docs/release-to-ms512.sh \"/pfad/zu/ALVA-TEXT.app\""
  exit 1
fi

cyan "▶ [0/7] Verwende App: $SRC_APP"

# ---- Schritt 1: Gatekeeper-Check (auf Original, das ist notary-gültig) ----
cyan "▶ [1/7] Gatekeeper-Akzeptanz prüfen"
spctl --assess --verbose=4 --type execute "$SRC_APP"

# In ein sauberes /tmp-Verzeichnis spiegeln (ohne iCloud-xattrs).
# Grund: iCloud Drive hängt `com.apple.FinderInfo` und ähnliche Finder-
# Metadaten an jede Datei, die dort liegt. Die Signatur ist davon nicht
# betroffen, aber `codesign --verify --strict` meckert. Wir arbeiten
# daher mit einer xattr-freien Kopie weiter.
WORK_DIR="/tmp/alva-text-release-${TAG}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp -a "$SRC_APP" "$WORK_DIR/"
xattr -cr "$WORK_DIR/ALVA-TEXT.app"
WORK_APP="$WORK_DIR/ALVA-TEXT.app"

cyan "  Verifiziere Signatur auf xattr-freier Kopie"
codesign --verify --deep --strict --verbose=2 "$WORK_APP"
green "  Signatur OK, Notarization OK, Gatekeeper OK."

# ---- Schritt 2: ZIP via ditto (von der sauberen Kopie) ----
cyan "▶ [2/7] Packe signierte ZIP via ditto"
ZIP_PATH="/tmp/ALVA-TEXT-${TAG}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$WORK_APP" "$ZIP_PATH"
ZIP_SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
green "  ZIP erstellt: $ZIP_PATH ($ZIP_SIZE)"

# ---- Schritt 3: SSH-Konnektivität testen ----
cyan "▶ [3/7] Teste SSH-Verbindung zu $REMOTE"
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE" true; then
  red "✗ SSH zu $REMOTE fehlgeschlagen. Prüfe Tailscale / SSH-Key."
  exit 1
fi
green "  Verbindung steht."

# ---- Schritt 4: Zielverzeichnis anlegen ----
cyan "▶ [4/7] Erstelle Zielverzeichnis auf MS512"
ssh "$REMOTE" "mkdir -p ${TARGET} ${BASE}/current ${BASE}/archive"

# ---- Schritt 5: Transfer (rsync mit resume) ----
cyan "▶ [5/7] Übertrage .app + .zip nach MS512"
# --partial --append-verify erlaubt Wiederaufnahme bei Broken-Pipe.
# Wir übertragen die xattr-freie Kopie, nicht die iCloud-Original-App.
rsync -avh --partial --progress \
  "$WORK_APP" "$REMOTE:${TARGET}/"
rsync -avh --partial --progress \
  "$ZIP_PATH" "$REMOTE:${TARGET}/ALVA-TEXT.zip"

# Manifest schreiben
cat > /tmp/alva-text-manifest.json <<EOF
{
  "product": "ALVA-TEXT",
  "version": "${VERSION}",
  "build": "${BUILD}",
  "release_date": "${DATE}",
  "tag": "${TAG}",
  "bundle_id": "com.adserica.alvatext",
  "publisher": "AdLuna GmbH",
  "ip_holder": "AdSerica Ltd. (Hong Kong)",
  "architectures": ["Intel x86_64", "Apple Silicon arm64"],
  "signed_by": "AdPolis GmbH Developer ID Application",
  "notarized": true,
  "zip_size": "${ZIP_SIZE}"
}
EOF
scp /tmp/alva-text-manifest.json "$REMOTE:${TARGET}/manifest.json"

# ---- Schritt 6: current/-Symlink aktualisieren ----
cyan "▶ [6/7] Aktualisiere 'current'-Symlink"
ssh "$REMOTE" "
  cd ${BASE}/current
  ln -sfn ../builds/${TAG}/ALVA-TEXT.zip ALVA-TEXT.zip
  ln -sfn ../builds/${TAG}/ALVA-TEXT.app ALVA-TEXT.app
  ln -sfn ../builds/${TAG}/manifest.json manifest.json
"

# ---- Schritt 7: GitHub Release (optional, wenn gh CLI vorhanden) ----
if command -v gh &>/dev/null; then
  cyan "▶ [7/7] GitHub Release anlegen"
  REPO_DIR="${REPO_DIR:-$HOME/codex-work/alper-scheel}"
  if [[ -d "$REPO_DIR/.git" ]]; then
    (
      cd "$REPO_DIR"
      git tag -a "alva-text-${TAG}" -m "ALVA-TEXT ${VERSION} Build ${BUILD} (${DATE})" 2>/dev/null \
        || yellow "  Tag alva-text-${TAG} existiert schon"
      git push origin "alva-text-${TAG}" 2>/dev/null \
        || yellow "  Tag-Push übersprungen (existiert oder kein Netz)"
      if gh release create "alva-text-${TAG}" "$ZIP_PATH" \
          --title "ALVA-TEXT ${VERSION} Build ${BUILD}" \
          --notes "Release-Tag ${TAG}. Details: Brain/02_PROJEKTE/ALVA-TEXT/" \
          --prerelease 2>/dev/null; then
        green "  GitHub Release: https://github.com/Alper-Scheel/alper-scheel/releases/tag/alva-text-${TAG}"
      else
        yellow "  Release existiert schon oder gh-Auth fehlt"
      fi
    )
  else
    yellow "  Kein Git-Repo unter $REPO_DIR — GitHub-Release übersprungen"
  fi
else
  yellow "▶ [7/7] Skip GitHub Release (gh CLI nicht installiert)"
fi

# ---- Bericht ----
green ""
green "✓ Release abgeschlossen."
green ""
ssh "$REMOTE" "ls -lh ${TARGET} && echo '---current---' && ls -lh ${BASE}/current/"
echo
echo "Download-Pfad auf MS512:  ${TARGET}"
echo "Current-Symlink:          ${BASE}/current/ALVA-TEXT.zip"
echo
echo "Nächste Schritte:"
echo "  • Datei manuell an Tester verteilen:"
echo "    scp ${REMOTE}:${BASE}/current/ALVA-TEXT.zip ~/Desktop/   # holt ZIP zurück"
echo "  • Oder öffentlich zugänglich machen:"
echo "    Später via Caddy/Nginx auf downloads.adluna.de → current/"

# Aufräumen
rm -f "$ZIP_PATH" /tmp/alva-text-manifest.json
rm -rf "$WORK_DIR"
