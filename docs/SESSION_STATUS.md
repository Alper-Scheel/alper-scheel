# ALVA-TEXT — Session-Status & Übergabe

> **Stand:** 22. April 2026, Abend-Session (Komprimierung).
> **Branch:** `alva-fixes-live`
> **Zweck dieses Dokuments:** Nahtlose Übergabe zwischen Cowork-Sessions.
> Bei Session-Start in neuer Konversation: dieses Dokument + `README.md` +
> `docs/PHASE_4_APP_STORE.md` + `docs/PHASE_5_LOCAL_WHISPER.md` lesen, dann
> weitermachen.

---

## 1. Kurzüberblick

ALVA-TEXT ist eine macOS-Menu-Bar-App für KI-gestütztes Diktieren:
drei Modi (Standard / Höflich / Nachricht), dynamisch zuweisbare
Sprach-Hotkeys via F-Tasten (Übersetzung in 25 Sprachen), und eine
Rückwärtsübersetzung für markierten Fremdtext. Animiertes Status-Icon,
Verlaufsfenster mit Kosten-Tracking, Autostart beim Login,
First-Run-Onboarding, Permission-Auto-Polling.

**Transkriptions-Backend** ist umschaltbar:
- **Lokal** (Default, kein Key nötig): WhisperKit + `openai_whisper-small`
- **Cloud** (API-Key nötig): OpenAI Whisper
- **Auto**: lokal bevorzugt, Cloud als Fallback

**Rewrite/Translate** läuft immer über OpenAI `gpt-4o-mini` (API-Key
optional — ohne Key sind Höflich/Nachricht/Übersetzung deaktiviert).
Englische Übersetzung läuft **lokal via Whisper-Translate-Task**, wenn
der lokale Backend aktiv ist (keine Cloud-Kosten).

---

## 2. Architektur (Quelltexte)

Alle Dateien unter `ALVA-TEXT/ALVA_TEXT/`:

