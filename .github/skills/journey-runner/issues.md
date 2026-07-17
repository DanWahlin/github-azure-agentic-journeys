# Journey Runner Issues

## 2026-07-17 — Non-interactive Copilot helper omitted required permissions

- **Phase:** Runner Step 3, Copilot invocation
- **Observed:** `copilot -p` could read the journey file in its working directory but returned `Permission denied and could not request permission from user` for parent skills and executable commands such as `node --version`.
- **Cause:** Prompt mode is non-interactive. `run-copilot-prompt.mjs` passed only `-p`, so Copilot couldn't request tool, URL, or parent-directory approval after startup.
- **Fix:** Added explicit `--allow-dir`, `--allow-all-tools`, and `--allow-all-urls` options to the wrapper and documented them in the runner skill. These remain opt-in rather than silently granting access.
- **Verification:** A smoke prompt read the parent `journey-runner/SKILL.md`, executed `node --version`, and returned `PERMISSIONS_OK v24.13.0` with exit code 0.
- **Status:** Resolved and integrated. The permission-aware helper was used throughout the five-journey campaign, including the repaired clean-environment reruns.
