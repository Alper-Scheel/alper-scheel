# Phase 4 — App Store / TestFlight-Vorbereitung

> **Ziel:** ALVA-TEXT signiert archivieren, TestFlight-Build hochladen,
> Family + Marius + Tobias als Tester einladen.

---

## Was Claude bereits gemacht hat (im Repo)

- **`ALVA-TEXT/ALVA_TEXT/ALVA_TEXT.entitlements`** — Entitlements-Datei
  - Sandbox aktuell **ausgeschaltet** (für einfacheren TestFlight-Beta-Start)
  - Mikrofon-Zugriff aktiviert
  - Netzwerk-Client aktiviert
- **`ALVA-TEXT/ALVA_TEXT/Info.plist`** — Purpose-Strings auf Deutsch:
  - `NSMicrophoneUsageDescription`
  - `NSAccessibilityUsageDescription`
  - `NSAppleEventsUsageDescription`
  - `LSApplicationCategoryType` = Produktivität
  - `NSHumanReadableCopyright`
  - `CFBundleDisplayName`
- **`ALVA-TEXT/ALVA_TEXT/PrivacyInfo.xcprivacy`** — Apple-Privacy-Manifest
  - Audio und Textinhalte deklariert (für App-Funktionalität, nicht
    für Tracking oder Identitäts-Linking)
  - Required-Reason-APIs: UserDefaults (CA92.1), FileTimestamp (C617.1)
- **`project.pbxproj`** — Build-Konfiguration angepasst:
  - `ENABLE_HARDENED_RUNTIME = YES`
  - `CODE_SIGN_ENTITLEMENTS = ALVA_TEXT/ALVA_TEXT.entitlements`
  - Entitlements + Privacy-Manifest als Projekt-Files registriert
  - PrivacyInfo.xcprivacy wird als Resource ins Bundle kopiert

## Was du jetzt in Xcode tun musst

### 1. Signing Team konfigurieren (2 Minuten)

1. Xcode öffnen, Projekt laden
2. Project Navigator links → oberster Eintrag `ALVA-TEXT` (blaues Icon)
3. Target `ALVA-TEXT` auswählen → Reiter **Signing & Capabilities**
4. **Team** Dropdown → deinen Entwickler-Account auswählen
   (vermutlich `Alper Scheel (DEINE-TEAM-ID)`)
5. Xcode ergänzt automatisch:
   - Provisioning Profile (für Debug-Signing)
   - Signing Certificate

### 2. Bundle-ID prüfen und ggf. ändern (2 Minuten)

Aktuell (ab 22.04.2026): `com.adserica.alvatext` — gehalten von
**AdSerica Ltd. (Hong Kong)**. Die Bundle-ID ist in `project.pbxproj`
bereits gesetzt, `KeychainStore.swift` verwendet denselben String als
Keychain-Service-Name, und Info.plist trägt AdSerica als Copyright-
Inhaber. Nichts manuell in Xcode zu ändern.

Hintergrund: Das geistige Eigentum an ALVA-TEXT soll bei AdSerica Ltd.
liegen (IP-Holding, gehört Alper + Tobias). Der Apple Developer Account
kann vorübergehend der bestehende Org-Account sein; der Umzug auf einen
eigenen AdSerica-Developer-Account erfolgt über Gleis 2 (siehe
SESSION_STATUS.md → Phase 4).

### 3. App-ID im Apple Developer Portal registrieren (5 Minuten)

1. `developer.apple.com` → **Account** → **Certificates, IDs & Profiles**
2. **Identifiers** → `+` → **App IDs** → **Continue** → **App**
3. Eingeben:
   - **Description**: ALVA-TEXT
   - **Bundle ID**: Explicit → die Bundle-ID aus Xcode
4. **Capabilities**:
   - Keine besonderen Capabilities nötig (Accessibility und
     Input-Monitoring sind TCC-Runtime-Permissions, keine Entitlements)
5. **Continue** → **Register**

### 4. App in App Store Connect anlegen (5 Minuten)

1. `appstoreconnect.apple.com` → **Meine Apps** → `+` → **Neue App**
2. Eingeben:
   - **Plattform**: macOS
   - **Name**: ALVA-TEXT (oder eigener Marketing-Name)
   - **Primäre Sprache**: Deutsch
   - **Bundle-ID**: die registrierte ID auswählen
   - **SKU**: beliebige eindeutige Kennung, z.B. `ALVA-TEXT-001`
   - **Benutzerzugriff**: Voller Zugriff
3. **Erstellen**

### 5. Archive + Upload via Xcode (10 Minuten)

