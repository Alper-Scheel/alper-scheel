# AdLuna Platform API — Architektur & Implementierungsplan

> **Produkt:** Multi-Tenant-Lizenz- und Aktivierungsdienst für sämtliche AdLuna-Produkte (ALVA-TEXT, später ALVA-macOS, ALVA-Voice, weitere).
> **Operativer Träger:** AdLuna GmbH (DE) — öffentlich sichtbar
> **IP-Eigentümer:** AdSerica Ltd. (HK) — im Backend
> **Host:** MS512 (100.101.8.27 via Tailscale; public via Cloudflare Tunnel an `api.adluna.de`)
> **Stand:** 22. April 2026 (v2 — Multi-Tenant)

---

## 1. Warum Multi-Tenant von Tag eins

Der License-Server wird von Anfang an als **Plattform-API** gebaut, nicht als Einzelprodukt-Server. Begründung:

- **ALVA-TEXT ist nur der erste Tenant.** Das Ökosystem um ALVA wird mehrere Apple-Clients haben (ALVA-macOS, ALVA-Voice-iOS, evtl. ALVA-Watch) sowie perspektivisch weitere Standalone-Tools aus der AdLuna-Werkbank.
- **Eine Infrastruktur, n Produkte.** Ein einziger FastAPI-Dienst, ein Datenmodell, ein Deployment, ein Monitoring. Jedes weitere Produkt ist nur ein neuer Eintrag in der `products`-Tabelle — kein zusätzlicher Server nötig.
- **Cross-Product-Nutzer.** Ein Nutzer mit Email `alper@example.com` kann ALVA-TEXT bezahlt haben, gleichzeitig ALVA-Voice-Beta nutzen und später ALVA-macOS dazukaufen. Ein Konto, mehrere Lizenzen.
- **Strategischer Hebel für Paddle-Integration.** Wenn später Paddle-Produkte angelegt werden, zeigt jedes auf `product_id` im License-Server. Cross-Sell und Upgrade-Pfade trivial umsetzbar.

Der Mehraufwand gegenüber Single-Tenant ist minimal — eine zusätzliche Tabelle (`products`), ein `product`-Parameter in den Endpunkten, eine Product-ID im Device-Eintrag. Der langfristige Hebel ist enorm.

---

## 2. Datenmodell (SQLite, später bei Skalierung → PostgreSQL)

```sql
-- Produkte (wird beim Deployment mit Seed-Daten gefüllt)
CREATE TABLE products (
    id              TEXT PRIMARY KEY,              -- 'alva-text', 'alva-macos', 'alva-voice-ios'
    name            TEXT NOT NULL,                 -- Nutzer-sichtbarer Name
    slug            TEXT NOT NULL UNIQUE,          -- URL-safe, z.B. für /products/alva-text
    default_trial_days INTEGER DEFAULT 14,
    paddle_product_id TEXT,                        -- Paddle-Produkt-ID für Paywall
    price_eur       DECIMAL(10,2),                 -- Brutto-Einmalpreis
    active          INTEGER DEFAULT 1,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Nutzer (eindeutig über Email)
CREATE TABLE users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    email           TEXT NOT NULL UNIQUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verified_at     TIMESTAMP,                     -- NULL bis erster Code eingelöst
    notes           TEXT                           -- interne Notizen (Admin)
);

-- Aktivierungscodes (Einmal-Einträge, kurzlebig)
CREATE TABLE activation_codes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id      TEXT NOT NULL REFERENCES products(id),
    code            TEXT NOT NULL,                 -- 6-stellig, kryptographisch zufällig
    device_uuid     TEXT NOT NULL,                 -- an das konkrete Gerät gebunden
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at      TIMESTAMP NOT NULL,            -- typisch +15 Minuten
    used_at         TIMESTAMP,                     -- NULL bis eingelöst
    ip_address      TEXT
);

-- Devices (pro Nutzer × Produkt eindeutig)
CREATE TABLE devices (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id      TEXT NOT NULL REFERENCES products(id),
    device_uuid     TEXT NOT NULL,                 -- macOS/iOS Hardware-UUID
    device_name     TEXT,                          -- vom User vergeben
    platform        TEXT,                          -- 'macos', 'ios', 'ipados', ...
    token           TEXT NOT NULL UNIQUE,          -- 64-Byte URL-safe Server-Token
    activated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_check_at   TIMESTAMP,
    last_check_ip   TEXT,
    app_version     TEXT,
    UNIQUE(user_id, product_id, device_uuid)
);

-- Lizenzstatus (pro Device, überschreibbar durch Admin oder Webhook)
CREATE TABLE licenses (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       INTEGER NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'beta',  -- beta|trial|active|expired|revoked
    tier            TEXT NOT NULL DEFAULT 'full',  -- full|limited|paid
    trial_expires_at TIMESTAMP,                     -- Ende Trial-Phase
    paid_at         TIMESTAMP,                     -- gesetzt durch Paddle-Webhook
    revoked_at      TIMESTAMP,
    revoked_reason  TEXT,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Check-Log (für Monitoring, debugging, Audit)
CREATE TABLE license_checks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       INTEGER REFERENCES devices(id) ON DELETE SET NULL,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status_returned TEXT,
    ip_address      TEXT,
    app_version     TEXT
);

-- Server-Konfiguration (Kill-Switch-Logik)
CREATE TABLE server_config (
    key             TEXT PRIMARY KEY,
    value           TEXT,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Initial:
-- ('beta_mode_global', 'true')
-- ('allowlist_cutoff_date', '2026-11-01')   -- Datum, bis zu dem Registrierungen Beta bleiben
```

