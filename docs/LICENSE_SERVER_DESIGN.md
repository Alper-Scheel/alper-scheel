# License-Server — Architektur & Implementierungsplan

> **Produkt:** ALVA-TEXT (später auch ALVA-Plattform)
> **Operativer Träger:** AdLuna GmbH (DE) — öffentlich sichtbar
> **IP-Eigentümer:** AdSerica Ltd. (HK) — im Backend
> **Host:** MS512 (100.101.8.27 via Tailscale; public via Cloudflare Tunnel an `api.adluna.de`)
> **Stand:** 22. April 2026

---

## 1. Zielsetzung

Der License-Server ist die zentrale Steuerungsinstanz für:

1. **Aktivierung:** Ein Endnutzer darf ALVA-TEXT erst nutzen, nachdem er seine Email verifiziert und einen Aktivierungscode in die App eingegeben hat.
2. **Kill-Switch:** Die App prüft täglich gegen den Server, ob ihre Lizenz noch gültig ist. Der Server kann jederzeit einzelne oder alle Clients auf `expired` schalten (z.B. zum Monetarisierungs-Start).
3. **Tracking:** Der Server protokolliert jede Aktivierung (Email, Device-UUID, App-Version, Zeitpunkt), um die Nutzerbasis zu verstehen und Email-Kampagnen zu steuern.
4. **Skalierung:** Derselbe Server bedient später die ALVA-iOS- und ALVA-macOS-Clients mit denselben Primitiven (Registrierung, Check, Device-Management).

---

## 2. Datenmodell (SQLite)

```sql
CREATE TABLE users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    email           TEXT NOT NULL UNIQUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verified_at     TIMESTAMP,                        -- NULL bis Code eingegeben
    allowlist_flag  INTEGER DEFAULT 0,                -- 1 = immer aktiv (Early-Adopter)
    paid_flag       INTEGER DEFAULT 0,                -- 1 = hat bezahlt (Paddle-Webhook)
    max_devices     INTEGER DEFAULT 2                 -- Gerätelimit pro Email
);

CREATE TABLE activation_codes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    code            TEXT NOT NULL,                    -- 6-stelliger Einmal-Code
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at      TIMESTAMP NOT NULL,               -- +15 Minuten
    used_at         TIMESTAMP                         -- NULL bis eingelöst
);

CREATE TABLE devices (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    device_uuid     TEXT NOT NULL UNIQUE,             -- macOS Hardware-UUID
    device_name     TEXT,                             -- z.B. "Alper's MacBook Pro"
    product         TEXT NOT NULL,                    -- 'alva-text', später 'alva-macos', 'alva-ios'
    app_version     TEXT,
    activated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_check_at   TIMESTAMP,
    last_ip         TEXT,
    token           TEXT NOT NULL UNIQUE,             -- Server-Token nach Aktivierung
    revoked         INTEGER DEFAULT 0
);

CREATE TABLE license_status_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       INTEGER REFERENCES devices(id),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status          TEXT,                             -- 'beta', 'active', 'expired', 'invalid'
    tier            TEXT                              -- 'full', 'trial', 'paid'
);
```

**Keine Passwort-Speicherung.** Der Auth-Flow läuft über Einmal-Codes an die echte Email-Inbox. Das ist sicherer, DSGVO-armer und für Endnutzer bequemer.

---

## 3. API-Endpunkte (FastAPI)

### POST `/v1/activation/request`
**Body:** `{ email: string, device_uuid: string, device_name: string, product: string, app_version: string }`

Flow:
1. Email-Regex-Check.
2. User-Entry finden oder neu erstellen.
3. 6-stelligen Code generieren (kryptographisch zufällig), 15-Minuten-Gültigkeit, in `activation_codes` speichern.
4. Email an `users.email` mit Code-Text senden (via SMTP an ms512 oder über Mailgun/Resend).
5. Rate-Limit: max 3 Code-Anfragen pro Email pro Stunde.
6. Response: `{ ok: true, message: "Code per Email verschickt" }`.

