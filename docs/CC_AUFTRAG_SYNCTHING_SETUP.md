---
auftrag: Syncthing als iCloud-Ersatz für Desktop/Documents-Sync zwischen Alpers Macs
empfaenger: Claude Code (CC)
auftraggeber: Alper Scheel
erstellt: 2026-04-24
prioritaet: P2 — wichtig, aber nicht blockierend; erst NACH Time-Machine-Fix ausfuehren
laufzeit: 45-60 min (Installation auf beiden Macs + Ordner-Mapping + Tailscale-Verbindung)
voraussetzungen:
  - Time Machine muss wieder funktionieren (Backup-Fallback vor Umstellung)
  - Tailscale auf beiden Macs aktiv (ist bestehend)
  - Homebrew auf beiden Macs (MacBook Pro + Mac Studio M2 Ultra in Koenigs Wusterhausen)
---

# Auftrag: Syncthing-basiertes Peer-to-Peer-Sync zwischen MacBook Pro und Mac Studio

## Kontext

Alper moechte aus iCloud-Desktop/Documents-Sync raus. Gruende:
- Doppelte Dateien, verloren gegangene Screenshots
- Kein Vertrauen mehr in iCloud-Konsistenz
- Passt nicht zur AdLuna-/AdSerica-Datenhoheits-Philosophie (US-Cloud)

Anforderung: Wechsel zwischen MacBook Pro (mobil, Alpers primaeres Dev-Geraet) und Mac Studio M2 Ultra (stationaer in Koenigs Wusterhausen). Beide Macs sollen ausgewaehlte Ordner (Desktop, Dokumente, ggf. weitere) automatisch synchron halten.

Loesungsweg: **Syncthing** — Open-Source P2P-File-Sync, keine Cloud, Datenhoheit bei Alper, laeuft ueber Tailscale zwischen den beiden Macs.

## Deine Aufgaben

### Vorarbeit: Verifikation des Zielzustands

1. Bestaetigen, dass Time Machine wieder funktioniert und ein aktuelles Backup existiert. Wenn nicht → STOP, Alper informieren.

2. Feststellen welche Ordner gesynct werden sollen. Vorschlag zur Abstimmung mit Alper:
   - `~/Desktop` (Schreibtisch)
   - `~/Documents` (Dokumente)
   - `~/Downloads` NICHT — jedes Geraet hat eigene Downloads, die Sync-Kollisionen waere Chaos
   - Ggf. `~/Pictures/Screenshots` wenn separat konfiguriert

3. iCloud-Status pruefen: `defaults read com.apple.preferences.icloud 2>&1 | head -30`

### Schritt 1: Syncthing auf MacBook Pro installieren

```bash
brew install syncthing
```

Syncthing als launchd-Agent registrieren:

```bash
brew services start syncthing
```

Status pruefen: `brew services list | grep syncthing` → muss "started" zeigen.

Web-UI ist nach Start erreichbar unter http://127.0.0.1:8384 (lokal auf dem Mac).

### Schritt 2: Syncthing auf Mac Studio (Koenigs Wusterhausen) installieren

Ueber Tailscale SSH:

```bash
ssh <mac-studio-hostname>
brew install syncthing
brew services start syncthing
```

(Mac-Studio-Hostname aus /Users/AdPolis/.ssh/config lesen oder Alper fragen.)

### Schritt 3: Geraete miteinander verbinden

Syncthing identifiziert Geraete ueber Device-IDs (X.509-basierte Fingerprints). Auf beiden Macs:

1. Web-UI oeffnen
2. Device-ID anzeigen (Actions → Show ID)
3. Auf dem jeweils anderen Mac: **Add Remote Device** → Device-ID des anderen Macs eintragen
4. Bei Tailscale: Adresse des anderen Mac (`100.x.x.x`) direkt eingeben statt Discovery

### Schritt 4: Ordner konfigurieren

Fuer jeden zu syncenden Ordner (z.B. `~/Desktop`):

1. Auf MacBook: Web-UI → **Add Folder** → Pfad `/Users/AdPolis/Desktop`, Folder-ID `desktop-mbp`
2. **Sharing-Tab**: Mac Studio als Teilnehmer zulassen
3. Auf Mac Studio: Web-UI bekommt eine Benachrichtigung → **Accept**
4. Pfad bestaetigen oder auf Mac Studio auf einen anderen Pfad legen (z.B. `/Users/ms-studio-user/Desktop-Sync` um Vermischung zu vermeiden).

Wiederholen fuer Dokumente.

### Schritt 5: Ignore-Patterns konfigurieren

In Syncthing-Web-UI pro Ordner unter **Advanced → Ignore Patterns**:

```
.DS_Store
.Trashes
.fseventsd
.Spotlight-V100
*.tmp
~$*
.~lock.*
/node_modules
/.venv
/.git/objects/pack
```

Das verhindert Sync von Systemmuell und grossen Pack-Files.

### Schritt 6: Versionierung einschalten

Pro Ordner: **Versioning** → **Staggered File Versioning**, max 30 Tage. Schuetzt vor versehentlichen Loeschungen — Sync reserviert pro geloeschter Datei ein Backup in `.stversions/`.

### Schritt 7: Verifikation

1. Auf MacBook eine Test-Datei auf Desktop anlegen: `echo "test" > ~/Desktop/syncthing-test.txt`
2. Warten 10-30 Sekunden, dann auf Mac Studio pruefen: `ls ~/Desktop-Sync/syncthing-test.txt` (oder entsprechender Pfad).
3. Muss existieren mit gleichem Inhalt.
4. Umgekehrt testen.
5. Testdatei loeschen — Versionierung sollte einen Eintrag in `.stversions/` ablegen.

### Schritt 8: iCloud-Desktop/Documents-Sync auf MacBook deaktivieren

**ERST** wenn Syncthing stabil laeuft UND Time Machine ein aktuelles Backup hat.

1. System Settings → Apple-ID → iCloud → iCloud Drive → **iCloud-Drive-Ordner konfigurieren**
2. **"Desktop- und Dokumentenordner"** deaktivieren
3. Dialog: "Aus iCloud Drive entfernen" waehlen, **NICHT** "Kopie behalten bei iCloud"
4. macOS verschiebt die Dateien aus `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop` zurueck nach `~/Desktop`
5. Bei dem Prozess entstehen moeglicherweise doppelte Dateien (die bekannten Duplikate). **Dieser Schritt braucht Alpers Aufmerksamkeit.**

## Rueckmeldung an Alper

1. Syncthing-Versionen auf beiden Macs
2. Device-IDs (falls es fuer die Dokumentation relevant wird)
3. Test-Sync geklappt? (Testdatei-Verifikation aus Schritt 7)
4. iCloud deaktiviert? (Ja/Nein)
5. Blocker?

## Referenz

- Syncthing-Doku: https://docs.syncthing.net
- Versioning: https://docs.syncthing.net/users/versioning.html
- Ignoring: https://docs.syncthing.net/users/ignoring.html

## Weniger-ideal-Alternativen

Nur falls Syncthing nicht funktioniert:
- **Resilio Sync** — aehnlich, aber kommerziell
- **Chronosync** — manuelle Sync-Jobs, nicht real-time
- **NAS als Master** — alle Dateien auf NAS, lokal nur via SMB-Mount (braucht staendiges Netz)
