# Build-Anleitung — ALVA-TEXT v2.2.0-beta1 (Build 23)

> Persönlicher Daily-Test-Build. **NICHT** auf adluna.de oder GitHub Releases hochladen — die v2.2-Webseite-Doku liegt absichtlich noch unveröffentlicht.

---

## Was in diesem Build neu ist (Phase 1a)

- **Mode-Switch Standard ↔ Pro** im Onboarding (Schritt 0) und in den Settings.
- **Personalization-Reiter „Persönlich"** in den Settings — sichtbar in beiden Modi, voll aktiv nur in Pro.
- **Identitäts-Block:** Profilname, Emoji, Anredename, Initialen, Rolle, Firma, Hauptsprache.
- **Sign-offs:** formell, locker, default — fließen in den Adaptive-Mode-System-Prompt ein, nur wenn der Diktat-Text mit einem Gruß-Hinweis endet.
- **No-Go-Phrasen** mit Add/Delete-UI.
- **Wortschatz-Bibliothek** mit Eigennamen + Korrektur-Mappings.
- **Multi-Profil:** anlegen, duplizieren, umschalten, löschen — eines aktiv.
- **Foundation für alle weiteren Cluster** ist gelegt (PersonalizationProfile + PersonalizationStore + ProMode + ChannelClass).

**Noch nicht in beta1** (kommt in beta2 / beta3):
- Custom Dictation Modes mit eigenen Hotkeys + System-Prompts (inkl. Prompt-Optimizer)
- Pro-App-Erkennung mit Auto-Profil-Wechsel
- Cloud-Privacy-Feinsteuerung mit Send-Vorschau
- Output-Verhalten pro Modus (Auto-Paste / Pre-Confirm / Drag-Handle)
- Adaptive Learning (lokal, opt-in)
- Kontakt-/Kalender-Integration (EventKit / Contacts)
- Profile-Picker in der Menüleiste (heute nur in den Settings umschaltbar)

---

## Geänderte / neue Dateien

| Datei | Status |
|---|---|
| `ALVA_TEXT/ProMode.swift` | NEU |
| `ALVA_TEXT/PersonalizationProfile.swift` | erweitert |
| `ALVA_TEXT/PersonalizationStore.swift` | NEU |
| `ALVA_TEXT/PersonalizationTabView.swift` | NEU |
| `ALVA_TEXT/AppCoordinator.swift` | edit (proMode-Property + .message-Verdrahtung) |
| `ALVA_TEXT/SettingsView.swift` | edit (TabView neuer Tab + OnboardingView Mode-Page) |
| `ALVA_TEXT/Info.plist` | edit (2.2.0-beta1 / 23) |
| `ALVA_TEXT.xcodeproj/project.pbxproj` | edit (3 neue Files + Version) |

Backup: `project.pbxproj.bak.v22-beta1` liegt im Xcodeproj-Ordner.

---

## Build-Schritte

Identisch zur v2.1.3-Pipeline — Notarisierungs-Profil und Signing-Identity müssen in deinem Keychain liegen.

```bash
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT

# 1) Sauberen Build-Ordner anlegen
rm -rf build && mkdir -p build

# 2) Archive bauen
xcodebuild \
  -project ALVA_TEXT.xcodeproj \
  -scheme ALVA_TEXT \
  -configuration Release \
  -archivePath build/ALVA-TEXT.xcarchive \
  archive

# 3) Export
xcodebuild \
  -exportArchive \
  -archivePath build/ALVA-TEXT.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
# Falls ExportOptions.plist nicht existiert: anlegen mit method=developer-id, signingStyle=automatic
```

Wenn `xcodebuild` mault, dass das Schema nicht shared ist:
- Xcode öffnen → Product → Scheme → Manage Schemes → ALVA_TEXT → "Shared" anhaken.

---

## Sign / Notarize / DMG

Wie bei v2.1.3:

