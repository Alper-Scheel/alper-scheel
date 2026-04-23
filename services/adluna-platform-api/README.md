# AdLuna Platform API

Multi-Tenant License & Activation Service für alle AdLuna-Produkte
(ALVA-TEXT, künftig: ALVA macOS Full, ALVA iOS, …).

Betrieb: MS512 (macOS, launchd) hinter Cloudflare Tunnel →
`https://api.adluna.de`. Daten: SQLite (WAL) lokal; Upgrade auf Postgres
ist ohne Code-Änderung möglich (`Settings.db_url`).

---

## Architektur

```
ALVA-TEXT (macOS App)
      │  POST /v1/activation/request   → E-Mail mit 6-stelligem Code
      │  POST /v1/activation/verify    → Device-Token (Keychain)
      │  POST /v1/license/check        → täglich, liefert status/tier
      ▼
Cloudflare Tunnel (api.adluna.de)
      ▼
FastAPI (MS512, :8080)
      ▼
SQLite (data/license.db, WAL-Mode)
      │
      └── Resend API (mail.adluna.de)
```

Entscheidungs-Hierarchie im Server (`_resolve_status`):

1. License `revoked` → **revoked / limited**
2. `beta_mode_global=true` → **beta / full** (Kill-Switch für alle)
3. License `active` + `tier=paid` → **active / paid**
4. License `trial` + nicht abgelaufen → **trial / full**
5. sonst → **expired / limited**

---

## Projektstruktur

```
services/adluna-platform-api/
├── app/
│   ├── __init__.py          Version
│   ├── main.py              FastAPI-Entrypoint + Router
│   ├── config.py            Pydantic Settings (.env)
│   ├── database.py          Engine + Session + WAL
│   ├── models.py            SQLAlchemy: Product/User/Device/License/...
│   ├── schemas.py           Pydantic-Request/Response-Modelle
│   ├── auth.py              Token-Gen + Bearer-Auth-Dependencies
│   ├── emailer.py           Resend-Integration
│   └── endpoints/
│       ├── activation.py    /v1/activation/*
│       ├── license.py       /v1/license/check, /v1/device/*
│       ├── webhook.py       /v1/webhook/paddle (Stub)
│       └── admin.py         /v1/admin/* (Admin-Bearer)
├── alembic/                 Schema-Migrations
│   ├── env.py
│   ├── script.py.mako
│   └── versions/
│       └── 20260423_0001_initial_schema.py
├── alembic.ini
├── seed.py                  ALVA-TEXT als erstes Product eintragen
├── Dockerfile               Multi-Stage (builder → runtime, user adluna)
├── docker-compose.yml       nur für lokales Dev-Testing
├── requirements.txt
├── .env.example             Template für neue Deployments
└── .env                     SECRETS (gitignored)
```

## Endpoints

| Methode | Pfad | Auth | Zweck |
|---|---|---|---|
| `POST` | `/v1/activation/request` | – | 6-stelligen Code per E-Mail senden |
| `POST` | `/v1/activation/verify`  | – | Code einlösen, Device-Token liefern |
| `POST` | `/v1/license/check`      | Bearer (Device) | Täglicher Status-Check |
| `POST` | `/v1/device/list`        | Bearer (Device) | Alle Geräte des Users sehen |
| `POST` | `/v1/device/revoke`      | Bearer (Device) | Fremd-Device widerrufen |
| `POST` | `/v1/webhook/paddle`     | HMAC (Phase 2) | Zahlung eingegangen |
| `GET`  | `/v1/admin/stats`        | Bearer (Admin)  | Überblick |
| `GET`  | `/v1/admin/users`        | Bearer (Admin)  | Liste aller Nutzer |
| `GET`  | `/v1/admin/user/{email}` | Bearer (Admin)  | Details zu einem Nutzer |
| `DELETE` | `/v1/admin/user/{email}` | Bearer (Admin) | DSGVO-Löschung |
| `GET`  | `/` / `/health`          | – | Uptime-Check |

---

## Lokale Entwicklung

```bash
cd services/adluna-platform-api
cp .env.example .env          # dann RESEND_API_KEY + ADLUNA_ADMIN_TOKEN eintragen
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
python -m seed
uvicorn app.main:app --reload --host 127.0.0.1 --port 8080
```

Admin-Token für `.env` erzeugen:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Smoke-Test:

```bash
curl -s http://127.0.0.1:8080/health | jq
curl -s -X POST http://127.0.0.1:8080/v1/activation/request \
  -H 'content-type: application/json' \
  -d '{"email":"test@example.com","product":"alva-text","device_uuid":"11111111-1111-1111-1111-111111111111"}'
```

---

## Deployment auf MS512

Einmalig:

1. Python 3.12 + `uv` installieren (`brew install uv`)
2. `cloudflared` installieren + mit `api.adluna.de → http://127.0.0.1:8080` verdrahten
3. `~/Library/LaunchAgents/de.adluna.platform-api.plist` anlegen
   (Template am Ende von `docs/deploy-platform-api.sh`)
4. `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.adluna.platform-api.plist`
5. `.env` auf MS512 anlegen (NICHT aus Repo syncen — wird explizit ausgeschlossen)

Jedes Release:

```bash
bash docs/deploy-platform-api.sh          # → rsync + alembic + seed + restart
bash docs/deploy-platform-api.sh --dry    # Trockenlauf
bash docs/deploy-platform-api.sh --logs   # tailt nach Deploy
```

---

## Secrets

Niemals ins Repo! Pfade:

- **Lokal:** `services/adluna-platform-api/.env` (gitignored)
- **Produktion:** `ms512:/Users/ms512/services/adluna-platform-api/.env`

Inhalt:

```
RESEND_API_KEY=re_xxx_xxx
ADLUNA_ADMIN_TOKEN=<48-byte urlsafe>
LICENSE_SERVER_ENV=production
```

---

## Nächste Schritte

Phase 1 (aktuell):

- [x] FastAPI-Skelett + Endpoints
- [x] Alembic-Migrations
- [x] Dockerfile + Compose
- [x] Deploy-Skript
- [ ] `.env` auf MS512 anlegen + Admin-Token generieren
- [ ] launchd-Service + cloudflared-Config
- [ ] Swift `LicenseClient.swift` in ALVA-TEXT
- [ ] End-to-End-Test mit echtem Mail-Versand via Resend

Phase 2 (Monetarisierung):

- [ ] Paddle-Webhook (HMAC-Verifikation + `status=paid` setzen)
- [ ] Checkout-Integration in ALVA-TEXT (System-Browser öffnet Paddle)
- [ ] Bestätigungsmail + License-Token-Update pushen

Phase 3 (Multi-Tenant):

- [ ] `alva-macos` als zweites Produkt
- [ ] Admin-Dashboard (separate Web-App, nutzt `/v1/admin/*`)
- [ ] PostgreSQL-Migration bei steigender Last
