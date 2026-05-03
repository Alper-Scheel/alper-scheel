# ALVA-TEXT — Bug-Tracker, Learnings, Recovery-Index

> **Zweck:** Persistenter Wissens-Speicher für die ALVA-TEXT-Entwicklung.
> Wird in Git committet, ist aus jeder Session wieder lesbar — auch nach
> Context-Verlust oder kompletter Session-Wiederaufnahme.
>
> **Erste Anlaufstelle bei Session-Start:** diese Datei lesen, bevor irgendwas
> am Code geändert wird. Dokumentiert offene Bugs, Architektur-Entscheidungen,
> Lessons Learned, und den letzten funktionierenden Stand.

---

## 🔴 Recovery — wenn die Session leer startet

**Repo-Pfad:** `/Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT/`

**Letzter funktionierender Stand (Stand 2026-04-29 abends):**
- `alva-v2.1.2`-Branch + Tag `v2.1.2` = letzter sauber committeter Code
- **v2.1.3-DMG** auf GitHub Releases (signiert, notarisiert) = letzter funktionierender Distribution-Build, läuft sauber bei Testern
- `feat/v2.2-foundation`-Branch = WIP für v2.2 (Mode-Wahl, PersonalizationStore, etc.) — nicht installiert
- `alva-v2.1.4`-Branch = WIP-Hotfix-Versuch von 2026-04-29 — **NICHT zum Bauen verwenden ohne Re-Test**, hat funktional Issues (Onboarding-Restrukturierung halbfertig, License-Gates getestet aber TCC-Schleife nicht gefixt)

**Server (api.adluna.de):**
- FastAPI-Service unter `/Users/AdPolis/codex-work/alper-scheel/services/adluna-platform-api/`
- Admin-Token in `services/adluna-platform-api/.env` (Variable `ADLUNA_ADMIN_TOKEN`)
- Public via Cloudflare Tunnel auf `api.adluna.de`
- Admin-Endpoints unter `/v1/admin/*` mit Bearer-Auth
- DELETE `/v1/admin/user/{email}` löscht User + alle Devices (DSGVO-Cascade)

**Wichtige Skripte im Repo:**
- `_flatline.sh` — komplettes Cleanup auf Mac, kein Build/Install
- `_install-v213-from-github.sh` — DMG laden + installieren (signiert)
- `_revoke-devices.sh` — Server-Side Device-Slots für Mail freiräumen
- `_v22-build.sh` — v2.2-Branch bauen (nicht für Distribution)
- `_v214-clean-install.sh` — v2.1.4-Hotfix bauen (siehe Warnung oben)
- `_rollback-to-v213.sh` — Rollback auf v2.1.3-DMG

---

## 🐛 Offene Bugs

### #B1 — Multiple ALVA-TEXT-Einträge in TCC-Listen ⚠️ HIGH UX

**Symptom:** In macOS-Systemeinstellungen → Datenschutz → Bedienungshilfen
und Eingabeüberwachung erscheinen mehrere ALVA-TEXT-Einträge nebeneinander.
Bei Power-User-Tests heute: bis zu 3 Einträge gleichzeitig.

**Ursache:** macOS bindet TCC-Einträge an `cdhash` (Code-Signatur-Hash).
Jeder Build mit anderer Signatur (Debug ad-hoc, Debug aus DerivedData,
Release Developer-ID-signiert) erzeugt einen eigenen Eintrag, der über
`tccutil reset Accessibility com.adserica.alvatext` NICHT entfernt wird.
`lsregister -kill -r` und Mac-Restart helfen ebenfalls nicht.

**Impact für End-User:** Verwirrend, aber funktional unkritisch — die
aktuell laufende App-Instanz hat genau einen aktiven Eintrag. Bei
Code-Sign-Wechsel zwischen Versionen kommt ein zweiter dazu.

