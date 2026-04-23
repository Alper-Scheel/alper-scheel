# AdLuna.de — DNS + Cloudflare Tunnel + Mailgun

> **Was hier passiert:** `adluna.de` wird als Plattform-Domain eingerichtet mit öffentlichem Zugang auf MS512 (für `api.adluna.de` und `downloads.adluna.de`) sowie mit einer verifizierten Mail-Sender-Konfiguration für `support@adluna.de` und Transaktions-Mails.
>
> **Zeitaufwand:** 1,5–2 Stunden aktive Klickerei. Propagations-Wartezeit (DNS) zusätzlich 1–24 h je nach Registrar.
> **Wer macht was:** Die DNS-seitigen Änderungen macht Alper im Admin-Panel. Die MS512-seitige Tunnel-Konfiguration kann CC übernehmen, sobald Cloudflare-Account steht.

---

## Voraussetzungen (bitte vorab klären)

| Punkt | Alpers Check |
|---|---|
| Wo ist `adluna.de` registriert? (IONOS, Strato, Cloudflare, Namecheap, etc.) | _Bitte eintragen:_ |
| Haben wir Admin-Zugang zum DNS-Management? | ja/nein |
| Besteht schon ein Cloudflare-Account? | ja/nein |
| Besteht schon ein Mailgun-Account auf AdLuna GmbH? | ja/nein |

Falls Cloudflare und Mailgun noch nicht existieren: im Setup unten wird erklärt, wie sie angelegt werden.

---

## Schritt 1 — Cloudflare-Account + Domain-Transfer (DNS-Management)

Dies ist der kritische erste Schritt. Wir verschieben das DNS-Management zu Cloudflare, weil wir Cloudflare Tunnel für die öffentliche Exposition von MS512 brauchen und weil Cloudflare ein sehr gutes (kostenloses) DNS-Interface bietet.

### 1.1 Cloudflare-Account anlegen (falls noch nicht vorhanden)

1. `https://dash.cloudflare.com/sign-up` → Alpers AdLuna-Email-Adresse nehmen (z.B. `alper@adluna.de` falls schon eingerichtet, sonst persönliche Mail und später umziehen)
2. Passwort setzen, Email verifizieren
3. **Plan:** Free — reicht absolut für unseren Use Case

### 1.2 adluna.de bei Cloudflare hinzufügen

1. Cloudflare-Dashboard → `+ Add a Site`
2. Domain: `adluna.de`, Plan: Free → Confirm
3. Cloudflare liest die aktuellen DNS-Einträge bei deinem bisherigen Registrar aus — prüfen, ob alle wichtigen Einträge (MX, vorhandene A/CNAME für Web) übernommen wurden
4. Cloudflare gibt dir zwei **Nameserver-Namen** (z.B. `greg.ns.cloudflare.com`, `lily.ns.cloudflare.com`) — **notieren**

### 1.3 Nameserver beim Registrar umstellen

Beim Registrar von adluna.de (IONOS/Strato/etc.):
- Login ins Domain-Admin-Panel
- adluna.de-Verwaltung → **Nameserver ändern** (oder „DNS-Server" / „NS-Records")
- Auf „eigene Nameserver" / „externe Nameserver" umstellen
- Die beiden Cloudflare-Nameserver eintragen
- Speichern

**Wartezeit:** 1–24 h, bis die Registry weltweit propagiert. Während dieser Zeit kann adluna.de kurzzeitig nicht erreichbar sein — das ist für uns akzeptabel, weil die Domain aktuell noch keine produktive Landing-Page bedient.

### 1.4 Cloudflare-Aktivierung prüfen

Im Cloudflare-Dashboard oben rechts: Domain-Status muss von `Pending Nameserver Update` auf `Active` wechseln. Das bestätigt, dass DNS-Management jetzt bei Cloudflare liegt.

---

## Schritt 2 — Cloudflare Tunnel für `api.adluna.de` und `downloads.adluna.de`

Zweck: MS512 läuft hinter Alpers Heim-Firewall ohne öffentliche IP. Cloudflare Tunnel ist ein kostenloser Reverse-Proxy, der einen verschlüsselten Tunnel zwischen MS512 und Cloudflare's Edge-Netz aufspannt. Öffentliche User erreichen `api.adluna.de` → Cloudflare Edge → Tunnel → MS512 lokal auf Port 8080.

### 2.1 Cloudflare Zero Trust aktivieren

1. Cloudflare-Dashboard → **Zero Trust** (im linken Menü, ggf. erst aktivieren — kostenlos bis 50 Nutzer)
2. Team-Name vergeben: `adluna` (oder ähnlich)
3. Plan: Free

