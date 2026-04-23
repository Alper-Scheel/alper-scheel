#!/usr/bin/env bash
# deploy-platform-api.sh — AdLuna Platform API auf MS512 ausrollen.
#
# Annahmen (siehe CC_AUFTRAG_ALVA_PLATFORM_API_INFRA.md):
#   - MS512 erreichbar via Tailscale (ssh ms512@100.101.8.27)
#   - Zielpfad: ~ms512/adluna-platform-api/
#   - Python 3.12 + uv installiert
#   - cloudflared läuft mit Tunnel-Config für api.adluna.de → 127.0.0.1:8080
#   - launchd-Service: de.adluna.platform-api.plist (siehe bottom of this file)
#
# Verwendung:
#   bash docs/deploy-platform-api.sh           → Deploy + Restart
#   bash docs/deploy-platform-api.sh --dry     → nur rsync simulieren
#   bash docs/deploy-platform-api.sh --logs    → tail Journal nach Deploy

set -euo pipefail

SSH_HOST="${SSH_HOST:-ms512@100.101.8.27}"
REMOTE_ROOT="${REMOTE_ROOT:-/Users/ms512/services/adluna-platform-api}"
LOCAL_ROOT="$(cd "$(dirname "$0")/../services/adluna-platform-api" && pwd)"
SERVICE_LABEL="de.adluna.platform-api"

if [[ "${1:-}" == "--dry" ]]; then
    RSYNC_FLAGS="-avhn --delete"
    shift
else
    RSYNC_FLAGS="-avh --delete"
fi

echo "──────────────────────────────────────────────────────────────────"
echo "Deploy AdLuna Platform API"
echo "  Source  : $LOCAL_ROOT"
echo "  Target  : ${SSH_HOST}:${REMOTE_ROOT}"
echo "  Service : $SERVICE_LABEL"
echo "──────────────────────────────────────────────────────────────────"

if [[ ! -f "$LOCAL_ROOT/app/main.py" ]]; then
    echo "✗ Source nicht gefunden: $LOCAL_ROOT/app/main.py" >&2
    exit 1
fi

# 1) Remote-Ziel sicherstellen
ssh "$SSH_HOST" "mkdir -p '$REMOTE_ROOT' '$REMOTE_ROOT/data'"

# 2) Code syncen (ohne .env — der Server hält seine eigene)
rsync $RSYNC_FLAGS \
    --exclude='.env' \
    --exclude='data/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.pytest_cache/' \
    --exclude='.venv/' \
    --exclude='data/license.db' \
    "$LOCAL_ROOT/" "${SSH_HOST}:${REMOTE_ROOT}/"

if [[ "$RSYNC_FLAGS" == *"n"* ]]; then
    echo "Dry-Run fertig — kein Server-Restart."
    exit 0
fi

# 3) Venv + Dependencies auf dem Server
ssh "$SSH_HOST" "cd '$REMOTE_ROOT' && \
    command -v uv >/dev/null 2>&1 && { \
        uv venv --python 3.12 .venv; \
        source .venv/bin/activate; \
        uv pip install -r requirements.txt; \
    } || { \
        python3.12 -m venv .venv; \
        source .venv/bin/activate; \
        pip install --upgrade pip; \
        pip install -r requirements.txt; \
    }"

# 4) Migrations + Seed
ssh "$SSH_HOST" "cd '$REMOTE_ROOT' && \
    source .venv/bin/activate && \
    alembic upgrade head && \
    python -m seed"

# 5) launchd-Service neu starten (zentrales Reload für macOS)
ssh "$SSH_HOST" "launchctl kickstart -k gui/\$(id -u)/${SERVICE_LABEL}" \
    || echo "⚠ launchd-Service ${SERVICE_LABEL} nicht registriert — siehe README."

# 6) Health prüfen
sleep 2
HEALTH=$(ssh "$SSH_HOST" "curl -fsS http://127.0.0.1:8080/health" || echo "unreachable")
echo "Health: $HEALTH"

if [[ "${1:-}" == "--logs" ]]; then
    ssh "$SSH_HOST" "tail -n 100 -f /Users/ms512/Library/Logs/adluna-platform-api.log"
fi

echo "──────────────────────────────────────────────────────────────────"
echo "Deploy complete."
echo "──────────────────────────────────────────────────────────────────"


# ---- launchd-Service-Template (nur Referenz — auf dem Server ablegen) ----
#
# Pfad:  ~/Library/LaunchAgents/de.adluna.platform-api.plist
# Load:  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.adluna.platform-api.plist
# Unload: launchctl bootout gui/$(id -u)/de.adluna.platform-api
#
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#   <key>Label</key><string>de.adluna.platform-api</string>
#   <key>WorkingDirectory</key><string>/Users/ms512/services/adluna-platform-api</string>
#   <key>ProgramArguments</key>
#   <array>
#     <string>/Users/ms512/services/adluna-platform-api/.venv/bin/uvicorn</string>
#     <string>app.main:app</string>
#     <string>--host</string><string>127.0.0.1</string>
#     <string>--port</string><string>8080</string>
#     <string>--workers</string><string>2</string>
#     <string>--proxy-headers</string>
#     <string>--forwarded-allow-ips=*</string>
#   </array>
#   <key>EnvironmentVariables</key>
#   <dict>
#     <key>LICENSE_SERVER_ENV</key><string>production</string>
#     <key>LICENSE_SERVER_DB_PATH</key><string>/Users/ms512/services/adluna-platform-api/data/license.db</string>
#   </dict>
#   <key>RunAtLoad</key><true/>
#   <key>KeepAlive</key><true/>
#   <key>StandardOutPath</key><string>/Users/ms512/Library/Logs/adluna-platform-api.log</string>
#   <key>StandardErrorPath</key><string>/Users/ms512/Library/Logs/adluna-platform-api.log</string>
# </dict>
# </plist>