**Fix-Idee für v2.1.5 / v2.2:**
1. Beim Onboarding Schritt „Bedienungshilfen" eine Pre-Check-Page,
   die explizit erkennt wenn mehrere ALVA-Einträge existieren und den
   User explizit auf manuelles `−`-Entfernen hinweist.
2. Erkennung über `sqlite3` lesend gegen `~/Library/Application Support/com.apple.TCC/TCC.db`
   (read-only, mit `system_security`-Permission).
3. Bei Distribution in DMG: nur signierte Release-Builds, keine
   Debug-Builds beim Tester — dadurch kein cdhash-Wechsel.

**Manueller Workaround heute:** User entfernt jeden ALVA-Eintrag manuell
mit `−`-Button in Systemeinstellungen.

---

### #B2 — TCC-Prompt VOR Onboarding-Window ⚠️ HIGH UX

**Symptom:** Beim Erststart kommt der macOS-Bedienungshilfen-Dialog
("ALVA-TEXT.app möchte diesen Computer mit Funktionen der Bedienungshilfe
steuern") **bevor** das ALVA-Onboarding-Window sichtbar ist. User wird
verwirrt, kein Kontext.

**Ursache:** `AppCoordinator.requestPermissions()` (aufgerufen von
`AppDelegate.applicationDidFinishLaunching`) ruft ungebremst
`AXIsProcessTrustedWithOptions(prompt:true)` auf — VOR dem Onboarding.

**Konkrete Code-Stelle:** `ALVA_TEXT/AppCoordinator.swift` Z. 600-602.

**Fix-Idee für v2.1.5:**
- TCC-Prompts NIE beim App-Start triggern.
- Permissions-Anfrage nur im jeweiligen Onboarding-Step, durch
  expliziten User-Klick auf "Erlaubnis erteilen".
- v2.1.4-Branch hatte den Fix bereits skizziert (`alva-v2.1.4`-Branch),
  aber Onboarding-Restrukturierung war halbfertig — komplett re-testen.

**Workaround heute:** User klickt "Systemeinstellungen öffnen" und setzt
Toggle, dann Onboarding manuell durchklicken.

---

### #B3 — License-Bypass: App funktioniert ohne Aktivierung 🔴 CRITICAL

**🔬 Live-Verifikation 2026-04-29 abends:** Frische v2.1.3-DMG-Installation
aus GitHub Release, Onboarding durchgeklickt OHNE den Account-Tab zu öffnen
(kein Aktivierungs-Code, keine Server-Verifikation). Hotkey ⌃ gedrückt,
Satz diktiert → Text landete sauber im Cursor-Kontext. Whisper-Pipeline
und Auto-Paste laufen vollständig ohne Aktivierungs-Check. Bug 100 %
reproduzierbar im Production-DMG.

**Symptom:** Roh-Diktat (`⌃`) und Adaptive-Mode (`⌥+⌃`) funktionieren
in v2.1.3 vollständig OHNE dass der User sich aktiviert hat.

**Ursache:** Kein Guard auf `LicenseState.shared.phase.isUsable` in:
- `AppCoordinator.beginRecording(mode:)` Z. 680
- `AppCoordinator.endRecordingAndProcess()` Z. 715
- `AppCoordinator.startReverseTranslate()` Z. 1211

Plus: `LicenseState.isUsable` gibt im `.loading`-Zustand `true` zurück
(Race-Condition beim App-Start).

**Impact:** Geschäftsmodell-Bug. Beta-Tester können die App ohne
gültigen Code voll nutzen.

**Fix-Status:** Im `alva-v2.1.4`-Branch implementiert (Guards drin,
`.loading → false`), aber Branch nicht released wegen anderer Issues
(siehe #B2, #B6).

**Fix-Idee:** v2.1.4-Code-Anteile in v2.1.5 übernehmen, einzeln testen.

---

### #B4 — Auto-Restart-Loop bei TCC-Cache-Glitch ⚠️ MEDIUM

**Symptom (v2.1.2/v2.1.3):** Wenn macOS' TCC-Cache pro-Prozess das
Trust-Status nicht richtig syncht, triggert `scheduleAutoRestart()`
einen App-Restart. Der frische Prozess sieht AX wieder false → neuer
TCC-Dialog → weiterer Restart. Endlos-Schleife.

**Code-Stelle:** `AppCoordinator.swift` Z. 576-591 (alte v2.1.2-Logik).

**Fix-Status:** v2.1.4 deaktiviert Auto-Restart komplett, zeigt
stattdessen User-Hinweis-Banner. Funktioniert in Theorie, in Praxis
ungetestet wegen anderen Issues.

---

### #B5 — Permission-Prompt-Schleife (Klick-Spam) ⚠️ MEDIUM

**Symptom:** Wenn der User den TCC-Toggle in Systemeinstellungen
setzt, ALVA aber `AXIsProcessTrusted()=false` weiter zeigt
(Cache-Bug), klickt der User aus Frustration mehrfach auf "Erlaubnis
erteilen". Jeder Klick triggert den OS-Dialog erneut.

**Code-Stelle:** `AppCoordinator.requestAccessibilityPrompt()` Z. 1003,
ohne Cooldown.

**Fix-Status:** v2.1.4 hat 5-Sek-Cooldown drin (`lastAccessibilityPromptAt`).

---

### #B6 — openSettings() öffnet zweites Fenster während Onboarding 🔴 HIGH UX

**Symptom (v2.1.3):** Beim Aktivierungs-Flow im Onboarding springt
plötzlich das ALVA-TEXT-Settings-Fenster auf, parallel zum Onboarding.
Drei Fenster gleichzeitig: Onboarding + Settings + Systemeinstellungen.

**Ursache:** `openSettings(initialTab: "account")` wird aufgerufen
(z.B. vom License-Gate, oder von `handlePendingPermissionResume`),
ohne zu prüfen ob das Onboarding-Window schon offen ist.

**Fix-Status:** v2.1.4 hat Guard in `openSettings()` — wenn Onboarding-
Window sichtbar, kein zweites Fenster, sondern Onboarding nach vorn.

---

### #B7 — Sign-off-Bug ✅ FIXED in v2.1.3

**Symptom:** Adaptive-Mode hängte „LG Alper" o.ä. an alle Outputs an,
auch wenn der Nutzer keine Grußformel diktiert hatte.

**Fix:** v2.1.3 OpenAIService.swift — System-Prompt um expliziten
"NIEMALS Namen/Sign-off erfinden"-Block erweitert + `personalization`-
Parameter eingeführt (Stub).

**Status:** Im v2.1.3-DMG live, wirkt.

---

### #B8 — Server-Device-Limit (3) erzeugt 409-Schleife ⚠️ MEDIUM

**Symptom:** Bei mehrfachen Clean-Installs erzeugt jeder Install eine
neue Device-UUID auf api.adluna.de. Nach 3 belegten Slots: HTTP 409
"Device limit reached" beim Aktivierungs-Versuch.

**Workaround:** `_revoke-devices.sh` löscht User-Eintrag auf api.adluna.de
(kaskadiert Devices). Funktioniert.

**Fix-Idee für v2.1.5:**
- App-Side: Bei 409 einen "Andere Geräte abmelden"-Button anzeigen,
  der einen neuen Server-Endpoint `/v1/activation/revoke-others`
  ruft (Auth via aktuellem Code).
- Server-Side: Endpoint einbauen, der für eine Email-Adresse alle
  Devices außer einem aktuellen revoked.

---

### #B9 — www.adluna.de zeigte 404 ✅ FIXED 2026-04-29

**Fix:** Custom Domain `www.adluna.de` zum Cloudflare-Pages-Projekt
`adluna` hinzugefügt + Redirect-Rule www → root angelegt. Verifiziert
mit curl.

---

### #B12 — „Beta-Zugang" / „Status: beta" als sichtbares User-Wording 🟡 MEDIUM UX

**Symptom (gemeldet 2026-04-29 abends):** Im Aktivierungs-Sheet steht
„Beta-Zugang mit deiner E-Mail freischalten." Im Erfolgs-Dialog steht
„Status: **beta** · Tier: **full**". Der User hat festgelegt: Wir sind
nicht mehr Beta, das Wording muss raus.

**Code-Stellen:**
- `ALVA_TEXT/ActivationView.swift` Z. 53: „Beta-Zugang mit deiner E-Mail freischalten."
- `ALVA_TEXT/ActivationView.swift` Z. 119: `Text("Status: **\(status)** · Tier: **\(tier.rawValue)**")`
- Server liefert `status: "beta"` als Aktivierungs-Status zurück.

**Fix-Idee für v2.1.5:**
- Wording-Anpassung im UI: „Vollen Zugang mit deiner E-Mail freischalten"
- Server-side `status`-Wert nicht direkt anzeigen; UI mappt selbst auf
  „Aktiv (voller Funktionsumfang)" o.ä.
- Optional: Server-side `status: "beta"` umbenennen zu `status: "active"`
  → cleanere Semantik.

---

### #B13 — Rote „Server-Antwort 500" im Aktivierungs-Sheet trotz Erfolg 🟡 MEDIUM UX

**Symptom (gemeldet 2026-04-29 abends):** Nach erfolgreicher Aktivierung
zeigt das Activation-Sheet ganz unten in Rot mit Warn-Icon: „Server-Antwort 500".
Der User kann das nicht einordnen — sieht aus wie ein Fehler, obwohl die
Aktivierung erfolgreich war (grünes Häkchen + Voller Funktionsumfang).

**Wahrscheinliche Ursache:** Race-Condition zwischen Aktivierung und
darauffolgendem License-Check. Die `submitCode`-Aktion ist erfolgreich
(verifyActivation 200), aber der Daily-Check (`performDailyCheck` /
`/v1/license/check`) läuft kurz danach im Hintergrund und wirft 500.
Die Fehlermeldung wird dann in die `errorMessage` der ActivationView
geschrieben und unten angezeigt — obwohl die Aktivierung selbst durch ist.

**Code-Stellen:**
- `ALVA_TEXT/ActivationView.swift` Z. 32-40: errorMessage-Anzeige unten
- `ALVA_TEXT/LicenseState.swift` Z. 145-152: Error-Handling bei Background-Check
- Server-Side: `services/adluna-platform-api/app/endpoints/license.py` —
  Warum wirft der License-Check direkt nach Aktivierung 500? Race mit
  noch-nicht-committetem Token? Logs prüfen.

**Fix-Idee für v2.1.5:**
- ActivationView: Wenn `step == .done`, KEINE Error-Message mehr anzeigen.
  Erfolg ist Erfolg.
- LicenseState: Background-Check-Fehler nicht in `phase = .error` schreiben,
  wenn die Phase bereits `.active` ist. Errors aus Background-Checks
  werden schluckend geloggt, der User sieht sie nicht.
- Server-Side: License-Check nach Activation-Verify mit Retry+Delay
  (ggf. 200-500ms warten bis Transaction committed).

---

### #B14 — Keine API-Key-Validierung bei Eingabe 🟡 MEDIUM UX

**Symptom (gemeldet 2026-05-03):** Wenn ein User einen ungültigen
OpenAI-API-Key eingibt (Tippfehler, abgelaufener Key, falsch kopiert),
zeigt die App keinerlei Hinweis. Das Eingabefeld zeigt brav `●●●●●`,
das UI-Feedback ist „Schlüssel gespeichert — alle Features
freigeschaltet." Der User glaubt alles ist OK. Erst beim ersten Cloud-
Call (Polite/Adaptive) failt es silent — Status-Icon „⚠ Fehler" in der
Menübar wird durchschnittlich übersehen, weil es nach 1.2 s wieder
verschwindet. Im Test 2026-05-03 hat der Maintainer selbst eine halbe
Stunde gebraucht, um die Ursache zu finden.

**Code-Stelle:** `ALVA_TEXT/AppCoordinator.swift` `apiKey`-didSet
schreibt nur in den Keychain, ohne den Key zu validieren.
`SettingsView.swift` Allgemein- und Systemfreigaben-Tab zeigt nur
„Schlüssel gespeichert" basierend auf isEmpty.

**Fix-Idee für v2.1.6 / v2.2:**
- Beim Speichern des Keys (didSet) async einen Test-Call gegen
  `GET https://api.openai.com/v1/models` mit dem Key.
- 200 → Status-Indikator „✓ Schlüssel funktioniert"
- 401 → roter Banner „❌ Schlüssel von OpenAI abgelehnt — auf
  platform.openai.com prüfen / neu generieren"
- 429 → gelber Banner „⚠ Rate-Limit — Account-Quota prüfen"
- Netzwerk-Error → grauer Hinweis „⚠ Validierung nicht möglich,
  Schlüssel wurde gespeichert"
- Bonus: „Test ausführen"-Button im Settings-Tab, der den Check
  manuell anstoßen kann.

---

### #B15 — Whisper-Lokal-Performance: lange Latenz bei längeren Texten ❓ OPEN

**Symptom (gemeldet 2026-05-03):** Längere Diktate (mehrere Sätze) im
Roh-Diktat-Modus (Control-Hotkey) brauchen bis zu 30 Sekunden zur
Verarbeitung. Status-Icon dreht sich. Bei kurzen Diktaten ist die
Latenz unter 2 Sekunden. **Regression-Verdacht** — laut Maintainer war
das früher (in einer der ersten v2.1.x-Versionen) deutlich schneller.

**Mögliche Ursachen (zu prüfen):**
1. Transkriptions-Modus aktuell auf „Cloud (OpenAI)" statt „Lokal"?
   Cloud-Whisper kann je nach Netz und OpenAI-Last langsamer sein.
2. Whisper-Small Modell ge-paged statt im RAM (nach längerer Inaktivität)?
3. Metal-Beschleunigung greift nicht zuverlässig (Settings → „Whisper-Small
   geladen / Läuft mit Metal-Beschleunigung" sagt was?)
4. Audio-Chunk-Splitting nicht aktiv → ganze Audiodatei in einem Pass
   transcribiert (linear langsam mit Audio-Länge)
5. Streaming-Inferenz fehlt (Konkurrenten wie MacWhisper streamen während
   der Aufnahme schon)

**Fix-Idee für Untersuchung:**
- Zeit-Logs in `runLocalTranscription` einbauen (start/end + Audio-Dauer)
- Mit verschiedenen Audio-Längen testen (5s, 15s, 60s)
- Vergleich Lokal vs. Cloud-Backend
- Ggf. Whisper-Modell-Variante anpassen (Tiny für schnellere Antworten,
  Medium nur auf User-Wunsch für Qualität)

---

### #B16 — „Prüfen"-Button bei Whisper-Modell ohne Funktion 🟢 LOW UX

**Symptom (gemeldet 2026-05-03):** Im Settings → Allgemein-Tab gibt es
unter „Whisper-Small geladen — Ready" einen „Prüfen"-Button. Klick auf
den Button bewirkt nichts. Plus: bei grünem Haken ist der Button
ohnehin redundant.

**Code-Stelle:** `SettingsView.swift` — Allgemein-Tab, Whisper-Status-
Sektion. Vermutlich `Button(action: { /* TODO */ }) { Text("Prüfen") }`
ohne Implementierung.

**Fix-Idee für v2.1.6:**
- Entweder: Button entfernen, da bei grünem Haken sinnlos.
- Oder: Funktion einbauen — Mini-Inferenz-Test (50 ms Audio, lokales
  Transkript-Tap-Test). Aber overengineered für den UX-Wert.
- Empfehlung: WEG damit.

---

### #B18 — Transkriptions-Modus springt nach Mac-Sleep auf Default zurück ✅ FIXED in v2.1.6 Build 28

**Symptom (gemeldet 2026-05-03):** User stellt Modus manuell auf
„Cloud (OpenAI)" oder „Automatisch", Mac geht in Sleep, beim Wake ist
der Modus zurück auf „Lokal".

**Ursache:** macOS terminiert während Sleep (App Nap / Memory Pressure)
den App-Prozess. Beim Wake wird er neu gestartet. UserDefaults.set ist
asynchron und schreibt erst beim nächsten Sync-Event auf die Disk —
wenn macOS die App vorher terminiert, ist der zuletzt geänderte Wert
weg, der frische Prozess liest den alten oder Default-Wert.

**Fix (v2.1.6 Build 28):**
- `transcriptionBackend.didSet` ruft `UserDefaults.standard.synchronize()`
  → forciert sofortiges Persistieren
- AppDelegate registriert `NSWorkspace.didWakeNotification`-Observer
- Auf Wake: `coordinator.rehydrateUserPreferences()` liest UserDefaults
  frisch und setzt @Published-Properties bei Bedarf neu

---

### #B17 — Auto-Modus erzeugt 15+ Sek Hänger bei Cloud-Latenz ⚠️ HIGH UX

**Symptom (gemeldet 2026-05-03 morgens):** Mit Transkriptions-Modus
„Automatisch (Cloud wenn möglich)" hängt das Status-Icon (Rädchen
dreht endlos) bei manchen Diktaten 20–30 Sekunden, dann erst kommt
der Text. Bei direktem Lokal-Modus passiert das nicht.

**Ursache:** `AppCoordinator.runTranscription` Auto-Branch:
```swift
case .auto:
    if !apiKey.isEmpty {
        do {
            return try await runCloudTranscription(audioURL: audioURL)
        } catch {
            return try await runLocalTranscription(audioURL: audioURL)
        }
    }
```
URLSession-Timeout = 15 Sek (`req.timeoutInterval = 15` in
LicenseClient/OpenAIService). Bei jedem Cloud-Hänger wartet der User
volle 15 Sek auf Timeout, dann nochmal 1–5 Sek für Lokal-Whisper.

**Fix-Ideen für v2.1.6:**
- Cloud-Timeout im Auto-Modus auf 4–5 Sek senken (statt 15).
- Health-Probe vor dem eigentlichen Aufruf: kurz pingen, ob OpenAI
  schnell antwortet. Bei Latenz > 1 Sek direkt zu Lokal switchen.
- Oder: Auto-Mode zur Default-Einstellung machen aber mit klarem
  Latency-Cutoff (z. B. nach 3 Sek Cloud-Versuch hart umschalten auf
  Lokal, kein Bremsklotz mehr).
- Oder pragmatischer: Default-Setting von Auto auf **Lokal** setzen.
  Cloud-Whisper bietet meist nur marginalen Qualitätsgewinn bei
  deutscher Sprache, dafür jede Menge Latenz und Cloud-Kosten.

**Workaround heute:** User stellt manuell auf „Lokal".

---

### #B11 — Onboarding springt auf Schritt 1 nach Permission-Toggle ⚠️ HIGH UX

**Symptom (v2.1.3, gemeldet 2026-04-29 abends):** User durchläuft Onboarding-
Schritt 3 (Bedienungshilfen), klickt „Erlaubnis erteilen", setzt den Toggle
in Systemeinstellungen, schließt das Settings-Fenster — daraufhin startet
das ganze Onboarding-Window von vorne mit „Willkommen bei ALVA-TEXT"
(Schritt 1). Der bisherige Fortschritt ist weg.

**Ursache:** `AppCoordinator.scheduleAutoRestart()` triggert nach erkanntem
Permission-Wechsel einen App-Restart (`open -n bundlePath`). Die neue Instanz
startet mit frischem `OnboardingView`, dessen `@State step = 0` zurück auf
Welcome zeigt. Der vorherige Fortschritt (Schritt 3 erreicht, Toggle gesetzt)
ist State-verloren.

**Code-Stelle:** `AppCoordinator.swift` Z. 576–591 (in v2.1.3) +
Onboarding-State in `SettingsView.swift` (`@State private var step: Int = 0`).

**Impact:** Massiver User-Verlust. Der User denkt, das System ist kaputt.
Nach 2–3 Auto-Restarts gibt der durchschnittliche Tester auf.

**Fix-Status:**
- v2.1.4-Branch hat `scheduleAutoRestart()` zum no-op gemacht und durch
  User-Banner ersetzt.
- Plus: Onboarding-step in UserDefaults persistieren, damit auch bei
  legitimen Restarts der Stand erhalten bleibt.

**Workaround in v2.1.3:** Onboarding einfach nochmal durchklicken — beim
zweiten Durchlauf sind die Toggles bereits gesetzt, „Erneut prüfen" wird
direkt grün, kein zweiter System-Restart nötig.

---

### #B10 — Whisper-Bug bei Beta-Tester (Marius?) ❓ OPEN

**Symptom (gemeldet von Marius):** Hotkey funktioniert (Mikro-Anzeige
+ ALVA-Icon blinkt), aber kein Text in Zwischenablage. ⌘V fügt nur
alten Clipboard-Inhalt ein.

**Status:** Ungeklärt. Vermutlich Whisper-Modell nicht geladen oder
Cloud-Backend ohne API-Key. Console-Logs vom Tester noch nicht da.

**Nächster Schritt:** Tester bitten Console.app → Filter "ALVA" →
Hotkey drücken → Screenshot der Logs schicken.

---

## 📚 Lessons Learned (2026-04-29)

### L1 — Big-Bang-Refactor ist Tod
Heute hatten wir einen sauberen v2.1.3-Stand (signiert, getestet beim
User, läuft). Innerhalb von 6 Stunden habe ich versucht, gleichzeitig:
- License-Gate-Bug zu fixen
- TCC-Schleife zu fixen
- Onboarding komplett zu restrukturieren
- v2.2-Foundation aufzubauen
- Build-Pipeline zu ändern

Ergebnis: nichts funktionierte zuverlässig, der User konnte stundenlang
nicht installieren, der User-Mac war in einem unbenutzbaren Zustand.

**Regel ab jetzt:** EIN Bug-Fix pro Build. Test nach jedem Build.
Nächster Bug-Fix erst nach grünem Test.

### L2 — Vor jedem Refactor: Backup commit + Tag
Ich habe heute v2.1.3 nicht als Tag committed bevor ich angefangen habe
zu refactorn. Der v2.1.3-Code lebte nur als unkommittete Working-Tree-
Änderung + als signiertes DMG auf GitHub. Glücklicherweise hatten wir
das DMG, sonst wäre der funktionierende Stand verloren gewesen.

**Regel ab jetzt:** Vor jedem Refactor:
1. `git tag` setzen auf den letzten funktionierenden Commit
2. `git bundle create` als lokales Backup
3. `git push --tags`

### L3 — Debug-Builds nicht für End-User-Tests
Ich habe heute mehrfach `xcodebuild -configuration Debug` direkt nach
`/Applications` kopiert. Debug-Builds sind ad-hoc-signiert, jede neue
cdhash erzeugt einen weiteren TCC-Eintrag (siehe #B1). Plus: Gatekeeper
behandelt sie anders, manche Permissions hängen an der Signatur.

**Regel ab jetzt:** Tests beim User immer mit signierter Release-Build
über DMG. Debug-Builds nur in Xcode-Run für Developer-Selbsttest.

### L4 — Permission-Prompts immer im Kontext
Ein TCC-Dialog ohne erklärenden Kontext (vorher Onboarding-Step
"Wir brauchen jetzt diese Permission, weil…") ist ein User-Verlust.
Nutzer klickt "Nicht erlauben" → App ist tot.

**Regel:** Permission-Prompts NIE direkt beim App-Start. IMMER nach
einem expliziten User-Klick im Kontext eines Onboarding-Steps.

### L5 — `tccutil reset` ist nicht idempotent in der UI-Liste
`tccutil reset Accessibility com.adserica.alvatext` löscht nur den
Approval-Status, nicht den UI-Listen-Eintrag. Mehrere Einträge können
parallel existieren (siehe #B1). Lösung: manuell mit `−`-Button.

### L6 — Auto-Restart als Workaround für TCC-Cache-Bug ist gefährlich
Apple's TCC-Cache pro-Prozess ist ein bekanntes macOS-Issue. App-Side-
Workaround per Auto-Restart erzeugt aber neue Bugs (Endlos-Loops).
Besser: User-sichtbarer Banner "App bitte einmal manuell neu starten,
falls Toggle nicht erkannt wird".

---

## 📂 Datei-Index (was wo liegt)

```
ALVA-TEXT/
├── ALVA_TEXT/                              # Swift-Quellcode
│   ├── AppCoordinator.swift                # Zentraler State-Hub (1400+ Zeilen)
│   ├── AppDelegate.swift                   # App-Lifecycle, Warm-Up-Tap
│   ├── ALVA_TEXTApp.swift                  # SwiftUI @main entry
│   ├── ActivationView.swift                # Aktivierungs-Sheet (eigenständig)
│   ├── AudioRecorder.swift                 # Mic-Aufnahme
│   ├── HotkeyManager.swift                 # Carbon-Hotkey-Wrapper
│   ├── KeychainStore.swift                 # Generic-Password-Wrapper
│   ├── LicenseClient.swift                 # HTTP-Client für api.adluna.de
│   ├── LicenseState.swift                  # ObservableObject mit phase
│   ├── LocalWhisperTranscriber.swift       # WhisperKit-Adapter
│   ├── OpenAIService.swift                 # Adaptive-Mode + Translate
│   ├── PasteService.swift                  # ⌘V-Simulation + AX-Check
│   ├── SettingsView.swift                  # 6-Tab-Settings + OnboardingView (~2150 Zeilen!)
│   ├── StatusMenuController.swift          # Menübar-Item
│   └── MenuHeaderView.swift                # SwiftUI-Header im Menübar
│
├── _BUGS_AND_LEARNINGS.md                  # ← DIESE DATEI
├── _flatline.sh                            # Mac-Cleanup
├── _install-v213-from-github.sh            # Schritt B: DMG installieren
├── _revoke-devices.sh                      # Schritt A: Server cleanup
├── _v214-clean-install.sh                  # WIP, nicht für Produktion
├── _v22-build.sh                           # v2.2-Foundation Build
├── _rollback-to-v213.sh                    # v2.2 → v2.1.3 Rollback
├── BUILD_v2.2.0-beta1.md                   # v2.2-Build-Anleitung
└── ALVA_TEXT.xcodeproj/                    # Xcode-Projekt
    └── xcshareddata/xcschemes/
        └── ALVA-TEXT.xcscheme              # Shared Scheme (heute angelegt)
```

---

## 🗺️ Nächste Schritte (priorisiert)

1. **v2.1.3-DMG soll der Standard bleiben** für Beta-Tester. Funktioniert.
2. **#B10 (Whisper-Bug Marius)** — Console-Logs einholen, fixen
3. **v2.1.5** — Hotfix-Release mit:
   - License-Gates (aus #B3)
   - TCC-Prompt nur im Onboarding-Step (aus #B2)
   - Cooldown auf Permission-Prompt (aus #B5)
   - openSettings-Guard (aus #B6)
   - "Andere Geräte abmelden"-Button (aus #B8)
   
   **Aber: jeden Punkt einzeln. EIN Edit, ein Build, ein Test, dann nächster.**
4. **v2.2-Foundation** — wenn v2.1.5 stabil ist, in Ruhe weiterbauen
5. **Tester-Mail an die fünf Erstgenannten** — versprochen, noch ausstehend

---

*Letzte Aktualisierung: 2026-04-29 abends.*
