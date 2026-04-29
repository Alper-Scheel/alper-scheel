#!/usr/bin/env bash
# AdLuna — Cloudflare Pages Deploy
# ------------------------------------------------------------
# Voraussetzungen:
#   - Node.js installiert (brew install node)
#   - Beim ERSTEN Lauf: `npx wrangler login` einmal ausführen (öffnet Browser)
#   - Danach reicht ./deploy.sh
# ------------------------------------------------------------

set -e
cd "$(dirname "$0")"

echo "[1/3] Versionscheck..."
node --version || { echo "Node.js fehlt — bitte 'brew install node' laufen lassen."; exit 1; }

echo "[2/3] Lokaler Smoke-Test (Datei-Existenz)..."
for f in index.html produkte.html impressum.html datenschutz.html agb.html lizenzen.html manifest.html ai-act.html admed.html alva-text.html alva-text-manual.html styles-v3.css styles.css _headers _redirects robots.txt sitemap.xml; do
    [ -f "$f" ] || { echo "FEHLT: $f"; exit 1; }
done
echo "  → alle Dateien vorhanden"

echo "[3/3] Deploy zu Cloudflare Pages (Projekt: adluna)..."
# WICHTIG: Branch-Name muss exakt mit dem im CF-Dashboard hinterlegten
# "Production branch" übereinstimmen, sonst wird's nur ein Preview-Deploy.
# Default bei direct-uploads ohne Git ist "main". Falls das Pages-Projekt
# einen anderen Production-Branch hat: BRANCH-Variable überschreiben.
BRANCH="${ADLUNA_BRANCH:-main}"
echo "  → Deploy auf Branch: $BRANCH"
npx --yes wrangler@latest pages deploy . \
    --project-name adluna \
    --branch "$BRANCH" \
    --commit-dirty true

echo ""
echo "✅ Deploy fertig."
echo "   Standard-URL:    https://adluna.pages.dev"
echo "   Custom-Domain:   https://adluna.de  (im CF-Dashboard verbinden, falls noch nicht)"
