#!/usr/bin/env bash
# Sends one request to the Claude API using the same shape the app uses
# (strict tool call, adaptive thinking, server-side fallbacks) with the key
# from App/Config/Secrets.xcconfig. Use it to confirm the key and request
# format work before testing model features in the app.
#
#   scripts/check-claude.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/App/Config/Secrets.xcconfig"
BASE="$ROOT/App/Config/Base.xcconfig"

[ -f "$SECRETS" ] || { echo "Missing $SECRETS — copy Secrets.example.xcconfig and add your key."; exit 1; }

KEY=$(sed -n 's/^ANTHROPIC_API_KEY *= *//p' "$SECRETS" | tr -d '[:space:]')
MODEL=$(sed -n 's/^CLAUDE_MODEL *= *//p' "$BASE" | tr -d '[:space:]')
MODEL=${MODEL:-claude-opus-5}

[[ -n "$KEY" && "$KEY" != sk-ant-... ]] || { echo "ANTHROPIC_API_KEY is empty or still the placeholder in $SECRETS"; exit 1; }

echo "Model: $MODEL"
echo "Key:   ${KEY:0:12}…"

RESPONSE=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: server-side-fallback-2026-07-01" \
  -d @- <<JSON
{
  "model": "$MODEL",
  "max_tokens": 1024,
  "thinking": {"type": "adaptive"},
  "output_config": {"effort": "low"},
  "fallbacks": "default",
  "system": "Convert the message into a recipe search by calling set_search_query exactly once.",
  "tools": [{
    "name": "set_search_query",
    "description": "Set the structured recipe filter.",
    "strict": true,
    "input_schema": {
      "type": "object",
      "properties": {
        "exclude_ingredients": {"type": "array", "items": {"type": "string"}},
        "min_protein": {"type": ["number", "null"]},
        "max_minutes": {"type": ["integer", "null"]}
      },
      "required": ["exclude_ingredients", "min_protein", "max_minutes"],
      "additionalProperties": false
    }
  }],
  "tool_choice": {"type": "auto"},
  "messages": [{"role": "user", "content": "high protein dinner, no dairy, under 30 minutes"}]
}
JSON
)

python3 - "$RESPONSE" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
if "error" in r:
    print("API error:", r["error"].get("type"), "-", r["error"].get("message"))
    sys.exit(1)
print("stop_reason:", r.get("stop_reason"))
print("served by:  ", r.get("model"))
calls = [b for b in r.get("content", []) if b.get("type") == "tool_use"]
if not calls:
    text = " ".join(b.get("text", "") for b in r.get("content", []) if b.get("type") == "text")
    print("No tool call in the response. Text:", text[:300])
    sys.exit(1)
print("tool input: ", json.dumps(calls[0]["input"]))
u = r.get("usage", {})
print(f"tokens:      {u.get('input_tokens')} in / {u.get('output_tokens')} out")
print("OK — the app's request shape works with this key.")
PY
