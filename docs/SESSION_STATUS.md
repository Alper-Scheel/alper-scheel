# ALVA-TEXT — Session-Status & Übergabe

> **Stand:** 22. April 2026, Session-Ende.
> **Branch:** `alva-fixes-live`
> **Zweck dieses Dokuments:** Nahtlose Übergabe zwischen Cowork-Sessions.
> Bei Session-Start in neuer Konversation: dieses Dokument + `README.md` +
> `docs/ARCHITECTURE.md` lesen, dann weitermachen.

---

## 1. Kurzüberblick

ALVA-TEXT ist eine macOS-Menu-Bar-App für KI-gestütztes Diktieren:
drei Modi (Standard / Höflich / Nachricht), dynamisch zuweisbare
Sprach-Hotkeys via F-Tasten (Übersetzung in 25 Sprachen), und eine
Rückwärtsübersetzung für markierten Fremdtext. Animiertes Status-Icon,
Verlaufsfenster, Autostart beim Login, First-Run-Onboarding.

Backend heute: **OpenAI** (Whisper für Transkription, GPT-4o-mini für
Umformulierung/Übersetzung). Geplant für Phase 5: **lokales Whisper**
(WhisperKit). Phase 6: **lokales Rewrite/Translate** (MLX + Llama).

---

## 2. Architektur (Quelltexte)

Alle Dateien unter `ALVA-TEXT/ALVA_TEXT/`:

| Datei | Rolle |
|---|---|
| `ALVA_TEXTApp.swift` | SwiftUI-App-Einstiegspunkt; minimaler `Settings {}`-Scene-Stub |
| `AppDelegate.swift` | `applicationDidFinishLaunching` — Setzt `.accessory` Policy, fordert Permissions, startet Status-Menu, öffnet Onboarding beim ersten Start |
| `AppCoordinator.swift` | **Kernzustand** der App — `@MainActor ObservableObject`. Enthält: Modi-State, Aufnahme-Pipeline, Hotkey-Config (Standard/Höflich/Nachricht + Reverse-Translate + Language-Bindings), History-Persistenz, Error-State, Onboarding-/History-Window-Controller, Launch-at-Login via `SMAppService` |
| `HotkeyManager.swift` | Event-Monitoring. `NSEvent.flagsChanged` (global+local) für Modifier-Combos. **CGEventTap** (`.cgSessionEventTap`, `.listenOnly`) für `.keyDown` — erkennt F-Tasten während Aufnahme + Reverse-Translate-Hotkey. Enthält: `HotkeyConfig`, `HotkeyMode`-Delegate, `LanguageBinding`, `LanguageCatalog` (25 Sprachen + Chunk-Detection via `NLLanguageRecognizer`), `TriggerKeyCatalog`, `fKeyNumber(forKeyCode:)` |
| `AudioRecorder.swift` | `AVAudioRecorder` → `.m4a` in `temporaryDirectory` |
| `OpenAIService.swift` | Whisper-Multipart-Upload, `rewriteToPoliteGerman`, `rewriteAsAdaptiveMessage` (mit detailliertem System-Prompt), `translateText(to:)`, generische `chatCompletion`-Helper |
| `PasteService.swift` | `simulateCommandV`, `simulateCommandC`, Accessibility-Check, Input-Monitoring-Check via `IOHIDCheckAccess`, Permission-Prompt-Helper |
| `KeychainStore.swift` | Minimaler Wrapper um `SecItemAdd/Update/Delete` für den OpenAI-API-Schlüssel |
| `StatusMenuController.swift` | `NSStatusItem` mit animiertem Template-Icon (6-Frame-Recording / 8-Frame-Transcribing). Menu-Einträge: Einstellungen, Verlauf, Einrichtung erneut starten, Beenden. Error-Zustand wird als Text angezeigt |
| `SettingsView.swift` | SwiftUI-UI — große Datei (>1000 Zeilen). TabView mit 5 Tabs: Allgemein, Modi & Kürzel, Sprachübersetzung, Bedienungshilfen, Status. Enthält auch `OnboardingView`, `HistoryView`, `ReverseTranslatePopup`. Card-Layout mit Icons + Farben |
| `Info.plist` | macOS 15+, `LSUIElement=true`, `NSMicrophoneUsageDescription` |
| `Assets.xcassets/` | Idle-Icon, 6 Recording-Frames, 8 Transcribing-Frames, AppIcon |

---

## 3. Feature-Status