### POST `/v1/activation/verify`
**Body:** `{ email: string, code: string, device_uuid: string }`

Flow:
1. Code gegen `activation_codes` prüfen (Email matcht, nicht abgelaufen, nicht schon eingelöst).
2. Falls User noch nicht verifiziert: `users.verified_at` setzen.
3. Device-Anzahl pro User prüfen — wenn `>= max_devices`, Response `too_many_devices` mit Liste der existierenden Devices zur Deaktivierung.
4. Neuen Device-Eintrag anlegen mit zufälligem Token (64 Byte URL-safe).
5. Code als `used_at = now` markieren.
6. Response: `{ ok: true, token: "...", status: "beta", tier: "full" }`.

### POST `/v1/license/check`
**Header:** `Authorization: Bearer <token>`
**Body:** `{ device_uuid: string, app_version: string }`

Flow:
1. Token in `devices.token` suchen, `device_uuid` matchen, `revoked = 0`.
2. `last_check_at = now`, `app_version` updaten, `last_ip` loggen.
3. User-Status prüfen: `paid_flag` ODER `allowlist_flag` ODER (globaler Beta-Modus an) → `status = active/beta`.
4. Sonst → `status = expired`, App zeigt Paywall.
5. Log-Eintrag in `license_status_log`.
6. Response: `{ status: "beta|active|expired", tier: "full|paid|trial", message: "...", check_again_in: 86400 }`.

