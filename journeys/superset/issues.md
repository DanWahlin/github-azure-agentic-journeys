# Superset AKS Journey — Issues Log

| Date | Phase | Error | Diagnosis | Fix/Workaround | Final status |
|------|-------|-------|-----------|----------------|--------------|
| 2026-07-16 | Prereq | `helm: command not found` — Helm not installed, required by postprovision hook to install NGINX ingress. | Runner image lacked Helm. | Installed Helm v3 via official get-helm-3 script before deploying. | Resolved |
| 2026-07-16 | Verify (screenshot) | Playwright MCP: `Chromium distribution 'chrome' is not found`; then Node script needed browser. | No browser installed in runner. | Ran `npm i playwright` + `npx playwright install chromium` and used a local Node screenshot script with `--no-sandbox`. | Resolved |
| 2026-07-16 | Verify (login) | Playwright `TimeoutError` on `input[name="username"]`. | Superset login form is React-rendered; fields expose `id` (username/password), not `name`. | Switched selectors to `#username`/`#password` and `button:has-text("Sign in")`; login succeeded to /superset/welcome/. | Resolved |

## 2026-07-17 — Repository remediation

- Helm 3, `kubectl`, Node.js 24 LTS, and `azd` 1.28+ are explicit prerequisites with Windows, macOS, and Linux installation guidance.
- Deployment now requires `infra-superset/hooks/postprovision.mjs` instead of a host-specific shell hook.
- Browser verification pins bundled Chromium and the working login selectors, then waits for `/superset/welcome/`.
- **Status:** Documentation, skill, and runner defects resolved.
