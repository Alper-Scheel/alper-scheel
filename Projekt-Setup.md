# Projekt-Setup — Regelwerk für neue & bestehende Projekte

> **Zweck:** Kondensiertes Engineering-Playbook. Alles, was wir uns
> in der Praxis schmerzhaft erarbeitet haben, in einer Datei. Liegt
> als `Projekt-Setup.md` im Root jedes Projekts und wird **vor jeder
> Session als erstes gelesen** — sowohl von Claude als auch vom User.
>
> **Stand:** 2026-04-29 · Version 1.0

---

## 0 · Das Eine Prinzip

> **Strukturieren statt eilen. Lieber eine Stunde vorbereiten als
> zehn Stunden reparieren.**

Jeder einzelne der Bugs, an denen wir uns heute zermürbt haben, war
vermeidbar — wenn wir uns an ein paar simple Regeln gehalten hätten.
Diese Datei ist die Sammlung dieser Regeln.

---

## 1 · Git-Hygiene (Pflicht von Tag 1)

**Beim Projekt-Start:**

- [ ] `git init` + `git remote add origin git@github.com:...`
- [ ] `.gitignore` korrekt aufsetzen (xcuserdata, DerivedData, .env, /build)
- [ ] Erstes commit + push (auch wenn nur README + .gitignore)
- [ ] Branch-Strategie festlegen — empfohlen: `main`, `dev`, `feature/*`, `hotfix/*`

**Vor jedem Refactor / größerem Edit:**

- [ ] Tag auf den letzten funktionierenden Stand: `git tag vX.Y.Z`
- [ ] Tag pushen: `git push origin --tags`
- [ ] Lokales Bundle als Defense-in-Depth: `git bundle create ~/Desktop/projekt-backup-$(date +%Y%m%d).bundle --all`
- [ ] Bundle auf NAS / Cold-Storage ziehen

**Niemals:**

- ❌ Major-Code committen ohne Tag auf den vorherigen funktionierenden Stand
- ❌ Working-Tree mit unkommittetem Mix aus mehreren Versionen lassen
- ❌ Releases ohne entsprechenden Git-Tag (Tag muss existieren bevor das DMG/Binary auf GitHub Release liegt)

**Tag-Konvention:** Strict semver mit `v`-Präfix, z.B. `v2.1.3`.
Hotfixes mit Patch-Bump. Major-Bump nur bei breaking changes für End-User.

---

## 2 · Refactor-Disziplin

**Die wichtigste Regel:** **EIN Edit, EIN Build, EIN Test.**

- ❌ Nie mehrere Bug-Fixes in einem Build mischen
- ❌ Nie eine Architektur-Änderung mit einem Bug-Fix kombinieren
- ❌ Nie auf einem Build aufsetzen, der noch nicht End-to-End getestet wurde

**Stattdessen:**

1. EINE Code-Änderung machen
2. Bauen
3. Installieren beim User (signiert, Release-Build)
4. End-to-End testen
5. Wenn grün: nächster Edit
6. Wenn rot: Rollback zum letzten Tag

**Big-Bang-Refactor ist Tod.** Wir hatten heute (2026-04-29) einen
sauberen v2.1.3-Stand und haben innerhalb von 6h fünf parallele
Refaktor-Schritte gemacht. Ergebnis: nichts funktionierte mehr.

---

## 3 · Build- & Distribution-Pipeline

**Beim Projekt-Setup:**

- [ ] Xcode-Scheme als „Shared" anlegen (`xcshareddata/xcschemes/*.xcscheme`)
  → sonst sieht `xcodebuild` das Scheme nicht in CI/Skripten
- [ ] Code-Signing-Identity dokumentieren (welche Developer-ID, welcher Team-Identifier)
- [ ] Notarization-Profile in Keychain anlegen (`xcrun notarytool store-credentials`)
- [ ] DMG-Build-Skript anlegen (`create-dmg` oder `hdiutil`-basiert)
- [ ] BUILD.md mit exakten Schritten — kopierbare Befehle

**Bei jedem Release:**