### 2.2 Tunnel erstellen

1. Zero Trust Dashboard → **Access** → **Tunnels** → `Create a tunnel`
2. **Cloudflared** als Connector wählen
3. Tunnel-Name: `ms512-adluna-platform`
4. Cloudflare zeigt dir einen **Installations-Befehl** für das Zielgerät (MS512). Dieser Befehl enthält ein Token — den merken, wir brauchen ihn auf MS512.

### 2.3 Tunnel auf MS512 installieren

**Das macht CC für dich** auf MS512 — kopiert den Installations-Befehl von Cloudflare in eine SSH-Session und startet `cloudflared` als systemd-Service. Er braucht dafür nur das Tunnel-Token, das Cloudflare beim Create-Prozess ausgibt.

**Was du machst:** kopiere das Token aus dem Cloudflare-Dashboard und schick es CC als separate Nachricht (oder trage es in `ZUGANGSDATEN.md` ein, CC kann dort lesen).

### 2.4 Hostnames für Tunnel konfigurieren

Im Cloudflare-Dashboard → Tunnel `ms512-adluna-platform` → **Public Hostnames** → `Add a public hostname`:

**Eintrag 1 — API:**
- Subdomain: `api`
- Domain: `adluna.de`
- Type: `HTTP`
- URL: `localhost:8080`
- (Dies ist der Port des FastAPI-Dienstes auf MS512)

**Eintrag 2 — Downloads:**
- Subdomain: `downloads`
- Domain: `adluna.de`
- Type: `HTTP`
- URL: `localhost:8081`
- (Dies ist der Port eines späteren Caddy/Nginx-Dienstes, der `~/storage/alva-text/current/` serviert. Port 8081 reservieren wir schon jetzt, Service kommt später.)

Speichern → Cloudflare legt automatisch die nötigen CNAME-Einträge in der DNS-Zone an.

### 2.5 Verifikation

Von einem beliebigen Client (auch dein Mac via Browser):

- `https://api.adluna.de/` → sollte jetzt auf MS512's FastAPI-Dienst antworten (sobald der läuft)
- `https://downloads.adluna.de/` → 503 zunächst (Service existiert noch nicht) — sobald Caddy läuft, funktioniert es

Cloudflare liefert automatisch HTTPS-Zertifikate, kein manuelles Let's-Encrypt-Management nötig.

---

## Schritt 3 — Mailgun-Account + Domain-Verifikation

### 3.1 Mailgun-Account auf AdLuna GmbH

1. `https://app.mailgun.com/mg/dashboard/` → Sign up
2. **Business-Info**: AdLuna GmbH, Alpers Adresse, USt-ID
3. Plan: **Foundation** (15 USD/Monat, 50.000 Mails) — reicht für die Beta und die ersten tausend Paying-Users locker
4. Kreditkarte hinterlegen (AdLuna-Firmen-Karte, wenn vorhanden, sonst temporär persönlich)

### 3.2 Domain hinzufügen

1. Mailgun-Dashboard → **Domains** → `Add New Domain`
2. Domain: `mg.adluna.de` (Sub-Domain für Mail, nicht die Haupt-Domain — Standard-Praxis)
3. Region: EU (Frankfurt, wegen DSGVO)
4. Mailgun zeigt dir eine Liste von **DNS-Records**, die du in Cloudflare setzen musst:

### 3.3 DNS-Records in Cloudflare setzen

Mailgun gibt typischerweise diese 5 Records aus:

| Typ | Name | Wert | Zweck |
|---|---|---|---|
| TXT | `mg.adluna.de` | `v=spf1 include:mailgun.org ~all` | SPF — welche Server dürfen im Namen senden |
| TXT | `s1._domainkey.mg.adluna.de` | (langer Mailgun-Key) | DKIM — Signatur-Schlüssel |
| MX | `mg.adluna.de` | `mxa.eu.mailgun.org` (prio 10), `mxb.eu.mailgun.org` (prio 10) | MX — Mail-Empfang |
| CNAME | `email.mg.adluna.de` | `mailgun.org` | Tracking-Unterstützung |
| TXT | `_dmarc.mg.adluna.de` | `v=DMARC1; p=quarantine; rua=mailto:admin@adluna.de` | DMARC-Policy |

Alle fünf in **Cloudflare DNS** → `+ Add record` eintragen. **Proxy-Status:** bei DNS-Records „DNS only" (graue Wolke), nicht orange, sonst laufen Mails nicht.

