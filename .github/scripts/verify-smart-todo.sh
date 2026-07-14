#!/usr/bin/env bash
# Smoke-check a SmartTodo API deployment (run after azd up).
# Requires AI generate-steps to succeed unless SMART_TODO_SKIP_AI=1.
set -euo pipefail

echo "=== verify-smart-todo ==="
API_URL=$(azd env get-value API_URL 2>/dev/null || true)
if [[ -z "${API_URL:-}" ]]; then
  echo "ERROR: API_URL not set (run azd up in the SmartTodo environment first)"
  exit 1
fi
API_URL=${API_URL%/}

cleanup_todo() {
  local id="${1:-}"
  if [[ -n "$id" ]]; then
    curl -sS -o /dev/null --max-time 30 -X DELETE "$API_URL/api/todos/$id" || true
  fi
}

echo "1) List todos"
code=$(curl -sS -o /tmp/st-todos.json -w "%{http_code}" --max-time 90 \
  "$API_URL/api/todos?userId=user-1" || true)
echo "   HTTP $code"
if [[ "$code" != "200" ]]; then
  echo "FAIL: list todos (managed identity / schema / cold start?)"
  cat /tmp/st-todos.json 2>/dev/null || true
  exit 1
fi

echo "2) Create todo"
create=$(curl -sS --max-time 60 -X POST "$API_URL/api/todos" \
  -H "Content-Type: application/json" \
  -d '{"title":"Verify script smoke test","userId":"user-1"}' || true)
TODO_ID=$(echo "$create" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])" 2>/dev/null || true)
if [[ -z "${TODO_ID:-}" ]]; then
  echo "FAIL: create"
  echo "$create"
  exit 1
fi
echo "   id $TODO_ID"
trap 'cleanup_todo "$TODO_ID"' EXIT

echo "3) Generate steps (AI — required for full pass)"
gcode=$(curl -sS -o /tmp/st-steps.json -w "%{http_code}" --max-time 120 \
  -X POST "$API_URL/api/todos/$TODO_ID/generate-steps" || true)
echo "   HTTP $gcode"

if [[ "${SMART_TODO_SKIP_AI:-}" == "1" ]]; then
  if [[ "$gcode" != "200" ]]; then
    echo "WARN: SMART_TODO_SKIP_AI=1 — accepting non-200 generate-steps ($gcode)"
  fi
else
  if [[ "$gcode" != "200" ]]; then
    echo "FAIL: generate-steps HTTP $gcode (set SMART_TODO_SKIP_AI=1 to skip AI check)"
    cat /tmp/st-steps.json 2>/dev/null || true
    exit 1
  fi
  python3 - <<'PY'
import json, sys
d = json.load(open("/tmp/st-steps.json"))
if isinstance(d, list):
    steps = d
elif isinstance(d, dict):
    steps = d.get("steps") or (d.get("todo") or {}).get("steps") or []
else:
    steps = []
n = len(steps)
print(f"   {n} steps")
if n < 3 or n > 7:
    print("FAIL: expected 3–7 AI-generated steps")
    sys.exit(1)
for s in steps:
    if not (s.get("title") and s.get("description")):
        print("FAIL: step missing title or description")
        sys.exit(1)
PY
fi

echo "4) Cleanup test todo"
cleanup_todo "$TODO_ID"
trap - EXIT

echo "OK: SmartTodo API (+ AI) smoke checks passed"
echo "API: $API_URL"
