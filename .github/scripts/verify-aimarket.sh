#!/usr/bin/env bash
# Smoke-check an AIMarket journey deployment (run after azd up).
# Invoke from repo root or any journey folder; requires an active azd env with outputs.
set -euo pipefail

echo "=== verify-aimarket ==="
API_URL=$(azd env get-value API_URL 2>/dev/null || true)
WEB_URL=$(azd env get-value WEB_URL 2>/dev/null || true)

if [[ -z "${API_URL:-}" ]]; then
  echo "ERROR: API_URL not set (run azd up in the AIMarket environment first)"
  exit 1
fi
if [[ -z "${WEB_URL:-}" ]]; then
  echo "ERROR: WEB_URL not set — frontend output required for integration check"
  exit 1
fi

API_URL=${API_URL%/}
WEB_URL=${WEB_URL%/}
# Host only, for searching inside built JS (with or without https)
API_HOST=$(echo "$API_URL" | sed -E 's|^https?://||' | cut -d/ -f1)

echo "1) Health: $API_URL/api/health"
code=$(curl -sS -o /tmp/aimarket-health.json -w "%{http_code}" --max-time 60 "$API_URL/api/health" || true)
echo "   HTTP $code"
if [[ "$code" != "200" ]]; then
  echo "FAIL: health"
  exit 1
fi

echo "2) Products: $API_URL/api/products"
curl -sS --max-time 60 "$API_URL/api/products" | python3 -c "
import sys, json
d=json.load(sys.stdin)
if isinstance(d, list):
  n=len(d)
elif isinstance(d, dict):
  n=d.get('totalCount', len(d.get('data', [])))
else:
  n=0
print(f'   products ~{n}')
if n < 1:
  sys.exit(1)
" || { echo "FAIL: products"; exit 1; }

echo "3) Frontend shell: $WEB_URL"
wcode=$(curl -sS -o /tmp/aimarket-index.html -w "%{http_code}" --max-time 60 "$WEB_URL" || true)
echo "   HTTP $wcode"
if [[ "$wcode" != "200" ]]; then
  echo "FAIL: web shell"
  exit 1
fi

echo "4) Frontend→API integration (built assets must reference API host)"
# Relative /api on the web host must NOT be the production API (SPA shell returns HTML)
rel_ct=$(curl -sS -o /tmp/aimarket-rel.txt -w "%{content_type}" --max-time 30 \
  "$WEB_URL/api/products" 2>/dev/null || true)
if echo "${rel_ct:-}" | grep -qi 'application/json'; then
  echo "WARN: $WEB_URL/api/products returned JSON — unexpected for separate Container Apps"
fi

# Find hashed JS bundles from index.html and require API host (or full /api base) in at least one
python3 - "$WEB_URL" "$API_HOST" "$API_URL" <<'PY'
import re, sys, urllib.request

web, api_host, api_url = sys.argv[1], sys.argv[2], sys.argv[3]
html = open("/tmp/aimarket-index.html", encoding="utf-8", errors="replace").read()
# script src="/assets/index-xxx.js") or src='...'
srcs = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html, flags=re.I)
if not srcs:
    # Vite sometimes inlines; also check modulepreload
    srcs = re.findall(r'href=["\']([^"\']+\.js)["\']', html, flags=re.I)
if not srcs:
    print("FAIL: no JS assets found in index.html — cannot verify VITE_API_URL bake-in")
    sys.exit(1)

def abs_url(src: str) -> str:
    if src.startswith("http"):
        return src
    if src.startswith("/"):
        return web.rstrip("/") + src
    return web.rstrip("/") + "/" + src

needles = [api_host, api_url.rstrip("/") + "/api", api_url.rstrip("/") + "/api/"]
found = False
checked = 0
for src in srcs[:8]:
    url = abs_url(src)
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            body = r.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"   skip {url}: {e}")
        continue
    checked += 1
    if any(n in body for n in needles if n):
        found = True
        print(f"   OK: API host found in {src}")
        break

if checked == 0:
    print("FAIL: could not download any JS assets")
    sys.exit(1)
if not found:
    print(f"FAIL: none of {checked} JS asset(s) contain API host '{api_host}'.")
    print("      VITE_API_URL was probably not set at build time — run postdeploy hook.")
    sys.exit(1)
PY

echo "5) Optional search (warn only if empty/index missing):"
scode=$(curl -sS -o /tmp/aimarket-search.json -w "%{http_code}" --max-time 60 \
  -X POST "$API_URL/api/products/search" \
  -H "Content-Type: application/json" \
  -d '{"query":"laptop"}' || true)
echo "   HTTP $scode"

echo "OK: AIMarket API + frontend integration checks passed"
echo "API: $API_URL"
echo "WEB: $WEB_URL"
