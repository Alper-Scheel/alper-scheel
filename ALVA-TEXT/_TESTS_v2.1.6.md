# v2.1.6 — Test-Checkliste

> **Vorgehen:** Punkt für Punkt durchgehen, je nach Ergebnis grün ✅ oder
> rot ❌ markieren. Bei rot: Notiz dazu, was schief gelaufen ist. Wenn
> alle grün: v2.1.6 ist Tester-tauglich, Begleit-Mail kann raus.
>
> **Stand:** Nach Bauen via `_v216-release-build.sh`.
> **Version-Erwartung:** 2.1.6 (Build 26)

---

## A · Installations-Check (vor App-Start)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| A.1 | Version sichtbar | Settings → Allgemein, Version-Anzeige | „Version 2.1.6 (Build 26)" | ☐ |
| A.2 | Apple-notarisiert | Im selben Block der grüne Haken | „Apple-notarisiert · signiert von AdPolis GmbH" | ☐ |
| A.3 | Bedienungshilfen-Liste sauber | Systemeinstellungen → Datenschutz → Bedienungshilfen | **Genau ein** ALVA-TEXT-Eintrag (kein Duplikat) | ☐ |

---

## B · Onboarding (Erststart, falls hasSeenOnboarding=false ist)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| B.1 | Onboarding kommt sauber | App-Start | Welcome-Window zeigt sich, kein TCC-Dialog parallel | ☐ |
| B.2 | Schritt-Counter | Header oben rechts | „Schritt 1 von 4" | ☐ |
| B.3 | API-Key-Eingabe | Schritt 2: Key eintragen oder skippen | Beides möglich, bei eingetragenem Key: „Schlüssel gespeichert — alle Features freigeschaltet" | ☐ |
| B.4 | Bedienungshilfen-Schritt | Schritt 3: Erlaubnis erteilen | TCC-Dialog kommt **einmal**, Toggle setzen, „Erneut prüfen" → grün | ☐ |
| B.5 | Kein Auto-Restart-Reset | Nach Toggle-Setzen Onboarding zurück | Onboarding bleibt bei Schritt 3, Springt **NICHT** zurück auf Schritt 1 | ☐ |
| B.6 | Eingabeüberwachung | Schritt 4: gleiche Prozedur | Wieder grüner Haken, kein Reset | ☐ |
| B.7 | Fertig-Klick | „Fertig" am Ende | Onboarding schließt sauber | ☐ |

> Wenn dein Mac noch von gestern den Onboarding-Flag gesetzt hat, kommt
> Onboarding nicht. Dann B-Block überspringen oder vorher mit
> `defaults write com.adserica.alvatext hasSeenOnboarding -bool false`
> zurücksetzen.

---

## C · Aktivierung & Account

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| C.1 | Aktivierungs-Status | Settings → Account | „Aktiv · Voller Funktionsumfang" grün | ☐ |
| C.2 | Wording „Beta" weg | Account-Tab inspizieren | **KEIN** Vorkommen von „Beta" oder „Beta-Phase" mehr im UI | ☐ |
| C.3 | Aktivierungs-Sheet (falls neu) | Account → Aktivieren | Header lautet „Vollzugang mit deiner E-Mail freischalten" — nicht „Beta-Zugang" | ☐ |
| C.4 | Done-Step ohne 500-Error | Aktivierungs-Sheet nach Erfolg | **Kein** roter „Server-Antwort 500" am Boden mehr | ☐ |
| C.5 | License-Gate aktiv | Wenn nicht aktiviert: Hotkey ⌃ halten | Aufnahme blockt, Settings öffnen sich im Account-Tab automatisch | ☐ |

---

## D · API-Key-Validation (#B14)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| D.1 | Korrekter Key | Settings → OpenAI-Feld: gültigen `sk-…` einfügen | Nach 1-3 Sek: grünes „Schlüssel funktioniert — alle Cloud-Features freigeschaltet" | ☐ |
| D.2 | Falscher Key | Im Feld einen Buchstaben verändern (z. B. `sk-XXX` ans Ende) | Nach 1-3 Sek: rotes „Schlüssel von OpenAI abgelehnt (401). Auf platform.openai.com prüfen…" | ☐ |
| D.3 | Leerer Key | Feld komplett leeren (⌘+A, Delete) | Kein Validation-Label sichtbar (Lokal-Modus reicht) | ☐ |
| D.4 | Key wieder einfügen | Original-Key wieder eintragen | Validation-Label springt zurück auf grün | ☐ |
| D.5 | Persistenz | App komplett quitten + neu starten, Settings öffnen | Validation-Label zeigt direkt grün (Validation läuft beim Launch) | ☐ |

---