Mailgun prüft alle 5 Minuten automatisch die Records. Sobald alle grün sind, ist die Domain verifiziert (~15 Minuten bis 2 Stunden je nach DNS-Propagation).

### 3.4 API-Key sichern

Mailgun-Dashboard → Settings → **API Keys** → Private API Key kopieren → **in `_SYSTEM/ZUGANGSDATEN.md`** eintragen. CC liest den Key dort für die Server-Konfiguration.

### 3.5 Absender einrichten

Mailgun-Dashboard → Domain `mg.adluna.de` → **Authorized Recipients / Senders** → neuen Absender `support@adluna.de`, `hello@adluna.de`, `no-reply@mg.adluna.de` erlauben.

### 3.6 Support-Email-Forwarding (optional, nützlich)

Wenn jemand an `support@adluna.de` schreibt, willst du das auf dein persönliches Postfach weiterleiten. Cloudflare bietet das kostenlos via **Email Routing**:

1. Cloudflare → adluna.de → **Email → Email Routing**
2. `Enable Email Routing`
3. Cloudflare fügt automatische MX-Records für die **Hauptdomain** hinzu (nicht mit mg.adluna.de verwechseln)
4. **Custom Address:** `support@adluna.de` → **Destination:** `alper.scheel@gmail.com`
5. Ziel-Email verifizieren (Cloudflare schickt Bestätigungs-Link)

Ab dem Moment landen Mails an `support@adluna.de` in deinem Gmail.

**Achtung:** `mg.adluna.de` (Mailgun) und `adluna.de` (Cloudflare Email Routing) sind zwei verschiedene Mail-Domains. Das ist Absicht — Mailgun macht Outbound-Transaktions-Mails, Cloudflare Routing macht Inbound-Forwarding. Keine Kollision.

---

## Schritt 4 — Apex-Domain + Landing-Page (optional für Phase 1)

Für die minimale Landing-Page `adluna.de/alva-text` (später):

- Entweder **Cloudflare Pages** (Free-Tier, statisches Hosting aus GitHub-Repo)
- Oder ein Caddy auf MS512, gleicher Tunnel, auf der Apex-Domain

Das kommt in einer späteren Iteration. Für die erste Tester-Runde (eigene Freunde und Familie) brauchen wir die Landing-Page nicht — wir verschicken Download-Links direkt per Mail.

---

## Checkliste — was du jetzt konkret machen musst

- [ ] **Cloudflare-Account anlegen** (10 Min, falls noch nicht vorhanden)
- [ ] **adluna.de bei Cloudflare hinzufügen**, Nameserver beim Registrar umstellen (15 Min + Warten)
- [ ] **Cloudflare Zero Trust aktivieren** (5 Min)
- [ ] **Cloudflare Tunnel erstellen**, Token an CC schicken (10 Min)
- [ ] **Public Hostnames für api + downloads konfigurieren** (5 Min)
- [ ] **Mailgun-Account auf AdLuna GmbH** (15 Min + Business-Verifikation)
- [ ] **Mailgun-Domain `mg.adluna.de` anlegen**, DNS-Records in Cloudflare einfügen (20 Min)
- [ ] **Mailgun-API-Key in ZUGANGSDATEN.md** speichern (2 Min)
- [ ] **Cloudflare Email Routing für support@adluna.de** (5 Min)

**Summe: ~1,5 Std. Deine Aktiv-Zeit + Warteperioden.**

Sobald alle Punkte durch sind, kann CC den FastAPI-Dienst auf MS512 deployen, und wir können den Aktivierungs-Flow Ende-zu-Ende testen (Code per Email kommt an, App akzeptiert den Code, Server lässt die App frei).

---

## Anhang — Credentials-Inventar

Nach Abschluss hast du folgende Zugänge, die in `_SYSTEM/ZUGANGSDATEN.md` zusammengeführt werden sollten:

- Cloudflare-Login (Email + Passwort + 2FA)
- Cloudflare API-Token (für zukünftige automatisierte DNS-Updates; Token-Erstellung in Account → API Tokens → Create Token)
- Mailgun-Login
- Mailgun-API-Key (Private)
- Cloudflare Tunnel-Token (einmalig, bei Tunnel-Erstellung angezeigt — oder später neu generierbar)

Alle in ZUGANGSDATEN.md pflegen, damit CC und Cowork bei Infrastruktur-Operationen konsistent zugreifen können.

---

*Dokument: `docs/ADLUNA_DNS_SETUP.md`. Letzter Stand: 22. April 2026.*
