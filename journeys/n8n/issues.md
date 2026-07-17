# n8n Journey — Issues Log

## 2026-07-16 — Screenshot capture: Playwright browser not available

- **Phase:** Verification / screenshot capture
- **Observed error:** Playwright MCP browser failed with `Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome`. A standalone Node script in `/tmp` also failed with `Cannot find module 'playwright'`.
- **Diagnosis:** MCP browser was set to launch system Chrome (not installed; bundled Chromium builds exist under `~/.cache/ms-playwright`). Node also cannot resolve `node_modules` for a script outside the project tree.
- **Fix/workaround:** Installed `playwright` in the working directory and ran a screenshot script from that directory using bundled Chromium, navigating to `N8N_URL` with `waitUntil: 'networkidle'`. Saved `screenshot-n8n.png`; removed temp npm artifacts afterward.
- **Final status:** Resolved — screenshot captured (n8n owner-setup page, title "n8n.io - Workflow Automation").

## 2026-07-16 — Note: n8n ignores legacy N8N_BASIC_AUTH_* variables

- **Phase:** Verification
- **Observed:** With `N8N_BASIC_AUTH_ACTIVE/USER/PASSWORD` set, the live UI shows the "Set up owner account" page rather than HTTP basic auth.
- **Diagnosis:** Current `n8nio/n8n:latest` uses built-in user management and no longer honors the deprecated basic-auth env vars. Expected upstream behavior, not a deployment defect.
- **Fix/workaround:** None required. Health endpoint and UI both return HTTP 200 and the page title contains "n8n", satisfying all success criteria.
- **Final status:** Informational — no impact on success criteria.

## 2026-07-17 — Repository remediation

- Legacy `N8N_BASIC_AUTH_*` variables and their secret were removed from the README and associated skill references.
- The first-run owner-account flow is now an explicit browser acceptance criterion; HTTP 401 is no longer accepted as proof.
- The image is pinned to `n8nio/n8n:2.30.6`, locally verified on Linux ARM64 with `/healthz` HTTP 200 and a rendered n8n UI.
- The post-provision hook path is consistently `infra-n8n/hooks/postprovision.mjs`.
- **Status:** Documentation and skill defects resolved.