| Datei | Zeilen | Rolle |
|---|---:|---|
| `ALVA_TEXTApp.swift` | 14 | SwiftUI-App-Einstiegspunkt; minimaler `Settings {}`-Scene-Stub |
| `AppDelegate.swift` | 44 | `applicationDidFinishLaunching` — Setzt `.accessory` Policy, fordert Permissions, startet Status-Menu, öffnet Onboarding beim ersten Start, killt alte Dev-Build-Instanzen (`terminateOlderInstances`) |
| `AppCoordinator.swift` | 1232 | **Kernzustand** der App — `@MainActor ObservableObject`. Enthält: Modi-State, Aufnahme-Pipeline, Hotkey-Config, `languageBindings`, History-Persistenz, Error-State, Onboarding/Settings/History/ReverseTranslate-Window-Controller (alle mit Activation-Policy-Trick für Accessory-Apps), Launch-at-Login, **Permission-Auto-Polling** alle 2s (`AXIsProcessTrusted`, `IOHIDCheckAccess`), **CGEventTap Auto-Reinstall** nach Permission-Grant, **API-Kosten-Tracking** pro Call |
| `HotkeyManager.swift` | 653 | Event-Monitoring. `NSEvent.flagsChanged` (global+local) für Modifier-Combos. **CGEventTap** (`.cgSessionEventTap`, `.listenOnly`) für `.keyDown` — erkennt F-Tasten während Aufnahme + Reverse-Translate-Hotkey. Enthält: `HotkeyConfig`, `HotkeyMode`-Delegate, `LanguageBinding`, `LanguageCatalog` (25 Sprachen + Chunk-Detection via `NLLanguageRecognizer`), `TriggerKeyCatalog`, `fKeyNumber(forKeyCode:)`, `reinstallEventTapIfNeeded()` |
| `AudioRecorder.swift` | 44 | `AVAudioRecorder` → `.m4a` in `temporaryDirectory`. Trackt `lastDuration` für Kosten-Tracking |
| `OpenAIService.swift` | 241 | Whisper-Multipart-Upload, `rewriteToPoliteGerman`, `rewriteAsAdaptiveMessage` (mit detailliertem System-Prompt), `translateText(to:)`, generische `chatCompletion`-Helper. Alle Chat-Methoden liefern `OpenAIChatResult { text, usage }` für Token-Tracking |
| `LocalWhisperTranscriber.swift` | 201 | **NEU** — WhisperKit-Wrapper (Swift Package). `openai_whisper-small` (~466 MB), lädt beim ersten Lauf in `~/Library/Application Support/`. Support für Whisper-internen Translate-Task (nur EN). `stripCommonHallucinations()` mit Regex + Phrase-Liste (`[Musik]`, `*seufzt*`, `Vielen Dank`, Untertitel-Stempel, …) |
| `PasteService.swift` | 114 | `simulateCommandV`, `simulateCommandC`, Accessibility-Check, Input-Monitoring-Check via `IOHIDCheckAccess`, Permission-Prompt-Helper |
| `KeychainStore.swift` | 79 | Minimaler Wrapper um `SecItemAdd/Update/Delete` für den OpenAI-API-Schlüssel |
| `StatusMenuController.swift` | 232 | `NSStatusItem` mit animiertem Template-Icon (6-Frame-Recording / 8-Frame-Transcribing). Menu: Einstellungen, Verlauf, Einrichtung, Beenden — **plus dynamische Sprach-Referenz am unteren Ende** (`Fn+F1 → Englisch, …`), rebuilt on `menuWillOpen` |
| `SettingsView.swift` | 1597 | SwiftUI-UI — TabView mit 5 Tabs: Allgemein (Backend + API-Key + Kosten), Modi & Kürzel, Sprachübersetzung, Bedienungshilfen, Status. Enthält auch `OnboardingView`, `HistoryView`, `ReverseTranslatePopup`, `PermissionIntroBanner`, Auto-Stale-Detection für Permissions |
| `Info.plist` | — | macOS 15+, `LSUIElement=true`, `NSMicrophoneUsageDescription`, `NSAccessibilityUsageDescription`, `NSAppleEventsUsageDescription` |
| `ALVA_TEXT.entitlements` | — | **NEU** — Sandbox=false (für TestFlight-Tests), Mic, Network |
| `PrivacyInfo.xcprivacy` | — | **NEU** — Audio-Data-Collection deklariert, kein Tracking |
| `Assets.xcassets/` | — | Idle-Icon, 6 Recording-Frames, 8 Transcribing-Frames, AppIcon |

---

## 3. Feature-Status

Alles fertig und im Branch `alva-fixes-live`:

- ✅ **Chunk 1**: Drei-Modi-Architektur (Standard=⌃, Höflich=⌥, Nachricht=⌘). Settings-Redesign Card-Layout. Adaptiver Chat-Prompt mit Ton-Erkennung (locker / formell).
- ✅ **Chunk 1b**: Toggle-Start/Stop Kollision gefixt. Emoji-/Abkürzungs-Feintuning im Message-Prompt.
- ✅ **Chunk 1c**: Leer-Transcript-Guard. Any-Key-Stop während Toggle.
- ✅ **Chunk 2**: Sprach-Hotkeys via F-Tasten (F1/F2/F3 = EN/FR/IT Default).
- ✅ **Chunk 2b/c/d**: CGEventTap auf `.cgSessionEventTap` / `.listenOnly`. Kantonesisch + Thailändisch. `.function`-Flag aus Modifier-Vergleich raus.
- ✅ **Chunk 3**: Rückwärtsübersetzung mit Popup. Default `⌃⌥Return`, konfigurierbar.
- ✅ **Chunk 3e**: Popup-Redesign mit `NLLanguageRecognizer`-Chunks, Copy-Icons, Lightbox-Look.
- ✅ **Chunk 4**: Autostart (`SMAppService.mainApp`), First-Run-Onboarding (4 Seiten), Verlauf mit Suche (50 Einträge), Fehler-Handling mit deutschen Texten.
- ✅ **Chunk 4a**: UX-Fixes aus Onboarding-Feedback.
- ✅ **Phase 5**: **Lokales Whisper** (WhisperKit) als Default-Backend. Backend-Switch in Settings (Cloud / Lokal / Auto).
- ✅ **Chunk 5a**: Whisper-Halluzinationen weggefiltert (`[Musik]`, `*seufzt*`, `Vielen Dank`, Untertitel-Patterns).
- ✅ **Chunk 5b**: Permission-UX vereinfacht. Auto-Poll alle 2s. Settings-Fenster kommt nach vorne. Input-Monitoring-Dialog-Problem durch "Systemeinstellungen öffnen" umgangen.
- ✅ **Chunk 5c**: API-Kosten-Tracking (Transkription pro Sekunde, Chat pro Token) — im Settings-Tab "Allgemein" sichtbar.
- ✅ **Chunk 5d**: Permission-Intro-Banner + Stale-Detection (auto-expand Hilfe nach 4s ohne Permission-Flip).
- ✅ **Chunk 5e**: CGEventTap reinstalliert sich automatisch, sobald Permissions live gegrantet werden (kein Restart mehr nötig).
- ✅ **Chunk 5f (22.04.)**: Accessory-App-Window-Fix für Reverse-Translate-Popup + History-Window (Activation-Policy-Trick + `.floating` Window-Level + `orderFrontRegardless`).
- ✅ **Chunk 5g (22.04.)**: **Menu-Bar-Dropdown zeigt Sprach-Referenz** am unteren Ende (`Fn+F1 → Englisch, …`), dynamisch per `NSMenuDelegate.menuWillOpen`.

---

## 4. Aktuelle Code-Änderungen (uncommitted)

9 modifizierte Dateien, 5 neue:

```
 M ALVA-TEXT/ALVA_TEXT.xcodeproj/project.pbxproj      (+38 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/AppCoordinator.swift           (+518 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/AppDelegate.swift              (+25 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/AudioRecorder.swift            (+5 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/HotkeyManager.swift            (+49 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/Info.plist                     (+14 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/OpenAIService.swift            (+32 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/SettingsView.swift             (+594 Zeilen)
 M ALVA-TEXT/ALVA_TEXT/StatusMenuController.swift     (+73 Zeilen)

?? ALVA-TEXT/ALVA_TEXT/ALVA_TEXT.entitlements        (neu)
?? ALVA-TEXT/ALVA_TEXT/LocalWhisperTranscriber.swift (neu)
?? ALVA-TEXT/ALVA_TEXT/PrivacyInfo.xcprivacy         (neu)
?? docs/PHASE_4_APP_STORE.md                         (neu)
?? docs/PHASE_5_LOCAL_WHISPER.md                     (neu)
```

**Insgesamt:** 9 changed files, +1175 / −173 Zeilen.

---

## 5. Nächste Schritte

### Phase 4 — App-Store-Ready (höchste Priorität, nächste Session)

- Apple-Developer-Account-Setup validieren
- Bundle-ID in App-Store-Connect registrieren: `com.adserica.alvatext`
  (gehalten von AdSerica Ltd. Hong Kong)
- Entitlements auf Sandbox umstellen (aktuell `sandbox=false` nur für
  TestFlight-Interne-Tests), Device-Audio-Input, Apple-Events
- Hardened Runtime aktivieren
- Code-Signing mit **Developer-ID Application**-Zertifikat
- Erste Archive-Build via Xcode → App-Store-Connect
- TestFlight-Build mit Alper + Family + Marius + Tobias als Testern
- App-Store-Listing: Screenshots, Beschreibung, Kategorie,
  Datenschutzerklärung

Details: siehe `docs/PHASE_4_APP_STORE.md`.

