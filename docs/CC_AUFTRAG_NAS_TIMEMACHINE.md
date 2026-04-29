---
auftrag: Time Machine von nicht-existenter lokaler Platte auf NAS-4 (oder anderes NAS) migrieren
empfaenger: Claude Code (CC)
auftraggeber: Alper Scheel
erstellt: 2026-04-24
prioritaet: P1 — aktuell KEIN funktionierendes Backup auf dem MacBook
laufzeit: 30 min (Setup) + mehrere Stunden (erstes initiales Backup laeuft im Hintergrund)
voraussetzungen:
  - Tailscale aktiv zu allen NAS-Geraeten
  - admin-Credentials fuer NAS-Shares (in Brain-Vault/_SYSTEM/Zugangsdaten.md)
  - Time-Machine-faehige Netzlaufwerk-Konfiguration auf dem Ziel-NAS
---

# Auftrag: Time Machine auf NAS-Share umstellen

## Kontext

Alpers MacBook Pro hat aktuell **keine funktionierende Time Machine**:

- `tmutil destinationinfo` zeigt eine lokale Platte mit UUID `D376F67C-3B28-4E38-939D-EDA2352C62B8`
- `diskutil info` fuer diese UUID liefert "Could not find disk" — die Platte existiert nicht mehr auf dem System
- Es ist also ein verwaistes Time-Machine-Ziel ohne Backup-Volume

**Das ist kritisch:** Alper plant, iCloud-Desktop/Documents-Sync zu deaktivieren. Ohne funktionierendes TM waere er ohne Fallback, wenn iCloud-Migration schiefgeht.

Zielzustand: Eines der vorhandenen NAS-Geraete (`nas-4` cold-storage oder ein anderes NAS) uebernimmt die Time-Machine-Rolle. Sync laeuft automatisch, Backup-Historie wird 30-60 Tage vorgehalten.

## WICHTIG: Auftrag muss vom MacBook Pro ausgefuehrt werden

Alle TM-Operationen muessen **auf dem MacBook Pro** laufen, nicht auf MS512. Der MacBook ist derjenige, der ein Backup braucht.

Wenn CC aktuell auf MS512 ist:
- Entweder via SSH: `ssh AdPolis@100.105.100.105 "<befehl>"`
- Oder Alper startet Claude Code lokal auf dem MacBook

## Vorhandene Infrastruktur analysieren

**CC-Fund 2026-04-24:** Auf MS512 existiert bereits `/Users/ms512/mounts/TimeMachine/MS512.sparsebundle/`. Das heisst: MS512 macht selbst bereits Time Machine, vermutlich auf ein NAS.

Erster Schritt: **existing Setup verstehen**, bevor wir parallel dasselbe fuer den MacBook aufsetzen.

```bash
# Auf MS512: welches NAS ist das TM-Ziel?
ssh ms512@100.101.8.27 'tmutil destinationinfo -X 2>&1'

# Wo ist das Sparsebundle wirklich gemountet?
ssh ms512@100.101.8.27 'mount | grep -i timemachine; ls -la /Users/ms512/mounts/'
```

Sobald klar: NAS-Adresse und Share-Pfad. Wir nutzen **dasselbe NAS** fuer MacBook-TM, aber mit eigenem Sparsebundle (macOS erzeugt automatisch einen, benannt nach Mac-Hostname).

## Entscheidung vorab: welches NAS?

Aus der Infrastruktur-Uebersicht (siehe `~/Documents/Brain/_SYSTEM/` bzw. global CLAUDE.md):
- `nas-1` (100.68.166.30) — intermittent
- `nas-2` (100.75.202.105) — aktive Projekte (Stub)
- `nas-3` (100.102.50.43) — intermittent
- `nas-4` (100.97.76.86) — Cold Storage / Backup
- `nas-ai-data` (100.125.222.69) — ML-Trainingsdaten

**Empfehlung: `nas-4`** — ist explizit als Backup-Rolle dokumentiert, stabil.

Falls `nas-4` aus technischen Gruenden nicht geht (kein AFP/SMB-Time-Machine-Support, kein freier Platz, Performance-Probleme), Fallback `nas-ai-data` oder `nas-1`.

## Deine Aufgaben

### Schritt 1: NAS-4 Time-Machine-Faehigkeit verifizieren

```bash
# SSH zu nas-4
ssh nas-4 "uname -a; df -h | head -5"
```

