#!/usr/bin/env bash
# Smoke-check a Grafana journey deployment (run after azd up).
# Invoke from repo root or any journey folder; requires active azd env outputs.
set -euo pipefail

echo "=== verify-grafana ==="
URL=$(azd env get-value GRAFANA_URL 2>/dev/null || true)
if [[ -z "${URL:-}" ]]; then
  echo "ERROR: GRAFANA_URL not set. Run from an azd environment that deployed Grafana."
  exit 1
fi
URL=${URL%/}

echo "Health: $URL/api/health"
code=$(curl -sS -o /tmp/grafana-health.json -w "%{http_code}" --max-time 60 "$URL/api/health" || true)
echo "HTTP $code"
cat /tmp/grafana-health.json 2>/dev/null || true
echo
if [[ "$code" != "200" ]]; then
  echo "FAIL: expected HTTP 200 from /api/health (cold start? retry in 60s)"
  exit 1
fi
if ! grep -q '"database"' /tmp/grafana-health.json 2>/dev/null; then
  echo "WARN: response missing database field — still check browser login"
fi
echo "OK: Grafana health endpoint responded"
echo "Open: $URL"