Alle erledigt und in `alva-fixes-live` gemerged (uncommitted):

- ✅ **Chunk 1**: Drei-Modi-Architektur (Standard=⌃, Höflich=⌥, Nachricht=⌘). Settings-Redesign mit Card-Layout. Adaptiver Chat-Prompt mit Ton-Erkennung.
- ✅ **Chunk 1b**: Toggle-Start/Stop Kollision gefixt. Emoji-/Abkürzungs-Feintuning im Message-Prompt.
- ✅ **Chunk 1c**: Leer-Transcript-Guard (GPT wird bei leerem Input nicht mehr aufgerufen). Any-Key-Stop während Toggle.
- ✅ **Chunk 2**: Sprach-Hotkeys via F-Tasten (F1/F2/F3 = Englisch/Französisch/Italienisch Default). Dynamisch in Settings erweiterbar auf 25 Sprachen.
- ✅ **Chunk 2b/c/d**: CGEventTap auf `.cgSessionEventTap` / `.listenOnly` (Accessibility-Permission reicht). Kantonesisch + Thailändisch ergänzt. `.function`-Flag wird aus Modifier-Vergleich ausgeschlossen (Fn bricht Aufnahme nicht mehr ab).
- ✅ **Chunk 3**: Rückwärtsübersetzung mit Popup. Default-Hotkey `⌃⌥Return` (layout-unabhängig). Konfigurierbar via Modifier-Checkboxes + Key-Picker.
- ✅ **Chunk 3e**: Popup neu gestaltet: Sprach-Chunks via `NLLanguageRecognizer`, Copy-Icons pro Box, Lightbox-Look (keine Titelleiste, Escape schließt).
- ✅ **Chunk 4**: Autostart (`SMAppService.mainApp`). First-Run-Onboarding (4 Seiten). Transkript-Verlauf mit Suche (letzte 50). Fehler-Handling mit lesbaren deutschen Meldungen.

---

## 4. Bekannte offene UX-Probleme (User-Feedback 22.04. morgens)

Diese sind NICHT code-bugs, sondern UX-/macOS-Eigenheiten:

1. **"Systemdialog anzeigen" für Input-Monitoring ist unzuverlässig.**
   `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` zeigt den Dialog
   nur beim allerersten Aufruf. Nach einmaliger Ablehnung oder nach
   Rebuild wird der Dialog nicht erneut gezeigt. **Lösung:** Button im
   Onboarding und Settings umbenennen oder durch einfacheres
   "Systemeinstellungen öffnen" ersetzen (das funktioniert immer).

2. **Input-Monitoring wird nach Rebuild stumm abgelehnt.** Die
   TCC-Datenbank merkt sich den alten Binary-Hash. Bei neuer Signatur
   kennt macOS die App nicht wieder → muss manuell aus der Liste
   entfernt und neu hinzugefügt werden. Selbes Problem wie
   Accessibility. **Dauerhafte Lösung**: Phase 4 (Developer-ID-Signing).

3. **Schritt-Zähler im Onboarding inkonsistent.** Seite mit
   "Eingabeüberwachung" zeigt "Schritt 3 — ..." im Titel aber
   "Schritt 4 von 4" oben rechts. Willkommens-Seite wird als "1 von 4"
   gezählt, hat aber keinen "Schritt N —"-Prefix.
   **Lösung:** Einheitliche Nummerierung.

4. **Zwei ALVA-Icons in Menu-Bar.** Xcode `⌘R` lässt oft die alte Binary
   laufen, die neue wird daneben gestartet. Lösung: vor `⌘R` die alte
   App explizit beenden (`⌘Q` auf der App oder Activity-Monitor-Kill).
   Tritt nur bei Dev-Builds auf, nach Release-Build weg.

5. **Pre-Population in Systemeinstellungen nicht möglich.** macOS
   verbietet aus Sicherheitsgründen, dass Apps sich selbst zu
   Accessibility/Input-Monitoring hinzufügen. Der Plus-Button + Finder
   + App-Auswahl ist der einzige Weg. Best Practice: kurzes
   Video/GIF-Onboarding mit Drag-Target-Anleitung (später).

6. **Message-Modus-Prompt-Tuning** noch offen: User möchte Emoji-Regeln
   leicht nachtunen, LG/VG im lockeren Ton beibehalten (ist bereits
   im Prompt, funktioniert meistens).

---

## 5. Reset-Skript für sauberes Onboarding-Retest