**Design-Entscheidungen:**

- **Keine Passwörter.** Authentifizierung erfolgt über Einmal-Codes an die bestätigte Email-Inbox.
- **Eine Email pro User, mehrere Devices pro Produkt.** Ein User kann ALVA-TEXT auf 2–3 Geräten aktivieren.
- **`licenses.status` + `tier` trennen.** `status=beta,tier=full` = Beta-Tester mit vollem Funktionsumfang. `status=active,tier=paid` = bezahlt. `status=expired,tier=limited` = Paywall-Modus.
- **`server_config`-Tabelle** als globaler Kill-Switch — einfacher zu ändern als YAML-Config auf der Disk.

---

## 3. API-Endpunkte (FastAPI)

Alle Endpunkte unter `/v1/`. Versionierung im URL-Pfad, damit zukünftige Breaking Changes ohne Client-Brüche möglich sind.

### POST `/v1/activation/request`

**Body:** `{ email, product, device_uuid, device_name?, platform, app_version }`

1. Email-Format validieren
2. Produkt in `products` suchen, 404 wenn nicht existiert/inaktiv
3. User anlegen oder finden
4. Rate-Limit: max 3 Code-Anfragen pro (Email, Produkt) in 60 Minuten
5. 6-stelligen Code generieren, 15-min Gültigkeit, speichern
6. Email mit Code an `users.email` senden (Produkt-Name erwähnt)
7. Response: `{ ok: true, message: "Code verschickt" }`

### POST `/v1/activation/verify`

**Body:** `{ email, product, code, device_uuid }`

1. Code nachschlagen, auf (email, product, device_uuid) matchen, Gültigkeit prüfen
2. `users.verified_at` setzen (falls noch nicht verifiziert)
3. Device-Limit für (user, product) prüfen — Default max 3, konfigurierbar pro Produkt
4. Device-Eintrag anlegen, 64-Byte URL-safe Token generieren
5. License-Eintrag anlegen mit Initial-Status = `beta`/`full` (oder aus globaler Config ableitbar)
6. Code als `used_at = now` markieren
7. Response: `{ ok: true, token, status, tier, message }`

### POST `/v1/license/check`

**Header:** `Authorization: Bearer <token>`
**Body:** `{ product, device_uuid, app_version? }`

1. Token in `devices.token` lookup, `device_uuid` + `product_id` müssen matchen
2. `last_check_at`, `last_check_ip`, `app_version` aktualisieren
3. Kill-Switch-Logik auswerten:
   - wenn `licenses.status = revoked` → respond `revoked`
   - wenn `licenses.status = paid` → respond `active, paid`
   - wenn `users.id` auf Allowlist ODER `server_config.beta_mode_global = true` → respond `beta, full`
   - wenn `licenses.status = trial` und `trial_expires_at > now` → respond `trial, full`
   - sonst → respond `expired, limited`
4. Log-Eintrag in `license_checks`
5. Response: `{ status, tier, message, check_again_in: 86400 }`

### POST `/v1/device/list`

**Header:** Bearer-Auth
**Body:** `{ email, product }`

Liefert dem Nutzer seine eigenen Devices für ein Produkt, damit er in der App Geräte verwalten/abmelden kann.

### POST `/v1/device/revoke`

**Header:** Bearer-Auth (User-Token oder Admin-Token)
**Body:** `{ device_uuid, product }`

Markiert `licenses.status = revoked`, Token wird invalid.

### POST `/v1/webhook/paddle`

**Header:** Paddle-Signature
**Body:** Paddle-Event-Payload

