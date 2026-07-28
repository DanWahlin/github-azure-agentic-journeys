# Journey Runner Issues

## 2026-07-17 — Non-interactive Copilot helper omitted required permissions

- **Phase:** Runner Step 3, Copilot invocation
- **Observed:** `copilot -p` could read the journey file in its working directory but returned `Permission denied and could not request permission from user` for parent skills and executable commands such as `node --version`.
- **Cause:** Prompt mode is non-interactive. `run-copilot-prompt.mjs` passed only `-p`, so Copilot couldn't request tool, URL, or parent-directory approval after startup.
- **Fix:** Added explicit `--allow-dir`, `--allow-all-tools`, and `--allow-all-urls` options to the wrapper and documented them in the runner skill. These remain opt-in rather than silently granting access.
- **Verification:** A smoke prompt read the parent `journey-runner/SKILL.md`, executed `node --version`, and returned `PERMISSIONS_OK v24.13.0` with exit code 0.
- **Status:** Resolved and integrated. The permission-aware helper was used throughout the five-journey campaign, including the repaired clean-environment reruns.

## 2026-07-28 — Prerequisite checker accepted `git` but could not execute it

- **Phase:** Runner Step 2, prerequisite validation.
- **Observed:** WeatherView requested `node,az,azd,copilot,git`, but `check-prerequisites.mjs` rejected `git` because the command registry had no Git entry.
- **Cause:** The runner documented and accepted arbitrary required-tool names without defining the executable/version arguments for Git.
- **Fix:** Added `git: ['git', ['--version']]` to the command registry.
- **Verification:** The same prerequisite invocation then passed with Git required.
- **Status:** Resolved and integrated.

## 2026-07-28 — Static Web Apps publisher cannot execute on ARM64 Linux

- **Phase:** WeatherView deployment after successful Bicep provisioning.
- **Observed:** azd downloaded Microsoft `StaticSitesClient` as an x86-64 ELF and failed with `Exec format` output on the ARM64 runner.
- **Cause:** The current Static Web Apps deployment client has no ARM64 Linux build; Bicep provisioning and content publishing are separate azd phases.
- **Fix:** Added an architecture gate to the runner and journey-template skills. ARM64 may build, test, compile Bicep, and run what-if, but the documented publish phase moves to an approved x64 host. Do not silently install privileged emulation or make local Docker a prerequisite.
- **Verification:** The runner used a temporary scoped x64 Azure publisher for this validation only, deleted it, then passed the checked-in HTTP/assets verifier and the full Playwright deployed-behavior verifier.
- **Status:** Upstream limitation documented; runner behavior corrected.
