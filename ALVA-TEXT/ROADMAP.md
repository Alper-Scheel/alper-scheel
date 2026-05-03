# ALVA-TEXT — Roadmap & Strategische Entscheidungen

> **Lebende Dokumentation** — wird bei jeder strategischen Entscheidung
> aktualisiert. Liegt im Repo, ist Teil von Git-History, geht nie verloren.
>
> **Stand:** 2026-05-03

---

## Versions-Strategie

### v2.1.x — Stabilisierung (jetzt)
Aufgabe: Aus dem heutigen Zustand eine zuverlässig laufende Beta-App machen.
Ziel ist ein stabiles Fundament für die Tester-Auslieferung. **Kein
Feature-Wachstum**, nur Bug-Fixes.

- **v2.1.5** (heute) — Onboarding-Reset-Bug, Beta-Wording weg, License-Gate
- **v2.1.6** (heute / morgen) — Cloud-Hänger-Fix (URLSession-Timeout),
  API-Key-Validation, Prüfen-Button-Entfernung, Default Lokal
- **v2.1.7+** — bei weiteren Tester-Funden

### v2.2 (entfällt als eigene Major-Version)
Ursprünglich geplant für Personalisierung (Cluster 1–10). Diese Features
wandern in **v3.0** als Teil des „komplett-lokal-fähig"-Sprungs. Die
v2.2-Foundation-Arbeit von 2026-04-29 bleibt im Branch
`feat/v2.2-foundation` als Vorarbeit für v3.0 erhalten.

### v3.0 — Komplett-Lokal-Fähigkeit (Ziel: Q3 2026)
**Großer Sprung** mit zwei verbundenen Themen:
1. **Personalisierung** (alle 10 Cluster aus dem April-Brainstorm)
2. **Lokales LLM** als Opt-in-Alternative zu OpenAI-Cloud

Damit erfüllen wir das Manifest-Versprechen „lokal und loyal" vollständig.
User können wählen: schnellste Cloud-Qualität oder vollständig offline.

---

## Hardware-Strategie für v3.0 (lokales LLM)

Whisper bleibt Speech-to-Text. Für das Rewriting (Polite/Adaptive/Custom
Modes/Prompt-Optimizer) brauchen wir ein lokales LLM. Apple Silicon mit
Unified Memory ist der Idealfall — keine VRAM-Trennung, jeder M-Chip
kann LLMs ausführen, wenn genug RAM da ist.

### Hardware-Tiers — Auto-Detection beim App-Start

| Tier | RAM | Modell | Empfohlen für |
|---|---|---|---|
| **Cloud-only** | jede | Kein lokales LLM | Default — beste Qualität, niedrigste Latenz |
| **Lokal-Light** | 8 GB | Llama 3.2 3B (4-bit, ~2 GB) | Mac mit knappem RAM, will kostenfrei + offline |
| **Lokal-Full** | 16 GB | Qwen 2.5 7B (4-bit, ~5 GB) | Standard-Pro-User, beste Qualitäts-Balance |
| **Lokal-Premium** | 32 GB+ | Llama 3.1 8B oder Qwen 2.5 14B | Power-User, maximale lokale Qualität |

### Toggle-Lock-Logik (UI-Verhalten)

In Settings → Modus → „Lokales LLM aktivieren":