**Realistische Zeit**: 3–5h konzentriert + Review-Wartezeit (1–3 Tage).

### Phase 6 — Lokales Rewrite (optional, später)

- MLX-Swift einbinden
- Llama 3.2 3B (~2 GB) oder Qwen 2.5 3B
- Priorität: Englisch-Übersetzung **bereits lokal via Whisper-Translate**
  (erledigt in Phase 5)
- Rewrite-Modi (Höflich / Nachricht) können Cloud bleiben

### Kleine Polituren

- Reverse-Translate-Popup final testen (Activation-Policy-Fix steht,
  aber noch nicht durch Alper gegen-geprüft).
- Menu-Bar-Sprach-Referenz (heute gebaut) optisch feinjustieren.

---

## 6. Handover-Workflow (diese Session → nächste)

Die Sandbox kann `.git/index.lock` auf dem Mount nicht entfernen — daher
müssen Commit + Push + Backup in **deinem Terminal** laufen. Das Skript
dafür liegt unter `docs/handover.sh` (siehe unten) und macht in einem
Rutsch:

1. Stale Git-Lock entfernen
2. Alles adden (inkl. neuer Dateien, Entitlements, Privacy Manifest)
3. Commit mit Standard-Message
4. Push nach GitHub (`alper-scheel.git`, Branch `alva-fixes-live`)
5. Rsync-Backup nach MS 512 (`ms512@100.101.8.27:~/backups/alper-scheel/`)

**Ausführung:**

```bash
bash ~/codex-work/alper-scheel/docs/handover.sh
```

(Pfad anpassen, falls das Repo woanders liegt.)

---

## 7. Build-Setup & Permissions

**Nach jedem Dev-Rebuild** (nur Xcode `⌘R`, nicht nach Release-Build):

1. Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen**
   → ALVA-TEXT `−` entfernen, `+` neu hinzufügen.
2. Systemeinstellungen → Datenschutz & Sicherheit → **Eingabeüberwachung**
   → ALVA-TEXT `−` entfernen, `+` neu hinzufügen.
3. Nach Input-Monitoring-Änderung: **App beenden und neu starten**.

Diese Choreografie entfällt in Phase 4 mit Developer-ID-Signing.

---

## 8. Default-Konfiguration

| Element | Default |
|---|---|
| Transkriptions-Backend | **Lokal** (WhisperKit) |
| Cloud-Fallback | Auto (wenn lokal fehlschlägt und Key da) |
| Whisper-Modell (lokal) | `openai_whisper-small` (~466 MB) |
| Whisper-Modell (Cloud) | `gpt-4o-mini-transcribe` |
| Umformulierungs-Modell | `gpt-4o-mini` |
| Standard-Hotkey | `⌃` (Control) |
| Höflich-Hotkey | `⌥` (Option) |
| Nachricht-Hotkey | `⌘` (Command) |
| Reverse-Translate-Hotkey | `⌃⌥Return` |
| Doppeldruck-Fenster | 350 ms |
| Mindest-Aufnahmedauer | 400 ms |
| Sprach-Bindings | F1=en, F2=fr, F3=it |
| Autostart | aus |
| History | an (max. 50) |
| Permission-Poll-Intervall | 2 s |

---

## 9. Kontakt & Kontext

- **User**: Alper Scheel (alper.scheel@gmail.com)
- **Repo**: `github.com/Alper-Scheel/alper-scheel`
- **Lokaler Pfad (Mac)**: `~/codex-work/alper-scheel`
- **Mac-Backup-Ziel**: `ms512@100.101.8.27:~/backups/alper-scheel/`
- **Xcode-Projekt**: `ALVA-TEXT/ALVA_TEXT.xcodeproj`
- **Bundle-ID (aktuell)**: `com.adserica.alvatext`
- **Herausgeber / Copyright**: AdSerica Ltd. (Hong Kong)
- **macOS-Target**: 15.0
- **Swift-Version**: 5.0 (Xcode 16)
