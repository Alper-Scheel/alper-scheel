# Phase 5 — Local Whisper (WhisperKit)

> **Ziel:** ALVA-TEXT funktioniert **standalone** ohne API-Schlüssel —
> lokale Transkription via WhisperKit (Whisper-Small auf Apple Silicon).
> OpenAI wird zum optionalen „Premium"-Upgrade für Umformulierung und
> Übersetzung.

---

## Was Claude bereits gemacht hat (im Code)

- **`LocalWhisperTranscriber.swift`** — neue Datei, gekapselt hinter
  `#if canImport(WhisperKit)` Guards. Kompiliert sauber auch ohne das
  Package; aktiviert sich automatisch sobald WhisperKit eingebunden ist.
  - `.prepare()` — lädt Whisper-Small beim ersten Aufruf
  - `.transcribe(audioURL:language:)` — Transkription mit
    ISO-639-1-Sprache (`"de"`, `"en"` etc.) oder nil für Auto-Detection
  - `.unload()` — RAM freigeben wenn User zur Cloud wechselt
- **`AppCoordinator`**:
  - Neuer Enum `TranscriptionBackend`: `.local` / `.cloud` / `.auto`
  - `@Published var transcriptionBackend` — default `.local`,
    persistiert in UserDefaults
  - `runTranscription(audioURL:)` wählt Backend aus, mit Auto-Fallback
    bei Cloud-Fehler
  - Pipeline verzweigt: ohne API-Key → nur Transkript, mit Key →
    alle Features. Bei fehlendem Key für Höflich/Nachricht/Übersetzung
    wird der Transkript ohne Transformation zurückgegeben, plus lesbare
    Fehler-Meldung
  - `HotkeyMode.requiresCloud` erkennt welche Modi OpenAI brauchen
- **`SettingsView`**:
  - Neue Card **„Transkriptions-Modus"** im Allgemein-Tab mit
    Radio-Buttons, Status-Zeile (geladen/nicht eingebunden), Anleitung
    zum Package-Hinzufügen
  - OpenAI-Schlüssel-Card ist jetzt als „optional" beschriftet, mit
    Erklärung welche Features ohne Key fehlen
- **Onboarding**:
  - Welcome-Seite sagt jetzt: „ALVA funktioniert direkt nach Installation"
  - API-Key-Seite ist optional markiert, User kann überspringen,
    sieht klare Liste welche Features mit/ohne Key verfügbar sind

---

## Was du jetzt in Xcode tun musst (1× einmalig)

### WhisperKit-Package hinzufügen

1. Xcode öffnen, Projekt `ALVA_TEXT.xcodeproj` laden
2. **File** → **Add Package Dependencies…**
3. URL-Feld oben rechts:
   ```
   https://github.com/argmaxinc/WhisperKit
   ```
4. **Dependency Rule**: Default (Up to Next Major Version)
5. **Add Package**
6. Im nächsten Dialog: Target `ALVA-TEXT` auswählen, **WhisperKit**
   anhaken
7. **Add Package**

Das war's. Xcode lädt das Package, resolvt dependencies, linkt gegen
unser Target.

### Validieren

8. `⌘⇧K` (Clean Build Folder)
9. `⌘B` (Build) — sollte durchlaufen, keine neuen Errors
10. `⌘R` (Run)
11. Settings öffnen → Allgemein → „Transkriptions-Modus"-Card:
    - Status sollte sein: **„Whisper-Small — wird beim ersten
      Lokal-Transkript geladen"** (grau/blau-Icon)
    - **NICHT** „Lokales Modell nicht eingebunden" (das wäre orange,
      = Package-Integration hat nicht geklappt)

### Erstes lokales Transkript

12. Modus-Picker in Settings auf **Lokal** stellen
13. In TextEdit: ⌃ halten + sprechen + loslassen
14. **Erster Aufruf**: WhisperKit lädt Whisper-Small Modell (~466 MB)
    — das kann 1-5 Minuten dauern, je nach Internet
15. Download-Progress wird im Console-Output (`⌘⇧Y`) sichtbar
16. Nach Download: Transkript erscheint
17. **Zweiter Aufruf**: Modell bleibt im RAM, Transkription in
    ~1-3 Sekunden fertig

---

## Hinweise zum Modell

- **Speicherort**: `~/Library/Application Support/<bundle-id>/huggingface/`
  (WhisperKit nutzt die Hugging-Face-Cache-Struktur)
- **RAM-Bedarf während Nutzung**: ~500 MB-1 GB, wird bei `unload()`
  freigegeben
- **Qualität Deutsch**: sehr solide für Standard-Diktat, etwas
  schlechter als Cloud-Whisper bei stark akzentuierter Sprache oder
  Fachbegriffen
- **Latenz**: 10 Sekunden Audio → ~2 Sekunden Transkription auf M1 Pro
- **Offline**: nach erstem Modell-Download funktioniert alles ohne Netz

---

## Troubleshooting

### „Cannot find 'WhisperKit' in scope"
→ Package wurde nicht gegen das ALVA-TEXT-Target gelinkt. In Xcode:
Target-Einstellungen → **Frameworks, Libraries, and Embedded Content**
→ `+` → WhisperKit auswählen → **Add**.

### Build-Fehler im WhisperKit-Code
→ WhisperKit braucht ein paar Swift-System-Libraries (CoreML,
Accelerate). Sollten automatisch kommen. Falls nicht: in
**General → Frameworks** manuell hinzufügen.

### „Transcription failed: Model not found"
→ WhisperKit hat das Modell nicht. Normalerweise lädt es beim ersten
`WhisperKit(config)`-Aufruf. Im Console-Output nach „downloading"
suchen; wenn kein Download stattfindet: API-Aufrufe zu huggingface.co
wurden blockiert (Firewall, DNS).

### App-Start-Performance leidet
→ Wir laden das Modell lazy beim ersten Transkript, nicht bei App-
Start. Wenn dir das zu langsam erscheint: in `AppCoordinator.start()`
einen `Task { try? await localWhisper.prepare() }` aufrufen, dann ist
das Modell beim ersten Bedarf schon geladen.

---

## Nach Phase 5 — zurück zu Phase 4

Wenn WhisperKit läuft und die App standalone funktioniert, dann:

1. In `ALVA_TEXT.entitlements`: `com.apple.security.app-sandbox`
   eventuell auf `true` flippen (für Mac App Store). Vorher lokal
   testen dass Paste noch funktioniert.
2. Xcode → **Product** → **Archive** — der Build ist jetzt
   sandbox-fähig und mit starkem Argument für Apple Review:
   „Die App funktioniert ohne externe Services. Der OpenAI-Schlüssel
   ist optional für Premium-Features."
3. Upload zu TestFlight (siehe `docs/PHASE_4_APP_STORE.md`)

---

## Warum dieser Schritt vor dem App Store wichtig ist

- **App-Review**: Apple ist skeptisch bei Apps, die ohne externe
  bezahlte Services nicht funktionieren. „BYOK-only" wird oft
  zurückgewiesen. Mit lokaler Default-Funktion fällt dieses Argument weg
- **Datenschutz**: Audio verlässt den Mac nicht im Standard-Betrieb.
  Starkes Marketing-Argument
- **Offline-Fähigkeit**: ALVA läuft im Flugzeug, im Zug, überall
- **Niedrigere Einstiegshürde**: User installiert → funktioniert.
  Kein API-Schlüssel-Setup im ersten Moment nötig
- **Premium-Upgrade-Pfad**: OpenAI-Schlüssel wird zum klaren Mehrwert,
  nicht zum Hindernis