```
1. Beim App-Start: SystemCheck.evaluate() liefert tier ∈ {cloudOnly, light, full, premium}
2. UI-Toggle „Lokales LLM" zeigt:
   - tier = cloudOnly → Toggle deaktiviert (grau, nicht klickbar)
     + Hinweis: „Dein Mac hat 8 GB RAM. Lokales LLM braucht mindestens 8 GB
        UND ein Apple-Silicon-Chip. Bitte Cloud-Modus nutzen."
   - tier = light → Toggle aktivierbar, beim Aktivieren Modell-Auswahl auf 3B
     + Hinweis: „Wir nutzen Llama 3.2 3B (~2 GB Modell, ~3 GB RAM-Bedarf
        während der Nutzung). Etwas geringere Qualität als Cloud,
        aber komplett offline."
   - tier = full → Modell-Auswahl auf 7B als Default + 3B als Light-Option
     + Hinweis: „Wir nutzen Qwen 2.5 7B. Qualität nahe an Cloud,
        ~6 GB RAM während aktiver Nutzung."
   - tier = premium → freie Modell-Auswahl 3B/7B/8B/14B
3. Aktiviertes lokales LLM lädt das Modell beim ersten Diktat in den
   Speicher (~2–10 Sek), bleibt dann residenten Speicher.
4. Klarer Hinweis im UI: „Lokales LLM blockiert dauerhaft X GB RAM.
   Andere Apps haben weniger Speicher zur Verfügung."
```

### Default-Verhalten

- **Auslieferungs-Default:** Cloud (OpenAI). Beste Qualität, niedrigste
  Latenz, geringster RAM-Footprint. Der typische User aktiviert lokal nie.
- **Power-User-Pfad:** Toggle in Settings → System-Check entscheidet,
  ob Aktivierung erlaubt ist.
- **Privacy-Marketing:** Wir bewerben Cloud-vs-Lokal als bewusste Wahl,
  nicht als Default-Eigenschaft. Manifest-Punkt „lokal optional"
  erfüllt.

### Modell-Distribution

- Modelle werden **NICHT** in die App gebündelt (DMG bliebe sonst >5 GB)
- Erst-Download beim ersten Aktivieren des lokalen Modus, mit Fortschrittsanzeige
- Speicherort: `~/Library/Application Support/ALVA-TEXT/models/`
- Format: GGUF (llama.cpp-kompatibel) oder MLX (Apple-native)
- Empfehlung: **MLX-LM** (Apple's Framework, optimiert für Apple Silicon)

### Prompt-Optimizer-Hotkey (v3.0-Feature)

Der separate Hotkey für Prompt-Generation (markierter Text → strukturierter
Profi-Prompt) braucht Prompt-Engineering-Qualität. **3B-Modelle reichen
knapp**, sind okay für einfache Prompts. **Bessere Qualität ab 7B**
(Llama 3.1 / Qwen 2.5) für komplexe Prompts mit mehreren Constraints.

→ Empfehlung: Prompt-Optimizer ist im **Lokal-Full-Tier (16 GB)** oder
**Cloud-Modus** verfügbar. Auf 8-GB-Macs nur Cloud-Variante.

---

## v2.1.6 — Konkreter Hotfix-Plan (heute)

**Vier chirurgische Edits, alle gleichzeitig committed, ein Build, ein Test:**

| # | Bug-ID | Edit | Datei |
|---|---|---|---|
| 1 | (neu) | URLSession-Timeout auf 30 s (Transcribe) + 10 s (Chat) | `OpenAIService.swift` |
| 2 | #B17 | Default-Modus `.auto` → `.local` | `AppCoordinator.swift` |
| 3 | #B16 | Prüfen-Button entfernen | `SettingsView.swift` |
| 4 | #B14 | API-Key-Validation async im didSet | `AppCoordinator.swift` |

**Versionsbump:** 2.1.5 → 2.1.6 (Build 25 → 26)

---

## Tester-Roll-out (nach v2.1.6 erfolgreich getestet)

1. v2.1.6-DMG auf GitHub Releases als „Latest" markieren
2. Begleit-Mail an die fünf Erstgenannten (Conny, Vivi, Marius, Tobias, Sven)
3. Klares Erwartungs-Setting in der Mail:
   - „Beta-Software, gibt noch Bugs"
   - „Bei Problemen Console-Logs schicken (Filter „ALVA")"
   - „v2.2 entfällt — der nächste große Release ist v3.0 mit Personalisierung"

---

*Letzte Änderung: 2026-05-03, basierend auf Hardware-Recherche
+ strategischer Diskussion mit Alper.*