- [ ] Version in `Info.plist` UND `project.pbxproj` (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
- [ ] Tag setzen UND pushen vor Release-Erstellung
- [ ] CHANGELOG.md mit Bullet-Points was sich geändert hat
- [ ] Notarisierter & gestapelter Build → DMG → GitHub Release

**Niemals:**

- ❌ Debug-Builds (ad-hoc-signiert) für Tester verteilen
- ❌ Verschiedene Code-Signaturen für die gleiche Bundle-ID (erzeugt mehrere TCC-Einträge auf macOS)
- ❌ DMG ohne `xcrun stapler staple` ausliefern

---

## 4 · macOS-spezifisch — TCC & Permissions

**Goldene Regel:** Permission-Prompts NIE beim App-Start. IMMER im
Kontext eines Onboarding-Schritts mit Erklärung, ausgelöst durch
expliziten User-Klick.

**Beim App-Start:**

- ❌ Kein `AXIsProcessTrustedWithOptions(prompt:true)` automatisch
- ❌ Kein `IOHIDRequestAccess` ohne UserDefaults-Flag-Check
- ✅ Nur stille Status-Reads, kein Dialog-Trigger

**Im Onboarding-Step:**

- Erklärung warum die Permission gebraucht wird
- Button "Erlaubnis erteilen" → der ruft den Prompt aus
- 5-Sek-Cooldown auf den Prompt-Aufruf (verhindert Klick-Spam)
- Status-Polling alle 2-3 Sek, aber: kein Auto-Restart bei Wechsel

**Wenn macOS' TCC-Cache pro-Prozess nicht synct (bekannter macOS-Bug):**

- ❌ Kein App-Side-Auto-Restart als Workaround (erzeugt Endlos-Loop)
- ✅ User-sichtbarer Banner: „Bitte App einmal manuell beenden und neu öffnen"

**Mehrere TCC-Listeneinträge nach Build-Wechsel (Debug → Release etc.):**

- macOS bindet Einträge an `cdhash` (Code-Signatur-Hash)
- `tccutil reset` löscht nur den Approval-Status, nicht den Listen-Eintrag
- Manueller Cleanup nötig: jeden Eintrag in Systemeinstellungen mit `−` entfernen
- **Vermeiden** durch konsistente Code-Signatur (immer Release-Build mit Developer-ID)

---

## 5 · Server / Backend (FastAPI o.ä.)

**Beim Setup:**

- [ ] `.env.example` ins Repo, `.env` in `.gitignore`
- [ ] `ADMIN_TOKEN` mit hoher Entropie (`openssl rand -base64 48`)
- [ ] Admin-Endpoints von Anfang an: `/admin/users`, `/admin/user/{email}` (GET + DELETE)
- [ ] Health-Check-Endpoint: `/healthz`
- [ ] Cloudflare Tunnel oder gleichwertiges für stabile Domain

**Bei jedem License/Activation-Service:**

- Device-Limit pro User dokumentieren (z.B. 3)
- Force-Revoke-Endpoint einbauen (`POST /activation/revoke-others`) — verhindert die "Limit erreicht, Tester gesperrt"-Falle
- Rate-Limit-Header korrekt setzen, damit Client „Try again in X seconds" anzeigen kann
- DSGVO-Cascade-Delete (User → Devices → Codes → Checks)

**Niemals:**

- ❌ Admin-Token im Repo committen
- ❌ Server ohne Admin-Endpoint deployen (sonst Notfall-DB-Eingriff nötig)
- ❌ Device-Limit ohne UX-Pfad zum Lösen (Tester wird sonst frustriert)

---

## 6 · License-Gating in der Client-App

**Architektur:**

- License-State als ObservableObject mit `phase: needsActivation | active | expired | revoked | error | loading`
- `phase.isUsable: Bool` — bei `.loading` IMMER `false` (sicherer Default, kein Race)
- License-Gate an JEDEM Entry-Point der Hauptfunktionalität (Hotkey-Handler, Cloud-Calls, etc.)
- UI-Anzeige reicht NICHT — App-Logik muss aktiv blocken

**Beim Aktivierungs-Flow:**

- Aktivierung als Pflicht-Schritt im Onboarding (nicht als separates Sheet)
- „Weiter" disabled solange `phase != .active`
- Bei 409 (Device-Limit): „Andere Geräte abmelden"-Button mit Force-Revoke-Call

---

## 7 · Web-Distribution (Cloudflare Pages)

**Beim Domain-Setup:**

- [ ] Sowohl `domain.de` als auch `www.domain.de` als Custom Domains einrichten
- [ ] Redirect-Rule `www → root` (301), saubere Canonical-URL
- [ ] DNS-Verifikation: `dig +short www.domain.de` muss auf Cloudflare-IPs zeigen
- [ ] HTTP→HTTPS-Redirect aktiv

**Bei jedem Deploy:**

- [ ] `_redirects` und `_headers` korrekt
- [ ] Smoke-Test über alle Pages (curl / Browser)
- [ ] Falls Bot-Fight-Mode aktiv: User-Browser-IP nicht durch eigene Tests bombardieren (sonst 403)

---

## 8 · Pflicht-Dokumentation pro Projekt

Diese Dateien gehören in jedes Projekt im Repo-Root:

- `README.md` — was es ist, Quickstart, Architektur in 1 Bild
- `BUILD.md` — exakte Build-Schritte, kopierbar
- `DEPLOY.md` — exakte Deploy-Schritte, kopierbar
- `CHANGELOG.md` — Versions-History mit Bullet-Points
- `_BUGS_AND_LEARNINGS.md` — Bug-Tracker + Lessons + Recovery-Block
- `Projekt-Setup.md` — diese Datei (Kopie aus dem Master)

**Recovery-Block** ist der wichtigste Teil von `_BUGS_AND_LEARNINGS.md`:
ganz oben, mit Branch-Stand, Tag-Stand, was läuft, wo der Server liegt,
welche Skripte was machen. Damit jede Session-Wiederaufnahme sofort weiß,
wo es weitergeht.

---

## 9 · Session-Continuity (Claude / AI-Assistent)

**Damit Memory zwischen Sessions erhalten bleibt:**

- `_BUGS_AND_LEARNINGS.md` ist der primäre Persistenz-Speicher
- Bei jeder Session: erst diese Datei lesen, dann arbeiten
- Wichtige Entscheidungen IMMER in die Datei eintragen (nicht nur in den Chat)
- Bei Session-Ende: Recovery-Block aktualisieren

**Im Brain-Vault eintragen:**

```markdown
## Active Projects
- ALVA-TEXT — Bug-Tracker: ~/codex-work/alper-scheel/ALVA-TEXT/_BUGS_AND_LEARNINGS.md
- AdMed — Bug-Tracker: ~/codex-work/admed/_BUGS_AND_LEARNINGS.md
- ...
```

So findet Claude beim Session-Start automatisch alle aktiven Projekt-
Trackers über das Brain-CLAUDE.md.

---

## 10 · Distribution / Tester-Workflow

**Bei jedem Tester-Onboarding:**

- Begleit-Mail mit:
  - Download-Link
  - Quickstart in 3 Schritten
  - Erwartete Permissions (was macOS fragen wird, warum)
  - Console.app-Anleitung für Bug-Reports (Filter, Screenshot)
  - Dein Reply-Pfad (Mail/Telegram/Whatsapp)

**Server-Side vorbereiten:**

- [ ] Tester-Email in Database whitelisten / freischalten
- [ ] Device-Slot-Limit großzügig (mindestens 5 für jeden Tester wegen Re-Installs)
- [ ] Admin-Reset-Skript für „User klickt mehrfach Install" griffbereit

**Niemals:**

- ❌ Debug-Build an Tester
- ❌ Tester ohne Aktivierungs-Code-Email-Whitelist
- ❌ Erst-Tester ohne persönliche Anleitung — Setup-Probleme verlierst du sonst beim ersten Frustrations-Moment

---

## 11 · Quick-Start für ein neues Projekt

```bash
# 1. Repo + Git
mkdir myproject && cd myproject
git init
echo "# myproject" > README.md

# 2. Pflicht-Dokumente
cp ~/codex-work/alper-scheel/Projekt-Setup.md .
touch BUILD.md DEPLOY.md CHANGELOG.md _BUGS_AND_LEARNINGS.md

# 3. .gitignore (sprach-/framework-spezifisch)
curl -s https://www.toptal.com/developers/gitignore/api/macos,xcode,swift > .gitignore

# 4. Erst-Commit + Remote
git add -A
git commit -m "Initial commit: project scaffold + setup docs"
git remote add origin git@github.com:USERNAME/myproject.git
git push -u origin main
git tag v0.0.0
git push origin --tags

# 5. _BUGS_AND_LEARNINGS.md mit Recovery-Block initialisieren
# 6. Brain-CLAUDE.md eintragen unter Active Projects
```

---

## 12 · Checkliste: „Bin ich bereit, Code zu ändern?"

Vor jeder Code-Änderung — egal wie klein:

- [ ] Branch sauber? (`git status`)
- [ ] Letzter funktionierender Stand getaggt?
- [ ] Backup gemacht (Bundle / GitHub-Push)?
- [ ] `_BUGS_AND_LEARNINGS.md` gelesen?
- [ ] Klar, was genau ich ändere und warum?
- [ ] Klar, wie ich den Erfolg teste?
- [ ] Bereit, bei Test-Failure auf den Tag zu rollen?

Wenn EINE Antwort „nein" — STOP. Erst die Vorarbeit, dann der Edit.

---

## Versionierung dieser Datei

| Version | Datum | Änderungen |
|---|---|---|
| 1.0 | 2026-04-29 | Initiale Fassung — gedreht aus den Lessons des ALVA-TEXT-Tages |

---

> **Diese Datei ist lebendig.** Jede neue Erkenntnis aus jedem
> Projekt fließt hier rein. Lieber zehnmal hier eintragen als einmal
> gegen denselben Stein laufen.
