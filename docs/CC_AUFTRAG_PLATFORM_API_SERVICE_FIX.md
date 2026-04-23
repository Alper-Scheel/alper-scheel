---
auftrag: AdLuna Platform API — Launchd-Service fixen + End-to-End verifizieren
empfaenger: Claude Code (CC) auf MacBook Pro
auftraggeber: Alper Scheel
erstellt: 2026-04-23 10:30 MEZ
prioritaet: P0 — 502 blockiert ALVA-TEXT-Release
laufzeit: 15–25 min autonom via SSH
voraussetzungen: SSH-Zugang zu ms512@100.101.8.27 (bestehend, passwordless)
---

# Auftrag: Platform-API-Service auf MS512 fixen

## Aktueller Stand (wichtig zu wissen)

**Bereits erledigt (funktioniert):**
- Code + venv + Alembic + Seed sind auf MS512 komplett (`/Users/ms512/services/adluna-platform-api/`)
- `.env` ist dort mit Resend-Key + Admin-Token
- Uvicorn läuft manuell gestartet einwandfrei (getestet: `curl http://127.0.0.1:8080/health` → `{"ok":true,"service":"adluna-platform-api","version":"0.1.0","env":"production"}`)
- Cloudflare-Tunnel `ms512-adluna-api` (UUID `64116a57-52c4-4f21-acc5-f87882b58dde`) ist aktiv und healthy
- Public Hostname `api.adluna.de → 127.0.0.1:8080` steht
- DNS propagiert: `curl https://api.adluna.de/` liefert **HTTP 502** (= Tunnel erreicht Upstream nicht, weil Service nicht permanent läuft)

**Das einzige Problem:**
Das launchd-Plist `~/Library/LaunchAgents/de.adluna.platform-api.plist` wurde über einen kaputten HEREDOC geschrieben. `plutil -lint` meldet „Encountered unexpected character k on line 19". Deshalb schlägt `launchctl bootstrap` mit „Input/output error" fehl, der Service läuft nicht dauerhaft, Cloudflare liefert 502.

## Dein Auftrag — drei Schritte

### Schritt 1: Plist via Python plistlib sauber neu schreiben

Python's `plistlib` erzeugt garantiert validen XML. HEREDOC/Shell-Expansion vermeiden.

```bash
ssh ms512@100.101.8.27 '/usr/bin/python3 << "PYEOF"
import plistlib, pathlib
p = pathlib.Path.home() / "Library/LaunchAgents/de.adluna.platform-api.plist"
plistlib.dump({
    "Label": "de.adluna.platform-api",
    "WorkingDirectory": "/Users/ms512/services/adluna-platform-api",
    "ProgramArguments": [
        "/Users/ms512/services/adluna-platform-api/.venv/bin/uvicorn",
        "app.main:app",
        "--host", "127.0.0.1",
        "--port", "8080",
        "--workers", "2",
        "--proxy-headers",
        "--forwarded-allow-ips=*",
    ],
    "EnvironmentVariables": {
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        "LICENSE_SERVER_ENV": "production",
        "LICENSE_SERVER_DB_PATH": "/Users/ms512/services/adluna-platform-api/data/license.db",
    },
    "StandardOutPath": "/Users/ms512/services/adluna-platform-api/logs/stdout.log",
    "StandardErrorPath": "/Users/ms512/services/adluna-platform-api/logs/stderr.log",
    "RunAtLoad": True,
    "KeepAlive": True,
    "ThrottleInterval": 10,
}, p.open("wb"))
print("wrote", p)
PYEOF
plutil -lint ~/Library/LaunchAgents/de.adluna.platform-api.plist
'
```

**Akzeptanz:** `plutil -lint` sagt „OK".

### Schritt 2: Service (re-)bootstrappen

```bash
ssh ms512@100.101.8.27 '
  launchctl bootout gui/$(id -u)/de.adluna.platform-api 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.adluna.platform-api.plist
  sleep 3
  launchctl list | grep adluna
  tail -n 30 ~/services/adluna-platform-api/logs/stderr.log
'
```

**Akzeptanz:**
- `launchctl list | grep adluna` zeigt PID + Label
- stderr.log zeigt Uvicorn-Startup ohne Tracebacks

### Schritt 3: End-to-End-Verifikation

```bash
# Lokal auf MS512
ssh ms512@100.101.8.27 'curl -sS http://127.0.0.1:8080/health'

# Durch den Cloudflare Tunnel (von deinem Mac)
curl -sS https://api.adluna.de/health

# Admin-Endpoint mit Bearer-Auth
curl -sS https://api.adluna.de/v1/admin/stats \
  -H "Authorization: Bearer Qq6DsH1zfZSNRCtdOAUbUwosP2nIaQdsnOyq7WcJwcRUTaU_gbz-Nv7KhnRzVfSL"

# Echte Aktivierungs-Mail triggern (Resend-Verifikation)
curl -sS -X POST https://api.adluna.de/v1/activation/request \
  -H 'content-type: application/json' \
  -d '{"email":"alper.scheel@gmail.com","product":"alva-text","device_uuid":"00000000-0000-0000-0000-000000000001"}'
```

**Akzeptanz aller vier Calls:**
1. Local health: `{"ok":true,...}`
2. Public health: `{"ok":true,...}` (200 OK, nicht mehr 502)
3. Admin stats: `{"total_users":1,...,"products":["alva-text"]}` (User `alper.scheel@gmail.com` ist durch den vierten Call schon angelegt)
4. Activation request: `{"ok":true,"message":"Code sent to alper.scheel@gmail.com ..."}` — und eine echte 6-stellige Code-Mail landet in Alpers Gmail-Postfach

## Rückmeldung an Alper

Kurz:
1. launchctl-Status (PID vorhanden?)
2. `/health` via Cloudflare-URL: HTTP-Code
3. Echte Aktivierungs-Mail von `no-reply@mail.adluna.de` angekommen? (Alper checkt Gmail)
4. Blocker, falls aufgetreten (exakte Fehlermeldung)

## Referenz

- Repo: `~/codex-work/alper-scheel` (MacBook)
- Server-Pfade:
  - `~/services/adluna-platform-api/` — Code + venv + .env + data/license.db
  - `~/Library/LaunchAgents/de.adluna.platform-api.plist` — Service-Definition
  - `~/services/adluna-platform-api/logs/{stdout,stderr}.log` — Logs
- Admin-Token: siehe Brain-Vault `_SYSTEM/Zugangsdaten_AdLuna_PlatformAPI.md`
- Existierende Dokumentation: `docs/deploy-platform-api.sh`, `services/adluna-platform-api/README.md`

---

*Erzeugt 23.04.2026 10:30 MEZ. Cowork hat App+Deploy+Tunnel fertiggestellt; nur der permanente Service-Start auf MS512 ist offen.*