### POST `/v1/device/revoke`
Manuell vom Admin-Dashboard (oder User „Dieses Gerät entfernen"-Button). Setzt `revoked=1`, App verliert beim nächsten Check Zugriff.

### POST `/v1/webhook/paddle` *(später)*
Paddle-Webhook bei erfolgreicher Zahlung: `users.paid_flag = 1` für die angegebene Email, Mail mit Bestätigung.

### GET `/v1/admin/stats` *(intern)*
Dashboard: Anzahl User total, aktive Devices, Checks pro Tag, Top-Länder, aktuelle Beta-Mode-Einstellung.

---

## 4. Globale Konfiguration (Kill-Switch)

Eine einzelne `config.yaml` oder DB-Tabelle `server_config`:

```yaml
beta_mode: true                # false = Kill-Switch aktiv, nur paid_flag/allowlist_flag zählen
beta_cutoff_date: null         # Datum, ab dem Neuregistrierungen nicht mehr beta sind
paddle_enabled: false          # Paywall-Screen zeigen ja/nein
message_of_the_day: null       # optionale Server-Push-Nachricht an alle Clients
```

**Kill-Switch-Ablauf in der Praxis:**
1. Du setzt `beta_mode: false` und `beta_cutoff_date: 2026-07-01`.
2. Alle Devices mit `activated_at < 2026-07-01` ODER `allowlist_flag=1` ODER `paid_flag=1` → `status=active`.
3. Alle neueren Devices ohne `paid_flag` → `status=expired`.
4. App zeigt Paywall, weist auf Kauf-Link via Paddle hin.

---

## 5. Client-Seite (ALVA-TEXT)

### Beim ersten App-Start (keine Aktivierung vorhanden):

1. **Welcome-Screen:** „Bitte gib deine Email ein. Du bekommst einen 6-stelligen Code zur Aktivierung."
2. **Email-Eingabe → POST `/activation/request`.**
3. **Code-Eingabe-Screen:** „Wir haben dir einen Code geschickt. Bitte prüfe deinen Posteingang."
4. **Code eingeben → POST `/activation/verify`.**
5. Server-Token in **macOS Keychain** speichern (Service: `com.adserica.alvatext.license`).
6. App schaltet frei, zeigt die normale UI.

### Bei jedem App-Start (Aktivierung vorhanden):

1. Token aus Keychain lesen.
2. POST `/license/check` mit Token + Device-UUID.
3. Response auswerten:
   - `active` oder `beta` → App läuft normal.
   - `expired` → Paywall-Screen: „Deine Testphase ist abgelaufen. Einmal-Kauf für €20 bei Paddle."
   - `invalid` (Token nicht mehr gültig, z.B. revoked) → Aktivierung-Screen neu.
4. Falls Server nicht erreichbar: letzten gültigen Status aus Keychain cachen, 14 Tage Grace-Period.
5. Nach 14 Tagen offline: App geht in Read-Only-Modus mit Popup „Bitte einmal online für Lizenz-Check".

### Zusätzlich einmal alle 24h:

Im Hintergrund ein `/license/check`. Wenn der Server mittlerweile den Kill-Switch umgelegt hat, bekommt die App das innerhalb eines Tages mit.

---

## 6. Email-Versand

**Option A (sofort, simpel):** SMTP via **Mailgun** (kostenlos bis 5.000 Mails/Monat) oder **Resend** (kostenlos bis 3.000/Monat). Nur transactional Mails, keine Newsletter.

**Option B (später, eigenständig):** MS512 eigener Mail-Server — aber SPF/DKIM/DMARC-Konfiguration ist Arbeit, und Mails aus Heim-Anschlüssen landen oft im Spam.

**Empfehlung für Start: Mailgun oder Resend,** `support@adluna.de` als Absender. Domain-Verification (SPF/DKIM) einmalig einrichten.

**Mail-Template für Aktivierungscode:**
```
Betreff: Dein ALVA-TEXT Aktivierungscode

Hi!

Dein Aktivierungscode für ALVA-TEXT lautet:

    ABC123

Der Code ist 15 Minuten gültig. Einfach in der App eingeben
und loslegen.

Fragen? Schreib uns: support@adluna.de

Viele Grüße
AdLuna GmbH
```

---

## 7. Infrastruktur-Setup

### MS512-Deployment

1. **FastAPI-Service** unter `~/services/alva-license/`:
   - `main.py` (die 6 Endpunkte)
   - `database.py` (SQLAlchemy)
   - `emailer.py` (Mailgun/Resend-Client)
   - `config.py` (Beta-Mode Flags)
   - `alembic/` (Migrations)
2. **Running via `uvicorn`** unter systemd-Service oder Docker.
3. **Port 8080 intern**, per Cloudflare Tunnel auf `api.adluna.de` public exposed.
4. **SQLite-DB** unter `~/services/alva-license/license.db` — tägliches Backup auf NAS.

### Monitoring

- **Uptime-Check** via UptimeRobot oder selbstgehostetes Prometheus.
- **Error-Logging** via Loguru → `~/services/alva-license/logs/`.
- **Wöchentlicher Report** per Mail an dich: Anzahl Neuregistrierungen, aktive Devices, Fehler-Count.

### Sicherheit

- Alle Endpunkte nur über HTTPS (Cloudflare Tunnel macht das automatisch).
- Tokens sind 64-Byte URL-safe Strings, keine reversiblen JWT mit Secrets im Client.
- Rate-Limits pro Email und pro IP (z.B. via slowapi).
- DB-Backup täglich auf NAS, verschlüsselt.
- **KEIN Passwort**, keine sensiblen User-Daten außer Email → DSGVO-Footprint minimal.

---

## 8. DSGVO-Kurzeinschätzung

**Gespeicherte Daten pro User:**
- Email (PII)
- Device-UUID (Pseudonym)
- Device-Name (evtl. PII, wenn User-benannt — wird optional gemacht)
- IP-Adresse (PII)
- Zeitstempel

**Verarbeitungszwecke:**
- Technische Authentifizierung (Art. 6 Abs. 1 lit. b DSGVO — Vertrag)
- Lizenzverwaltung (lit. b)
- Versand transactional Mails (lit. b)

**Keine** Newsletter, keine Tracking-Cookies, kein Profiling. Deshalb:
- **Kein Datenschutzbeauftragter erforderlich** (AdLuna GmbH wird weniger als 20 Personen dauerhaft damit beschäftigen).
- **Standard-Datenschutzerklärung** auf `adluna.de/datenschutz` reicht — ich liefere Muster.
- **Lösch-Recht:** User kann jederzeit `support@adluna.de` schreiben → wir löschen Email + alle Devices. Admin-Endpoint `DELETE /v1/admin/user/{email}` dafür einbauen.

---

## 9. AI-Act-Kurzeinschätzung

Der License-Server ist **keine KI-Komponente** — nur Auth/Lizenzverwaltung. ALVA-TEXT selbst nutzt Whisper-Transkription + GPT-4o-mini für Rewrite. Beides läuft als **„limited risk AI"** im AI-Act-Sinne (Art. 50 Transparenzpflicht):

- **Pflicht:** Nutzer muss erkennen können, dass KI eingesetzt wird.
- **Erfüllung:** Onboarding-Screen + Settings-Eintrag „ALVA nutzt KI-basierte Transkription (OpenAI Whisper) und Textbearbeitung (OpenAI GPT-4o-mini)."
- **Dokumentationspflicht:** leichtgewichtig — keine Conformity Assessment, keine CE-Kennzeichnung.

**Voraussichtliche Einstufung:** ALVA-TEXT ist weder High-Risk (Anhang III), noch Prohibited (Art. 5), noch GPAI-System. → Compliance mit Standard-Transparenzhinweisen erfüllt.

Langfristig, wenn ALVA-Hauptprodukt mit LoRA-Nachttraining auf User-Daten läuft, wird die AI-Act-Einstufung komplexer — das gehört dann in die ALVA-Doku, nicht die ALVA-TEXT-Doku.

---

## 10. Implementierungs-Reihenfolge

**Phase A — MVP-Lizenz-Server (1 Woche, 8–12 h Arbeit):**
1. FastAPI-Skelett auf MS512, `/activation/request` + `/activation/verify` + `/license/check`.
2. SQLite-Schema, Alembic-Migrations.
3. Mailgun-Integration, Aktivierungscode-Mail.
4. Cloudflare Tunnel auf `api.adluna.de`.

**Phase B — ALVA-TEXT Client-Integration (3–5 h):**
1. SwiftUI-Onboarding erweitern: Email-Screen + Code-Screen.
2. `LicenseClient.swift`, Keychain-Token-Store.
3. Täglicher Background-Check.
4. Paywall-Screen (ausgeblendet bis Kill-Switch).

**Phase C — Admin-Dashboard (2–3 h):**
Minimal: eine geschützte HTML-Seite auf `api.adluna.de/admin` mit Tabelle aller User + Devices + Buttons „Revoke", „Force-Activate".

**Phase D — Paddle-Integration (wenn monetarisiert wird, 2–3 h):**
Webhook-Endpunkt, User als `paid_flag=1` markieren, Bestätigungsmail.

---

## 11. Kosten-Abschätzung

| Posten | Kosten | Frequenz |
|---|---|---|
| MS512 (vorhanden) | 0 € | — |
| Cloudflare Tunnel | 0 € | — |
| Mailgun bis 5k/Monat | 0 € | monatlich |
| Domain `adluna.de` | ~12 €/Jahr | jährlich |
| Paddle (wenn aktiv) | 5 % + 0,50 € | pro Transaktion |
| Steuerberater HK-Struktur | 1.500–3.000 € | einmalig |

Bis zur Monetarisierung: **laufende Kosten nahe null**. Nach Monetarisierung: klassische SaaS-Unit-Economics.

---

*Dokument gepflegt unter `docs/LICENSE_SERVER_DESIGN.md`. Letzter Stand: 22. April 2026, 17:00.*
