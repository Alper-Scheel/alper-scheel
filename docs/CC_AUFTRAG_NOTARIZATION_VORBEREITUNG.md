---
auftrag: Notarization-Pipeline vorbereiten, ohne echten Build-Lauf
empfaenger: Claude Code (CC)
auftraggeber: Alper Scheel
erstellt: 2026-04-23 10:50 MEZ
prioritaet: P2 — Vorbereitung fuer heutige Abend-Session
laufzeit: 20-30 min
---

# Auftrag: Direct-Distribution-Notarization-Pipeline vorbereiten

## Kontext

Wir haben heute Abend den Zeitpunkt, einen ersten notarisierten Release-Build von ALVA-TEXT zu erstellen — sobald die Landing-Page steht, hostten wir den Download unter `downloads.adluna.de` und starten die Tester-Phase.

Das Skript `docs/release-to-ms512.sh` existiert bereits (erstellt letzte Woche), soll aber vor dem ersten echten Lauf **geprueft und auf den aktuellen Stand gebracht** werden.

## Deine Aufgabe

### 1. Zertifikate-Check

```bash
# Developer-ID-Zertifikat vorhanden?
security find-identity -v -p codesigning | grep "Developer ID Application"

# Ergebnis muss zeigen: "Developer ID Application: AdPolis ... (TEAMID)"
```

### 2. notarytool-Credentials-Check

```bash
# Sind Apple-ID + App-specific-Password fuer Notary konfiguriert?
xcrun notarytool history --keychain-profile "alva-notary" 2>&1 | head -10
```

Falls nicht konfiguriert: Anweisung fuer Alper vorbereiten (er muss das einmalig machen mit `xcrun notarytool store-credentials` + App-spezifischem Passwort von appleid.apple.com).

### 3. release-to-ms512.sh review

Datei lesen: `docs/release-to-ms512.sh`

Pruefen:
- Bundle-ID `com.adserica.alvatext` (neu) oder `com.alva.text` (alt)? Muss `com.adserica.alvatext` sein
- `xattr -cr` vor codesign? Muss da sein
- `ditto -c -k --sequesterRsrc --keepParent` fuer signature-preserving ZIP? Muss da sein
- Ziel-Verzeichnis MS512 + NAS-4?
- rsync-Flags macOS-BSD-kompatibel? (`--append-verify` entfernt, nur `--partial --progress`)

Falls Abweichungen: Anweisung vorbereiten, keinen Edit ohne Alpers OK.

### 4. Download-Hosting vorbereiten (Infra-Skelett)

`downloads.adluna.de` braucht einen zweiten Cloudflare Tunnel (oder dieselben Tunnel mit zusaetzlichem Public Hostname) + statischen File-Server auf MS512.

Empfohlene Struktur auf MS512:

```
~/services/downloads.adluna.de/
├── index.html               (einfache Landing mit Release-Notes)
├── alva-text/
│   ├── latest/
│   │   ├── ALVA-TEXT-1.0.0.zip
│   │   ├── ALVA-TEXT-1.0.0.zip.sha256
│   │   └── release-notes.md
│   └── history/             (alle aelteren Versionen)
└── checksums.txt
```

Static-File-Serving: `python3 -m http.server` ist zu billig fuer Produktion.
Empfehlung: nginx (via Homebrew) oder Python `aiohttp`-basierter Mini-Server mit Logging.

**NICHT installieren, nur Entscheidung vorbereiten.**

### 5. Reichtext fuer Alpers spaeteres "Los-Buildern"

Nachdem alles geprueft ist, Alper einen One-Liner-Befehl zusammenfassen, den er spaeter abends ausfuehren kann:

```bash
bash docs/release-to-ms512.sh 1.0.0
```

Plus: Erwartungen setzen, wie lange Notarization dauert (5-15 Min typisch, 1h im Worst Case).

## Regeln

- KEIN echter Build-Lauf heute. Nur Vorbereitung.
- KEIN codesign, KEIN notarytool submit — das ist Alpers Entscheidung
- KEIN Installation von nginx oder anderer Infrastruktur. Empfehlung vorbereiten, Alper entscheidet
- Alle Empfehlungen als strukturierter Bericht fuer Alper

## Rueckmeldung

1. Zertifikate-Check: ok / problem
2. notarytool: konfiguriert / muss Alper einmalig einrichten
3. release-to-ms512.sh review: ok / Abweichungen (Liste)
4. Download-Hosting Empfehlung: nginx / Python-aiohttp / Alternative
5. Empfohlener naechster Schritt fuer Alper (One-Liner)