Dieses Skript im Terminal ausführen, um **alle** ALVA-TEXT-Spuren zu
entfernen und Onboarding von null zu testen:

```bash
#!/usr/bin/env bash
# ALVA-TEXT complete reset — run BEFORE testing onboarding from scratch

# 1. Stop all running instances
pkill -x "ALVA-TEXT" 2>/dev/null || true
sleep 1

# 2. Reset all TCC permissions (Accessibility, Input-Monitoring, Microphone)
tccutil reset All com.alva.text 2>/dev/null || true

# 3. Delete app preferences (UserDefaults: Hotkeys, History, Onboarding-Flag, …)
defaults delete com.alva.text 2>/dev/null || true

# 4. Delete API key from Keychain
security delete-generic-password -s "com.alva.text" -a "openaiApiKey" 2>/dev/null || true

# 5. Clear Xcode DerivedData (optional, für ganz saubere Rebuilds)
rm -rf ~/Library/Developer/Xcode/DerivedData/ALVA_TEXT-* 2>/dev/null || true

# 6. Unregister from launch-at-login (SMAppService)
# Kein direkter CLI-Befehl; wenn aktiv, über System-Settings → Anmeldeobjekte entfernen.

echo "✓ ALVA-TEXT vollständig zurückgesetzt. Jetzt in Xcode ⌘⇧K → ⌘B → ⌘R."
```

Speichere das als `~/reset-alva.sh`, mach's ausführbar (`chmod +x
~/reset-alva.sh`) und rufe `~/reset-alva.sh` vor jedem sauberen
Onboarding-Test auf.

---

## 6. Nächste Schritte

### Phase 4 — App-Store-Ready (höchste Priorität, nächste Session)

- Apple-Developer-Account-Setup validieren
- Bundle-ID in App-Store-Connect registrieren (`com.alva.text` oder
  `com.alperscheel.alvatext`)
- Entitlements: `com.apple.security.app-sandbox`,
  `com.apple.security.device.audio-input`,
  `com.apple.security.automation.apple-events`
- Hardened Runtime aktivieren
- Info.plist erweitern:
  - `NSAccessibilityUsageDescription`
  - `NSInputMonitoringUsageDescription` (via NSRequiresAquaSystemAppearance
    oder explizit)
  - App-Icon-Link
- `SMAppService`-Konfiguration für signierte App
- Privacy Manifest (`PrivacyInfo.xcprivacy`) mit den
  Data-Use-Kategorien deklarieren
- Code-Signing mit **Developer-ID Application**-Zertifikat
- Erste Archive-Build via Xcode → App-Store-Connect
- TestFlight-Build mit Alper + Family + Marius + Tobias als Testern
- App-Store-Listing: Screenshots, Beschreibung, Kategorie,
  Datenschutzerklärung

**Realistische Zeit**: 3-5h konzentriert + Review-Wartezeit (1-3 Tage).

### Phase 5 — Lokales Whisper (nach Phase 4 oder parallel)

- `WhisperKit` via Swift Package Manager einbinden
- `LocalTranscriber`-Klasse, die `whisper-small` beim ersten Start
  herunterlädt (~466 MB, nach `~/Library/Application
  Support/ALVA-TEXT/models/`)
- Settings-Option: Transkription **Cloud / Lokal / Auto**
- Fallback bei Netz-/API-Key-Fehler auf lokal, falls verfügbar
- UX für Modell-Download (Progress-Bar)

### Phase 6 — Lokales Rewrite (optional, später)

- MLX-Swift einbinden
- Llama 3.2 3B Modell (~2 GB) oder Qwen 2.5 3B
- Priorität: **Englisch-Übersetzung lokal** (User-Wunsch)
- Rewrite-Modi können ggf. Cloud bleiben (Qualitätsunterschied)

### Kleine UX-Polituren (zwischendurch)

- "Systemdialog anzeigen" zusammenlegen mit "Systemeinstellungen
  öffnen", wenn das IOHID-Prompt unzuverlässig ist
- Onboarding-Schritt-Zähler konsistent machen
- Erkennung "Mehrere ALVA-Instanzen laufen" mit Auto-Quit
- Kurzes Intro-GIF/Video im Onboarding

---

## 7. Handover-Workflow

### Git-Commit + Push (in deinem Mac-Terminal ausführen):

```bash
cd ~/codex-work/alper-scheel

# Sanity: was ist ungecommitet?
git status