1. Signatur mit Paddle-Secret verifizieren (wichtig, sonst kann jeder „bezahlt" faken)
2. Event `transaction.completed` auswerten: Email aus Paddle-Daten, Produkt über Paddle-Produkt-ID mappen
3. `licenses.status = paid`, `tier = paid`, `paid_at = now` für alle Devices des Users bei dem Produkt
4. Bestätigungsmail senden

### GET `/v1/admin/*` (Protected)

Admin-Endpunkte hinter separatem Admin-Token (aus ENV-Variable, nicht Email-basiert):

- `GET /v1/admin/users?product=alva-text` — Nutzerliste pro Produkt
- `GET /v1/admin/user/{email}` — alle Details eines Nutzers
- `POST /v1/admin/user/{email}/allowlist` — Permanent-Allowlist setzen
- `DELETE /v1/admin/user/{email}` — DSGVO-Löschung

---

## 4. Konfiguration und Kill-Switch

**Global** (eine `server_config`-Tabelle, pro Key-Value):

| Key | Wert | Wirkung |
|---|---|---|
| `beta_mode_global` | `true` / `false` | Wenn `true`: alle Devices antworten mit `status=beta, tier=full`, egal was in `licenses` steht. Komplett offen für Beta-Phase. |
| `allowlist_cutoff_date` | ISO-Datum | Alle `devices.activated_at < cutoff` bleiben auf Allowlist, auch wenn `beta_mode_global = false`. Schützt Bestands-Beta-Tester. |
| `require_paid` | product-id oder `*` | Für welche Produkte ist Paywall aktiv? |

**Typischer Phasen-Flow:**

1. **Beta-Phase:** `beta_mode_global = true`. Alle Nutzer „beta, full". Kein Paywall.
2. **Kill-Switch-Tag:** `beta_mode_global = false`, `allowlist_cutoff_date = <heute>`, `require_paid = alva-text`. Bestandstester bleiben auf Allowlist, Neuregistrierungen brauchen nach 14-Tage-Trial Paddle-Zahlung.
3. **Vollmonetarisierung:** jedes Produkt pro `require_paid` einzeln steuerbar.

---

## 5. Client-Integration (ALVA-TEXT erster Tenant)

### First-Run-Flow

1. App ist gerade installiert, Keychain leer.
2. Onboarding-Screen „Willkommen bei ALVA-TEXT".
3. Email-Screen: „Bitte gib deine Email ein. Wir schicken dir einen Aktivierungscode."
4. `POST /v1/activation/request` → Email rausgegangen.
5. Code-Screen: „Wir haben dir einen 6-stelligen Code geschickt. Einfach eingeben."
6. `POST /v1/activation/verify` → Token kommt zurück.
7. Token in Keychain (Service: `com.adserica.alvatext`, Account: `licenseToken`).
8. App schaltet frei → normale UI.

### Daily-Check

1. App-Start: Token aus Keychain lesen.
2. Letzter Status aus Keychain cachen (14 Tage Grace-Period).
3. Background-Task alle 24 h: `POST /v1/license/check`.
4. Response auswerten: `active|beta|trial` → App läuft, `expired` → Paywall-Screen, `revoked` → Aktivierung neu starten.
5. Bei Netzwerk-Fehler: letzter gecachter Status wird weiter genutzt, bis Grace-Period abläuft.

### Multi-Produkt-Ready

Der gleiche `LicenseClient.swift` in der App ist wiederverwendbar für künftige Produkte. Der Produkt-Identifier `"alva-text"` ist eine einzige Konstante, die im späteren ALVA-macOS zu `"alva-macos"` wird.

---

## 6. Email-Versand

**Provider für Phase 1–2: Mailgun** (alternativ Resend — vergleichbare Konditionen).

- AdLuna GmbH als Account-Inhaber
- Domain `adluna.de` verifiziert (DKIM + SPF + DMARC) — _das_ ist die Arbeit, keine Shortcuts
- Absender: `support@adluna.de` oder `hello@adluna.de` (beide identisch routet auf dein Postfach)
- Template: einfacher HTML + Plaintext-Mail mit Code und Produkt-Erwähnung

**Einmal-Aufwand DNS:** siehe `docs/ADLUNA_DNS_SETUP.md`.

**Kosten Mailgun Foundation Plan:** 15 USD/Monat für 50.000 Mails, mehr als genug für Aktivierungs- und Transaktions-Mails.

---

## 7. Deployment auf MS512

### Verzeichnisstruktur

```
~/services/adluna-platform-api/
├── app/
│   ├── main.py              FastAPI-Einstiegspunkt
│   ├── models.py            SQLAlchemy-Modelle
│   ├── database.py          DB-Connection, Sessionmaker
│   ├── emailer.py           Mailgun-Client
│   ├── auth.py              Token-Generierung, Bearer-Auth-Dependency
│   ├── schemas.py           Pydantic-Request/Response-Schemas
│   ├── endpoints/
│   │   ├── activation.py    /v1/activation/*
│   │   ├── license.py       /v1/license/*
│   │   ├── device.py        /v1/device/*
│   │   ├── webhook.py       /v1/webhook/*
│   │   └── admin.py         /v1/admin/*
│   └── config.py            Settings aus ENV
├── alembic/                 DB-Migrationen
├── tests/
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

### Prozess-Betrieb

- **systemd-Unit** `adluna-platform-api.service` — Auto-Restart, Logging nach `journald`
- Alternativ: **Docker Compose** für saubere Isolation (bevorzugt)
- **Port 8080** intern, via **Cloudflare Tunnel** an `api.adluna.de` public
- **SQLite-DB** unter `~/services/adluna-platform-api/data/license.db`
- **Tägliches Backup** via cron-Job auf NAS und in MS512-Backup-Verzeichnis

### Monitoring

- **Uptime-Check** auf `api.adluna.de/health` via UptimeRobot (kostenlos bis 50 Monitore)
- **Logs:** `~/services/adluna-platform-api/logs/*.log` via Loguru
- **Daily Digest Mail** an Alper: Zahl Neuregistrierungen, Fehler-Count, Check-Volumen (Cron-Job)
- **Errors:** auf Wunsch Sentry-Integration (Phase 3)

---

## 8. Deployment-Skript

`docs/deploy-platform-api.sh` — überträgt den Code-Ordner auf MS512, installiert Abhängigkeiten, legt systemd-Unit an, startet den Service, führt initiale Migration aus, seedet Produkte (ALVA-TEXT als ersten Eintrag).

Idempotent: kann beliebig oft ausgeführt werden, aktualisiert die Deployment-Version.

---

## 9. DSGVO-Kurzeinschätzung

Unverändert zum Original-Design: minimale PII (Email, Device-UUID, IP), Art. 6 (1) b (Vertragserfüllung) als Rechtsgrundlage, kein DSB erforderlich bei < 20 Personen-Teamgröße. Details: `Brain/02_PROJEKTE/ALVA-TEXT/05-AI_Act_und_DSGVO_Compliance.md`.

---

## 10. AI-Act-Kurzeinschätzung

Der License-Server selbst ist **keine KI-Komponente** — nur Auth-/Lizenzverwaltung. Betrifft weder AI-Act-Pflichten für High-Risk noch für Limited-Risk. Die KI-Transparenz-Pflicht liegt bei den Client-Apps (ALVA-TEXT, künftige). Details: `Brain/02_PROJEKTE/ALVA-TEXT/05-AI_Act_und_DSGVO_Compliance.md`.

---

## 11. Kosten-Abschätzung

| Posten | Kosten | Frequenz |
|---|---|---|
| MS512 (vorhanden) | 0 € | — |
| Cloudflare Tunnel | 0 € | — |
| Domain `adluna.de` | ~12 €/Jahr | jährlich |
| Mailgun Foundation Plan | ~14 €/Monat | monatlich |
| Paddle (wenn aktiv) | 5 % + 0,50 € | pro Transaktion |
| Steuerberater HK-Struktur | 1.500–3.000 € | einmalig |

Bis zur Monetarisierung: **laufende Kosten ca. 15 €/Monat**, einmalige Setup-Kosten null.

---

## 12. Implementierungs-Reihenfolge

**Phase A — Core-API (1–2 Tage):**
1. FastAPI-Skelett anlegen (`services/adluna-platform-api/`)
2. Datenmodell + Alembic-Migrations
3. Endpoints implementieren (Activation, License, Webhook-Stub)
4. Admin-Endpunkte minimal

**Phase B — Deployment (0,5 Tag):**
1. systemd-Unit + Docker-Compose auf MS512
2. Cloudflare Tunnel für `api.adluna.de`
3. HTTPS testen

**Phase C — Mailgun (0,5 Tag):**
1. Mailgun-Account auf AdLuna GmbH
2. DNS-Records für `adluna.de` (DKIM, SPF, DMARC) setzen
3. Email-Template-Tests

**Phase D — Client-Integration (1 Tag):**
1. SwiftUI-Aktivierungsscreen in ALVA-TEXT
2. LicenseClient.swift mit URLSession
3. Keychain-Token-Speicher
4. Background-Check-Logic

**Phase E — Test + Release (0,5 Tag):**
1. End-to-End-Test mit eigenem Account
2. Notarisierter Build mit License-Flow
3. Release-Pipeline laufen

**Total: ~4 aktive Arbeitstage. Tester-Release in 1 Woche realistisch.**

---

*Dokument gepflegt unter `docs/LICENSE_SERVER_DESIGN.md`. Letzter Stand: 22. April 2026, v2 Multi-Tenant.*
