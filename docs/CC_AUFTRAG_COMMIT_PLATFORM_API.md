---
auftrag: Git-Commit fuer Platform-API + ALVA-TEXT License-Client
empfaenger: Claude Code (CC)
auftraggeber: Alper Scheel
erstellt: 2026-04-23 10:45 MEZ
prioritaet: P1 — Code ist fertig und verifiziert, jetzt versioniert
laufzeit: 2 min
---

# Auftrag: Atomic Commit der Platform-API-Integration

## Kontext

Cowork hat in einer langen Session den kompletten License-Server-Stack + Swift-Client-Integration gebaut, End-to-End getestet (api.adluna.de ist live, Aktivierungs-Mail kommt via Resend, Verify liefert Token, Admin-Stats zeigen `verified_users:1, active_devices:1`).

Jetzt soll das Ganze als **ein** sauberer atomarer Commit ins Repo.

## Deine Aufgabe

1. `cd ~/codex-work/alper-scheel`
2. Den unten stehenden Stage-Befehl ausfuehren (**gezielt**, kein `git add .` — sonst landet `.env` drin!)
3. Pruefen: `git status --short` zeigt nur gruene staged changes, keine untracked `.env`
4. Mit der unten stehenden Message committen (HEREDOC)
5. `git log --oneline -3` zeigen
6. **NICHT pushen** — Alper pusht manuell, wenn er will

## Stage-Befehl

```bash
git add .gitignore \
        services/ \
        docs/deploy-platform-api.sh \
        docs/ADLUNA_DNS_SETUP.md \
        docs/LICENSE_SERVER_DESIGN.md \
        docs/CC_AUFTRAG_PLATFORM_API_SERVICE_FIX.md \
        docs/CC_AUFTRAG_COMMIT_PLATFORM_API.md \
        ALVA-TEXT/ALVA_TEXT.xcodeproj/project.pbxproj \
        ALVA-TEXT/ALVA_TEXT/AppCoordinator.swift \
        ALVA-TEXT/ALVA_TEXT/AppDelegate.swift \
        ALVA-TEXT/ALVA_TEXT/SettingsView.swift \
        ALVA-TEXT/ALVA_TEXT/StatusMenuController.swift \
        ALVA-TEXT/ALVA_TEXT/LicenseClient.swift \
        ALVA-TEXT/ALVA_TEXT/LicenseState.swift \
        ALVA-TEXT/ALVA_TEXT/ActivationView.swift \
        ALVA-TEXT/ALVA_TEXT/MenuHeaderView.swift
```

## Sanity-Check vor Commit

```bash
git status --short
# Muss zeigen: keine `.env`, keine xcuserdata
# Falls .env auftaucht: SOFORT ABBRECHEN, Alper informieren
grep -c "RESEND_API_KEY\|ADLUNA_ADMIN_TOKEN" services/adluna-platform-api/.env.example
# Muss 0 oder 2 sein, aber NIEMALS echte Token-Werte
```

## Commit-Message

```bash
git commit -F- <<'MSG'
AdLuna Platform API + ALVA-TEXT License-Client

Infrastruktur (services/adluna-platform-api/):
- FastAPI-Server mit Product/User/Device/License/ActivationCode/ServerConfig
- Endpoints: /v1/activation/{request,verify}, /v1/license/check,
  /v1/device/{list,revoke}, /v1/webhook/paddle (stub), /v1/admin/*
- SQLite im WAL-Mode, Alembic-Migrations, Seed fuer ALVA-TEXT-Product
- Resend-Integration fuer Aktivierungs-Mails (no-reply@mail.adluna.de)
- Kill-Switch via server_config.beta_mode_global
- Dockerfile + docker-compose.yml + README fuer lokales Dev
- Deploy-Skript docs/deploy-platform-api.sh (rsync + venv + alembic + seed)

ALVA-TEXT Client-Integration:
- LicenseClient.swift: async/await HTTP-Client gegen api.adluna.de,
  Keychain-basierte Token-Persistenz, Device-UUID-Stabilitaet
- LicenseState.swift: ObservableObject mit Phase-Logik (.loading /
  .active / .expired / .revoked / .error), Daily-Check-Timer
- ActivationView.swift: Zwei-Schritt-Flow Email -> 6-stelliger Code
- MenuHeaderView.swift: Gravatar + Email + Aktiv-Toggle im Status-Menu
  (analog Tailscale-Header)
- AccountTab in SettingsView: Lizenzstatus, Trial-Countdown,
  Aktivieren/Abmelden, Jetzt-pruefen
- AppCoordinator.isPaused -> gated hotkeyStart /
  reverseTranslateRequested / hotkeySelectLanguage; laufende Aufnahmen
  duerfen normal beendet werden

Doku:
- docs/LICENSE_SERVER_DESIGN.md aktualisiert
- docs/ADLUNA_DNS_SETUP.md (Cloudflare + Resend DNS-Cascade)
- docs/CC_AUFTRAG_PLATFORM_API_SERVICE_FIX.md (Service-Bootstrap)
- docs/CC_AUFTRAG_COMMIT_PLATFORM_API.md (dieser Auftrag)

Secrets:
- .env gitignored (RESEND_API_KEY + ADLUNA_ADMIN_TOKEN liegen lokal
  auf MS512 in /Users/ms512/services/adluna-platform-api/.env)

End-to-End verifiziert: api.adluna.de/health -> 200,
Aktivierungs-Mail via Resend zugestellt, Verify liefert Token,
Admin-Stats zeigen verified_users:1, active_devices:1.
MSG
```

## Rueckmeldung an Alper

Kurz:
1. Commit-SHA (erste 7 Zeichen)
2. `git log --oneline -3` Output
3. Blocker / Warnungen, falls was war

## Regeln

- KEIN `git push` (Alper macht das selbst bei Bedarf)
- KEIN `--amend` (neuer Commit, kein Rewrite)
- KEIN `git add .` oder `git add -A` (Secrets-Risiko)
- Wenn `.env` in staged area auftaucht: ABBRUCH, Alper sofort informieren
- Wenn Pre-Commit-Hook (lint, test) scheitert: Fehler melden, nicht `--no-verify`