# Alles adden (inkl. neuer Dateien: Assets.xcassets, KeychainStore.swift, docs/)
git add ALVA-TEXT/ALVA_TEXT.xcodeproj/project.pbxproj
git add ALVA-TEXT/ALVA_TEXT/ALVA_TEXTApp.swift
git add ALVA-TEXT/ALVA_TEXT/AppCoordinator.swift
git add ALVA-TEXT/ALVA_TEXT/AppDelegate.swift
git add ALVA-TEXT/ALVA_TEXT/HotkeyManager.swift
git add ALVA-TEXT/ALVA_TEXT/OpenAIService.swift
git add ALVA-TEXT/ALVA_TEXT/PasteService.swift
git add ALVA-TEXT/ALVA_TEXT/SettingsView.swift
git add ALVA-TEXT/ALVA_TEXT/StatusMenuController.swift
git add ALVA-TEXT/ALVA_TEXT/KeychainStore.swift
git add ALVA-TEXT/ALVA_TEXT/Assets.xcassets
git add docs/

# Commit
git commit -m "Chunks 1-4: full feature set (modes, language hotkeys, reverse translate, onboarding, history)

- 3 recording modes (Standard=Ctrl, Polite=Opt, Message=Cmd) with adaptive chat prompt
- Toggle (double-tap) with any-key-stop
- Language F-key hotkeys (F1=EN, F2=FR, F3=IT) + 25 languages in catalog
- Reverse translate (Ctrl+Opt+Return) with NLLanguageRecognizer chunks + lightbox popup
- Menu-bar icon with 6/8-frame animations
- Onboarding, history window (50 entries), launch-at-login, error UX
- CGEventTap at session level, listenOnly, works with Accessibility only"

# Push
git push origin alva-fixes-live
```

Falls `.git/index.lock` noch da (Sandbox-Artefakt):
```bash
rm -f .git/index.lock
```

### In der nächsten Cowork-Session

1. Neue Konversation starten
2. Ordner-Zugriff gewähren: `~/codex-work/alper-scheel`
3. Dieses Dokument öffnen: `docs/SESSION_STATUS.md`
4. Mit **Phase 4 (App-Store-Ready)** fortsetzen, falls Chunk 4 getestet
   und OK ist
5. Offene UX-Polituren nach Bedarf abarbeiten

---

## 8. Build-Setup & Permissions-Regel

**Nach jedem Rebuild** (Xcode-Dev-Build):
1. Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen**:
   ALVA-TEXT `−` entfernen, `+` neu hinzufügen
2. Systemeinstellungen → Datenschutz & Sicherheit → **Eingabeüberwachung**:
   ALVA-TEXT `−` entfernen, `+` neu hinzufügen
3. Nach Klick auf `+` via Finder zu `~/Library/Developer/Xcode/DerivedData/ALVA_TEXT-*/Build/Products/Debug/ALVA-TEXT.app` navigieren
4. App aktivieren (Toggle rechts)
5. Nach Input-Monitoring-Änderung: **App beenden und neu starten**
   (macOS zieht Input-Monitoring-Rechte erst nach Neustart an)

Diese Choreografie entfällt komplett in Phase 4 mit Developer-ID.

---

## 9. Default-Konfiguration

| Element | Default |
|---|---|
| Standard-Hotkey | `⌃` (Control) |
| Höflich-Hotkey | `⌥` (Option) |
| Nachricht-Hotkey | `⌘` (Command) |
| Reverse-Translate-Hotkey | `⌃⌥Return` |
| Doppeldruck-Fenster | 350 ms |
| Mindest-Aufnahmedauer | 400 ms |
| Sprach-Bindings | F1=en, F2=fr, F3=it |
| Whisper-Modell | `gpt-4o-mini-transcribe` |
| Umformulierungs-Modell | `gpt-4o-mini` |
| Autostart | aus |
| History | an (max. 50) |

---

## 10. Kontakt & Kontext

- **User**: Alper Scheel (alper.scheel@gmail.com)
- **Repo**: `github.com/Alper-Scheel/alper-scheel`
- **Lokaler Pfad**: `~/codex-work/alper-scheel`
- **Xcode-Projekt**: `ALVA-TEXT/ALVA_TEXT.xcodeproj`
- **Bundle-ID (aktuell)**: `com.alva.text`
- **macOS-Target**: 15.0
- **Swift-Version**: 5.0 (Xcode 16)