Synology-NAS erwartet? Wenn ja:
- DSM-Control-Panel muss "Time Machine" unter "Service" erlauben
- SMB-Share muss fuer Time Machine markiert sein
- Freier Speicher sollte >= 500 GB sein (Alpers Mac hat vermutlich 1-2 TB, TM braucht 2-3x)

Wenn SSH auf `nas-4` nicht funktioniert: siehe Alpers `~/Documents/Brain/_SYSTEM/Zugangsdaten.md` fuer DSM-Web-Zugang. Dann Alper kurz bitten, das Time-Machine-Share im DSM zu aktivieren.

### Schritt 2: Alten TM-Eintrag vom MacBook entfernen

Auf Alpers MacBook (via SSH von CC):

```bash
# Verwaistes Ziel entfernen
sudo tmutil removedestination D376F67C-3B28-4E38-939D-EDA2352C62B8
```

Falls das fehlschlaegt (UUID nicht mehr da): ignorieren, weitergehen.

### Schritt 3: Time-Machine-Share auf NAS-4 mounten

```bash
# Auf MacBook
# Share-Pfad variiert je nach NAS-Konfiguration. Synology DSM-Konvention:
# smb://admin@100.97.76.86/TimeMachine
open "smb://admin@100.97.76.86/TimeMachine"
```

Das oeffnet den Finder-Prompt fuer SMB-Login. Alper muss einmalig das NAS-Passwort eingeben und **Passwort im Schluesselbund speichern** ankreuzen.

### Schritt 4: Neues TM-Ziel setzen

```bash
sudo tmutil setdestination -a "smb://admin:<passwort>@100.97.76.86/TimeMachine"
```

**ACHTUNG:** Passwort im Befehl ist riskant (Shell-History). Besser:

```bash
# Alternative: Systemeinstellungen nutzen
open "x-apple.systempreferences:com.apple.preference.timemachine"
```

Dann im UI: Time-Machine-Volumen auswaehlen → NAS-Share aus der Liste waehlen → Verschluesselung aktivieren (empfohlen, AES-256, Passwort im Keychain speichern).

### Schritt 5: Erstes Backup starten

```bash
sudo tmutil startbackup --block
```

Das startet das initiale Backup und blockiert bis es durch ist (kann 2-8 Stunden dauern bei mehreren Hundert GB).

Alternativ: Ohne `--block`, dann laeuft es im Hintergrund und du kannst waehrenddessen Progress mit `tmutil status` pruefen.

### Schritt 6: Verifikation

```bash
tmutil latestbackup  # Muss einen Pfad zeigen, nicht mehr "Failed to mount"
tmutil status        # Sollte "Running = 1" zeigen waehrend Backup laeuft
```

Sobald `tmutil latestbackup` einen Pfad liefert, ist die Infrastruktur stabil. Danach kann Alper iCloud-Desktop/Documents-Sync deaktivieren.

### Schritt 7: Automatik + Retention

Standardmaessig macht macOS alle 1h ein inkrementelles Backup. Das ist gut so.

Retention (auf NAS-Seite bei Synology):
- DSM → Systemsteuerung → Freigegebene Ordner → TimeMachine → Bearbeiten → Zeitplan fuer geplante Backups **nicht noetig**, das macht macOS
- Optional: Kontingentbegrenzung setzen (z.B. 1 TB), damit TM nicht das ganze Volume fuellt

## Rueckmeldung an Alper

1. NAS-4 Time-Machine-Share aktiviert (ja/nein + Pfad)
2. Altes verwaistes TM-Ziel entfernt (ja/nein)
3. Neues Ziel gesetzt: SMB-Share-Pfad
4. Erstes Backup: Status + Zeitschaetzung
5. `tmutil latestbackup` Output nach Abschluss erstem Backup
6. Blocker / Abweichungen

## Sicherheitshinweise

- Keine Passwoerter in Shell-History lassen
- Backup-Verschluesselung aktivieren (wichtig, wenn NAS mal abhandenkommen sollte)
- Verschluesselungspasswort in Brain-Vault `_SYSTEM/Zugangsdaten.md` ergaenzen
- Nach dem ersten erfolgreichen Backup: `tmutil destinationinfo -X` zeigen, damit wir den neuen Stand dokumentieren koennen

## Nach-Arbeit

Sobald das erste Backup durch ist, erst dann:
- iCloud-Desktop/Documents-Sync deaktivieren (separate Session, siehe `CC_AUFTRAG_SYNCTHING_SETUP.md`)
- Syncthing zwischen MacBook und Mac Studio aufsetzen