1. Xcode → **Product** → **Scheme** → **ALVA-TEXT** (sollte bereits aktiv sein)
2. Build-Target oben in Toolbar: **Any Mac** oder **My Mac** auswählen
3. **Product** → **Archive**
4. Xcode baut (kann 1-2 Minuten dauern)
5. **Organizer**-Fenster öffnet sich automatisch mit fertigem Archive
6. **Distribute App** → **App Store Connect** → **Upload**
7. Optionen durchklicken:
   - **Distribution Options**: Default (Hochladen + Include Symbols)
   - **Re-sign**: Automatically manage signing
8. **Upload** → wenige Minuten Wartezeit
9. In App Store Connect: **TestFlight** → dein Build erscheint nach
   Apple-Processing (~15-30 Minuten) mit Status „Fertige Verarbeitung"

### 6. TestFlight-Tester einladen (5 Minuten)

1. App Store Connect → deine App → **TestFlight**
2. **Testflight-Information** → Beta-App-Beschreibung, Test-Notizen
   und Feedback-E-Mail ausfüllen (ist Pflicht für externe Tester)
3. **Interne Tester**: bis zu 100 Leute mit Rolle „Entwickler" oder
   „Admin" in deinem Team — können SOFORT testen, ohne Beta-Review
4. **Externe Tester**: bis zu 10.000 Leute via E-Mail oder Link —
   braucht **Beta App Review** von Apple (1-2 Tage)
5. Für deine Family-First-Runde: **Interne Tester** ist schneller
   - **+**-Button → E-Mail-Adressen eingeben
   - Apple schickt Einladungs-Mails mit TestFlight-Installations-Link
6. Tester öffnen TestFlight.app auf ihrem Mac → ALVA-TEXT erscheint
   dort → installieren → nutzen

---

## Typische Probleme beim ersten Archive + Fixes

### „Code Sign error: No signing certificate found"
→ Team in Xcode Signing & Capabilities noch nicht gewählt, oder kein
gültiges Distribution-Zertifikat im Keychain. Xcode hat einen Button
„Manage Certificates" — dort lässt sich eins erstellen.

### „Provisioning profile doesn't include beta-reports-active capability"
→ Apple Developer Portal → App-ID nochmal prüfen, Edit, dann in Xcode
**Automatically manage signing** aus- und wieder einschalten. Xcode
lädt das Profil neu.

### „The entitlement is not in the provisioning profile"
→ Entitlements-Datei enthält Keys, die nicht mit dem Provisioning
Profile abgeglichen sind. Meist `com.apple.security.app-sandbox` bei
Apps, die nicht für den Store gedacht sind. Lösung: Sandbox ausschalten
(in `ALVA_TEXT.entitlements`) oder im App-ID-Eintrag Sandbox aktivieren.

### „Invalid Code Signing Entitlements"
→ Für Apps außerhalb der Sandbox dürfen **keine** App-Sandbox-
spezifischen Entitlements im File sein. Wir haben Sandbox = `false`
gesetzt, das passt.

### TestFlight sagt „Processing" und tut nichts für Stunden
→ Normal. Apple braucht manchmal 30 Minuten bis mehrere Stunden. Falls
länger als 24h: im Organizer checken, Build erneut hochladen.

### Tester-Mac sagt „App ist beschädigt" beim ersten Start
→ macOS Gatekeeper ist strikt. Rechtsklick → Öffnen → „Trotzdem
öffnen" beim ersten Start. Bei TestFlight-signierten Apps normalerweise
nicht nötig, nur bei ad-hoc-Builds.

---

## Was noch offen ist (nach Phase 4)

- **App Store Review** für vollständige Veröffentlichung (nicht nur
  TestFlight): braucht nochmal Screenshots, Beschreibung, Keywords,
  Datenschutzerklärung (kann ich beim nächsten Mal generieren)
- **Sandbox einschalten**: wenn TestFlight stabil läuft, Sandbox in
  Entitlements auf `true` flippen und nochmal testen, dann Submit
- **Privacy Policy URL**: App Store verlangt eine Datenschutzerklärung
  online (z.B. als Seite auf deiner eigenen Website)

---

## Zusammenfassung

1. Xcode öffnen → Team auswählen → Bundle-ID vergeben
2. Apple Developer Portal → App-ID registrieren
3. App Store Connect → App anlegen
4. Xcode → Product → Archive → Upload
5. TestFlight → Tester einladen
6. Family testet, du sammelst Feedback
7. Später: App Store Submission mit Sandbox an, Screenshots etc.

**Voraussichtlicher Zeitaufwand für dich**: 30-40 Minuten aktive Klickerei,
plus 15-30 Minuten Apple-Processing-Wartezeit.
