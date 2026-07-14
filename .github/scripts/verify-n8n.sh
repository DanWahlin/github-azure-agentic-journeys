#!/usr/bin/env bash
# Smoke-check an n8n journey deployment (run after azd up).
# Invoke from repo root or any journey folder; requires active azd env outputs.
set -euo pipefail

echo "=== verify-n8n ==="
URL=$(azd env get-value N8N_URL 2>/dev/null || true)
if [[ -z "${URL:-}" ]]; then
  echo "ERROR: N8N_URL not set. Run from an azd environment that deployed n8n."
  exit 1
fi
URL=${URL%/}

echo "Waiting for /healthz (up to ~5 min)..."
ok=0
for i in $(seq 1 30); do
  code=$(curl -k -sS -o /tmp/n8n-health.txt -w "%{http_code}" --max-time 20 "$URL/healthz" || true)
  if [[ "$code" == "200" ]]; then
    ok=1
    break
  fi
  echo "  attempt $i/30 status=$code"
  sleep 10
done

if [[ "$ok" != "1" ]]; then
  echo "FAIL: /healthz never returned 200"
  exit 1
fi
echo "OK: /healthz HTTP 200"

ui=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 "$URL" || true)
echo "UI HTTP $ui"
if [[ "$ui" != "200" && "$ui" != "401" ]]; then
  echo "WARN: UI status $ui (401 may mean basic auth is required — still OK)"
fi
echo "Open: $URL"
