#!/bin/bash
# Direkt-Test: Ist der API-Key, den ALVA aus dem Keychain liest, bei OpenAI gültig?

set -u

echo ""
echo "════════════════════════════════════════════════════════"
echo " OpenAI-Key-Diagnose"
echo "════════════════════════════════════════════════════════"

# Key aus Keychain holen (kann ein Auth-Dialog erscheinen)
echo ""
echo "[1/3] Key aus macOS-Keychain lesen …"
KEY=$(security find-generic-password -s com.adserica.alvatext -a openaiApiKey -w 2>/dev/null)
if [ -z "$KEY" ]; then
    echo "       ❌ Kein Key im Keychain unter (com.adserica.alvatext / openaiApiKey)"
    echo "       Heißt: ALVA hat den Key nicht gefunden. Das wäre Ursache."
    exit 1
fi
echo "       ✓ Key gefunden (${KEY:0:7}…${KEY: -4}, Länge ${#KEY})"

# Test 1: Kann der Key überhaupt mit OpenAI sprechen?
echo ""
echo "[2/3] Test gegen OpenAI /v1/models …"
HTTP=$(curl -s -o /tmp/openai-models.json -w "%{http_code}" --max-time 10 \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    https://api.openai.com/v1/models)
echo "       HTTP $HTTP"

case "$HTTP" in
    200)
        echo "       ✓ Auth funktioniert. Account ist aktiv, Key ist gültig."
        ;;
    401)
        echo "       ❌ 401 Unauthorized — Key ungültig oder abgelaufen."
        echo "       Auf platform.openai.com einen neuen Key generieren."
        cat /tmp/openai-models.json 2>/dev/null
        exit 2
        ;;
    429)
        echo "       ⚠ 429 Rate-Limit — ungewöhnlich an /models. Account-Issue?"
        cat /tmp/openai-models.json 2>/dev/null
        exit 3
        ;;
    *)
        echo "       ❌ Unerwartet — Antwort:"
        cat /tmp/openai-models.json 2>/dev/null
        exit 4
        ;;
esac

# Test 2: Funktioniert ein echter Chat-Completion-Call (das ist was Polite/Adaptive macht)?
echo ""
echo "[3/3] Test gegen OpenAI Chat-Completions (gpt-4o-mini) …"
RESP=$(curl -s --max-time 15 \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Sag nur OK."}],"max_tokens":5}' \
    https://api.openai.com/v1/chat/completions)

HTTP_CHAT=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Sag nur OK."}],"max_tokens":5}' \
    https://api.openai.com/v1/chat/completions)

echo "       HTTP $HTTP_CHAT"
case "$HTTP_CHAT" in
    200)
        echo "       ✓ Chat-Completion klappt. Antwort-Auszug:"
        echo "$RESP" | python3 -c "import sys, json; d=json.load(sys.stdin); print('       →', d.get('choices',[{}])[0].get('message',{}).get('content',''))" 2>/dev/null || echo "$RESP" | head -c 200
        ;;
    401)
        echo "       ❌ 401 — Key gültig für /models aber nicht für Chat. Account-Permission-Issue."
        echo "$RESP" | head -c 400
        ;;
    429)
        echo "       ⚠ 429 — Rate-Limit oder Quota verbraucht / kein Guthaben."
        echo "$RESP" | head -c 400
        ;;
    *)
        echo "       ❌ Unerwartet:"
        echo "$RESP" | head -c 400
        ;;
esac

echo ""
echo "════════════════════════════════════════════════════════"
echo " Interpretation:"
echo "   • Test 2 = 200, Test 3 = 200 → API-Key OK, Bug woanders im App-Code"
echo "   • Test 2 = 200, Test 3 = 429 → Quota/Guthaben aufgebraucht"
echo "   • Test 2 = 401 → Key ist ungültig, neu generieren"
echo "════════════════════════════════════════════════════════"
