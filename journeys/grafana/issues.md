# Grafana Journey — Issues Log

## 2026-07-16 — azd authentication token expired

- **Phase:** Validation (`azd provision --preview`)
- **Observed error:** `AADSTS700082: The refresh token has expired due to inactivity ... Suggestion: reauthentication required, run 'azd auth login'`. azd exited with code 1 before any preview ran.
- **Diagnosis:** azd maintains its own credential store, separate from the Azure CLI. The Azure CLI session was still valid, but azd's cached refresh token had expired after 90 days of inactivity. Interactive `azd auth login` was not possible in this non-interactive run.
- **Fix/workaround:** Configured azd to reuse the authenticated Azure CLI credential: `azd config set auth.useAzCliAuth true`. Re-ran the preview and deployment successfully without an interactive login.
- **Final status:** Resolved. Deployment and all verification completed.

## 2026-07-16 — Playwright Chrome channel unavailable on Linux Arm64

- **Phase:** Verification (browser screenshot)
- **Observed error:** Playwright MCP failed with `Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome`; `npx playwright install chrome` then failed with `ERROR: not supported on Linux Arm64`.
- **Diagnosis:** The stable Google Chrome channel has no Arm64 Linux build. The Playwright MCP server was pinned to the `chrome` channel, which cannot be installed on this architecture.
- **Fix/workaround:** Installed the bundled Playwright Chromium (`npx playwright install chromium`) and captured the screenshot with a small local Node script using `chromium.launch()` (the pattern documented in the journey-runner skill). Full-page screenshot of the Grafana login page saved successfully.
- **Final status:** Resolved. `screenshot-grafana.png` captured and verified.

## 2026-07-17 — Repository remediation

- The Grafana README and skill now list Node.js 24 LTS for portable verification and avoid OpenSSL and Bash command substitution.
- `journey-runner` now checks Azure CLI and `azd` authentication separately, enables Azure CLI authentication reuse, and stops on an unsupported `azd` version.
- Screenshot tooling is pinned locally and launches bundled Playwright Chromium on Windows, macOS, and Linux.
- **Status:** Documentation and runner defects resolved; no Azure redeployment was required for these changes.
