---
auftrag: ALVA-TEXT-Doku 06-Monetarisierung_und_Roadmap.md aktualisieren
empfaenger: Claude Code (CC)
auftraggeber: Alper Scheel
erstellt: 2026-04-23 10:50 MEZ
prioritaet: P3 — Dokumentations-Update, nicht zeitkritisch
laufzeit: 15-25 min
---

# Auftrag: Brain-Vault-Doku 06-Monetarisierung auf aktuellen Stand bringen

## Kontext

Die Datei `~/Documents/Brain/02_PROJEKTE/ALVA-TEXT/06-Monetarisierung_und_Roadmap.md` wurde am 22.04. geschrieben, bevor die Paddle-Entscheidung final war. Inzwischen haben wir die Monetarisierungs-Architektur festgelegt:

**Finale Architektur-Entscheidungen (Stand 23.04.2026):**

1. **Paddle als Merchant-of-Record** (MoR) — kümmert sich um internationale Umsatzsteuer, VAT-MOSS, Währungen, Zahlungsabwicklung. Wir nutzen Paddle NICHT als Payment-Processor im technischen Sinne, sondern als voll-integrierten MoR — sie werden rechtlich der Verkäufer, wir sind Lizenzgeber.

2. **Webhook-Endpoint:** `POST https://api.adluna.de/v1/webhook/paddle` (bereits als Stub im Repo: `services/adluna-platform-api/app/endpoints/webhook.py`). Wird in Phase 2 aktiviert mit HMAC-Signatur-Verifikation.

3. **Kill-Switch-Mechanik** via `server_config.beta_mode_global`:
   - Solange `beta_mode_global=true` → alle aktivierten Geraete bekommen automatisch `status=beta, tier=full` (kostenlos)
   - Wechsel zu `beta_mode_global=false` nach Launch → Geraete wechseln zu `status=trial` (14 Tage Trial), danach `expired` wenn keine Zahlung
   - Nach Paddle-Zahlung: Webhook setzt `License.status=active, tier=paid, paid_at=<timestamp>`

4. **Ausgeschlossen:** Stripe, Braintree, direkte Payment-Integration. Paddle haben wir gewählt wegen MoR-Komfort (wir muessen keine globalen Steuer-Sachen selbst stemmen).

## Deine Aufgabe

1. `~/Documents/Brain/02_PROJEKTE/ALVA-TEXT/06-Monetarisierung_und_Roadmap.md` lesen
2. Inhalte pruefen: Was steht bereits drin? Was ist veraltet? Was fehlt?
3. Ergaenzen/Korrigieren mit den vier Architektur-Entscheidungen oben
4. Einen Abschnitt **"Technische Implementierung"** hinzufuegen, falls noch nicht vorhanden, mit:
   - Webhook-Endpoint-Pfad und Bedeutung
   - `server_config.beta_mode_global` als Kill-Switch
   - License-Status-Transitions (beta -> trial -> active/expired)
   - HMAC-Verifikation fuer Paddle-Webhooks (Phase-2-TODO)
5. Einen Abschnitt **"Zeitlicher Fahrplan"** mit Phasen:
   - Phase 1 (jetzt): Beta kostenlos, unbegrenzte Nutzer, Kill-Switch aktiv
   - Phase 2 (nach Landing-Page + Tester-Feedback): Paddle live, Preisfindung, Trial-Modell
   - Phase 3 (spaeter): weitere AdLuna-Produkte auf derselben Infrastruktur

## Regeln

- KEIN Stil-Umschreiben von Alper-formulierten Passagen. Falls ein Absatz inhaltlich nicht mehr stimmt, markieren mit `> [veraltet, siehe unten]` und neue Version anhaengen
- Wenn du unsicher bist, ob ein existierender Absatz noch gueltig ist: DRIN lassen, neue Version dazuhaengen, Alper entscheidet spaeter beim Review
- Keine komplette Neuschrift der Datei — nur Ergaenzungen und klar markierte Aktualisierungen
- Kein Commit ohne Alpers OK. Aenderung nur lokal im Brain-Vault.

## Rueckmeldung

1. Datei vorher/nachher: Zeilenzahl-Delta
2. Welche Abschnitte ergaenzt
3. Blocker, falls aufgetreten