```bash
cd /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT/build/export

# 4) Codesign-Verifikation
codesign --verify --deep --strict --verbose=2 ALVA-TEXT.app

# 5) ZIP für Notarisierung
ditto -c -k --keepParent ALVA-TEXT.app ALVA-TEXT.zip

# 6) Notarisieren (Profil "alva-notary" muss im Keychain stehen)
xcrun notarytool submit ALVA-TEXT.zip \
  --keychain-profile alva-notary \
  --wait

# 7) Stapeln
xcrun stapler staple ALVA-TEXT.app

# 8) DMG bauen
create-dmg \
  --volname "ALVA-TEXT v2.2.0-beta1" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "ALVA-TEXT.app" 175 190 \
  --hide-extension "ALVA-TEXT.app" \
  --app-drop-link 425 190 \
  ALVA-TEXT-v2.2.0-beta1.dmg \
  ALVA-TEXT.app

# 9) DMG ebenfalls notarisieren + stapeln
xcrun notarytool submit ALVA-TEXT-v2.2.0-beta1.dmg \
  --keychain-profile alva-notary \
  --wait
xcrun stapler staple ALVA-TEXT-v2.2.0-beta1.dmg
```

---

## Lokal installieren

```bash
# Aktuelle v2.1.3 löschen, neue Version in /Applications kopieren
osascript -e 'quit app "ALVA-TEXT"' || true
sleep 1
rm -rf /Applications/ALVA-TEXT.app
cp -R /Users/AdPolis/codex-work/alper-scheel/ALVA-TEXT/build/export/ALVA-TEXT.app /Applications/
open /Applications/ALVA-TEXT.app
```

Beim ersten Start sollte das **Onboarding mit der Mode-Wahl** erscheinen. Wähl Pro, geh durch die restlichen Schritte, dann erscheint in den Settings der neue Tab „Persönlich".

---

## Sanity-Tests, die du machen solltest

1. **Onboarding-Flow:** Erststart zeigt Mode-Wahl. Standard und Pro lassen sich beide wählen, Weiter ist erst aktiv nach Wahl.
2. **Mode-Switch in Settings:** „Persönlich"-Tab → Modus toggeln. Standard zeigt nur Hinweis-Card, Pro zeigt alle Editor-Karten.
3. **Profil-Persistierung:** Anredename, Initialen, Rolle eintragen → App neu starten → Werte sind noch da.
4. **Sign-off-Wirkung:** Im Pro-Modus „LG Alper" als „Locker"-Sign-off setzen. Diktat: „Hi Marius, kurz Bescheid lg." → Adaptive-Output sollte „LG Alper" am Ende haben (nicht „LG", nicht erfunden, sondern aus deinem Profil).
5. **Standard-Verhalten unverändert:** Im Standard-Modus diktieren → kein Personalisierungs-Block im Output, exakt wie in v2.1.3.
6. **Multi-Profil:** Zweites Profil „Geschäftlich" anlegen, anderen Sign-off setzen, im Picker umschalten → nächstes Diktat nutzt neues Profil.
7. **Wortschatz:** „Conny" eintragen, „Konny" diktieren → Output sollte „Conny" schreiben.

---

## Troubleshooting

- **Cannot find type 'PersonalizationStore' in scope** → in Xcode: File → Packages → Reset Package Caches, dann Clean Build Folder (⌘⇧K) und nochmal Build.
- **Compile-Error in PersonalizationTabView.swift / unterminated string** → eigentlich gefixt; falls doch: die deutschen Anführungszeichen in `prompt:`-Strings sind die häufigste Ursache. Im Zweifel `python3` Hex-Dump auf die Datei laufen lassen oder die Datei nochmal von mir anfordern.
- **Settings-Window öffnet leer** → `PersonalizationStore.shared` Initialisierung prüfen. UserDefaults-Key `alva.profiles` löschen mit `defaults delete com.adserica.alvatext alva.profiles` und App neu starten.
- **Onboarding kommt nicht** → `defaults write com.adserica.alvatext hasSeenOnboarding -bool false` und `defaults delete com.adserica.alvatext alva.proMode`, dann App neu.

---

## Was ich morgen / am Tag 2 baue (Phase 2)

- Profile-Picker in der Menüleiste (StatusMenuController)
- Custom Dictation Modes (eigene Hotkeys + Prompts) inkl. Prompt-Optimizer auf `⌃⌥⌘`
- Output-Verhalten pro Modus
- Cloud-Privacy-Feinsteuerung mit Send-Vorschau
- Pro-App-Erkennung (`NSWorkspace.frontmostApplication` → Profil-Auto-Mapping)

Stand: 2026-04-27