## E · Diktat — Roh-Modus (Control)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| E.1 | Kurzes Diktat | TextEdit öffnen, ⌃ halten + 5 Sek diktieren | Text erscheint in TextEdit innerhalb von 1-3 Sek nach Loslassen | ☐ |
| E.2 | Längeres Diktat | ⌃ halten + 30 Sek diktieren (mehrere Sätze) | Text erscheint innerhalb von 5-10 Sek (kein Endlos-Rädchen) | ☐ |
| E.3 | Sofortige Wieder-Aufnahme | Direkt nach E.2 nochmal ⌃ halten + diktieren | Aufnahme startet sofort, kein Lock von voriger Aufnahme | ☐ |
| E.4 | In verschiedenen Apps | Test in Mail, Notes, TextEdit | In jeder App landet der Text korrekt im Cursor-Kontext | ☐ |
| E.5 | Kein Auto-Restart | Während Diktat ⌃ halten + loslassen | App-Status-Icon zeigt Aufnahme/Verarbeitung — kein Restart-Hinweis | ☐ |

---

## F · Diktat — Polite-Modus (Option)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| F.1 | Kurze formelle Mail | Mail → neuer Mail, ⌥ halten + „Hallo Frau Müller, anbei der Vertrag, viele Grüße" | Sauber höflich formatiert, „Mit freundlichen Grüßen" o. ä. | ☐ |
| F.2 | Antwortzeit | Wie lange dauert F.1? | < 8 Sek (vorher waren's 30+ Sek) | ☐ |
| F.3 | Direkt nochmal | Sofort nach F.1 nochmal ⌥ + Diktat | Funktioniert, kein Endlos-Rädchen | ☐ |
| F.4 | Cloud-Hänger-Fall | Falls OpenAI gerade träge ist | Nach max. 12 Sek bricht der Call ab + Fehler-Status, kein 60-Sek-Hänger | ☐ |

---

## G · Diktat — Adaptive Message (Command oder ⌥+⌃)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| G.1 | Lockerer Chat | Slack/Messages, ⌘ halten + „Hi Marius, wie war dein Wochenende, lass uns Mittwoch quatschen" | Locker formuliert, evtl. mit Emoji, kein „Sehr geehrte" | ☐ |
| G.2 | Formelle Mail | Mail-Body, ⌘ halten + „Sehr geehrte Frau Müller, bitte um Rückmeldung, danke" | Formell, „Mit freundlichen Grüßen" am Ende | ☐ |
| G.3 | Sign-off-Bug bleibt weg | Wenn keine Grußformel diktiert | Output endet **ohne** erfundenes „LG Alper" | ☐ |

---

## H · Modus-Wahl (Lokal vs. Cloud vs. Auto)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| H.1 | Default ist Lokal | Settings → Allgemein → Transkriptions-Modus | Radio-Button auf „Lokal (ohne Internet)" | ☐ |
| H.2 | Whisper-Small geladen | Im selben Block | „Whisper-Small geladen — Ready. Läuft mit Metal-Beschleunigung" mit grünem Haken | ☐ |
| H.3 | Prüfen-Button weg | Im selben Block | **KEIN** „Prüfen"-Button mehr neben dem Haken (#B16) | ☐ |
| H.4 | Auto-Modus testen (optional) | Auf „Automatisch" wechseln, Diktat | Funktioniert, im Hänger-Fall fällt nach max. 30 Sek auf Lokal zurück | ☐ |

---

## I · Stress-Test (das, was bei dir gestern hing)

| # | Test | Wie | Erwartung | Ergebnis |
|---|---|---|---|---|
| I.1 | 10× hintereinander Diktat | Jedes Mal anderer Modus, schnell hintereinander | Jeder Diktat läuft durch, kein einziges Endlos-Rädchen | ☐ |
| I.2 | App-Quit + sofortiger Restart | ⌘+Q, sofort wieder öffnen | Saubere Wiederaufnahme, Status grün | ☐ |
| I.3 | Sleep-Wake-Test | Mac in Sleep, aufwecken, sofort diktieren | Funktioniert ohne Permission-Dialog-Wiederkehr | ☐ |

---

## Auswertung

- **Alles grün:** v2.1.6 ist tester-tauglich. Nächster Schritt: Begleit-Mail an Conny / Vivi / Marius / Tobias / Sven.
- **A oder B rot:** Onboarding/Install-Bug — sofort melden, ich fixe gezielt.
- **C oder D rot:** Aktivierungs/Validations-Bug — gezielter Fix.
- **E rot:** Whisper-Lokal-Bug oder Bedienungshilfen-Permission — Console-Logs sammeln.
- **F oder G rot:** OpenAI-Cloud-Bug — Console-Logs + Key-Status.
- **H rot:** UI-Inkonsistenz — Edit-Korrektur.
- **I rot:** Performance-Regression — kritisch, vor Tester-Mail unbedingt fixen.

**Nicht alle Tests müssen heute laufen.** A, C, D, E, F, G sind Pflicht.
B, H, I sind Bonus, machen wir wenn Pflicht-Block grün ist.
