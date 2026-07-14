#!/usr/bin/env bash
# Smoke-check a Superset journey deployment (run after azd up; needs kubectl).
set -euo pipefail

echo "=== verify-superset ==="
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found"
  exit 1
fi

echo "Pods in namespace superset:"
kubectl get pods -n superset

# Ready column is READY like "1/1" or "0/1". awk has no \1 backrefs — compare sides of "/".
not_ready=$(kubectl get pods -n superset --no-headers 2>/dev/null | awk '
{
  ready = $2
  status = $3
  split(ready, parts, "/")
  if (parts[1] != parts[2] || status != "Running") print
}
' || true)
if [[ -n "${not_ready:-}" ]]; then
  echo "FAIL: one or more pods not Ready/Running:"
  echo "$not_ready"
  exit 1
fi

URL=$(azd env get-value SUPERSET_URL 2>/dev/null || true)
if [[ -z "${URL:-}" ]]; then
  echo "ERROR: SUPERSET_URL not set"
  exit 1
fi
URL=${URL%/}

echo "Health: $URL/health"
code=$(curl -sS -o /tmp/superset-health.txt -w "%{http_code}" --max-time 60 "$URL/health" || true)
echo "HTTP $code"
cat /tmp/superset-health.txt 2>/dev/null || true
echo
if [[ "$code" != "200" ]]; then
  echo "FAIL: expected HTTP 200 from /health"
  exit 1
fi

POD=$(kubectl get pods -n superset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "${POD:-}" ]]; then
  echo "FAIL: no Superset pod found"
  exit 1
fi

echo "Checking DB engine (must be PostgreSQL, not SQLite)..."
# Init container logs (migrations) and main container logs
logs=$(
  {
    kubectl logs -n superset "$POD" -c superset-init 2>/dev/null || true
    kubectl logs -n superset "$POD" -c superset 2>/dev/null || true
    # common alternate container names
    kubectl logs -n superset "$POD" 2>/dev/null || true
  } | tail -n 500
)

if echo "$logs" | grep -qi "SQLiteImpl\|sqlite:////\|sqlite:///"; then
  echo "FAIL: SQLite detected in logs — psycopg2/config likely missing (silent fallback)"
  echo "$logs" | grep -i "sqlite\|postgres" | tail -n 20 || true
  exit 1
fi

if ! echo "$logs" | grep -qi "PostgresqlImpl\|postgresql://\|postgres://"; then
  echo "FAIL: no PostgreSQL evidence in pod logs (expected PostgresqlImpl or postgres URI)"
  echo "      Tip: kubectl logs -n superset $POD -c superset-init | grep -i postgres"
  exit 1
fi

echo "OK: PostgreSQL evidence found; no SQLite fallback"
echo "Open: $URL"
