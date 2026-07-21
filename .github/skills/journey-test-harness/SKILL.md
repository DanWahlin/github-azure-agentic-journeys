---
name: journey-test-harness
description: |
  Run multiple journeys as a cross-platform test suite. Discover journeys, invoke journey-runner in isolated workspaces, deploy, verify, capture screenshots, clean up only owned Azure resources, and produce a consolidated report.
  USE FOR: test all journeys, regression test, CI journey validation, nightly journey test, end-to-end journey suite, validate journeys deploy correctly.
  DO NOT USE FOR: running one journey interactively (use journey-runner), creating journeys (use journey-template), or reviewing content (use content-reviewer).
---

# Journey Test Harness

Orchestrate `journey-runner` across the selected journey directories. The harness must work on Windows, macOS, and Linux and must never delete an Azure environment merely because it appears in `azd env list`.

## Inputs

1. **Journeys**, default `all`
2. **Stack**, default Node.js/TypeScript for multi-stack journeys
3. **Deploy**, default `true`
4. **Location**, default `westus`
5. **Concurrency**, default `1`; increase only when quota, local ports, and API limits allow it

Each deployed journey uses `cleanup: after-verification` unless the user explicitly requests otherwise.

## Step 1: Discover Journeys

Use repository file-search APIs or Node.js `fs.readdir()` to find `journeys/*/README.md`. Do not use `ls | sed`, shell globs, or platform-specific path parsing.

For each journey, record:

- Folder name and absolute source path
- Journey type
- `PLAN.md` presence
- Required and optional tools from the journey prerequisite section
- Estimated cost and time
- Screenshot requirement

Filter only against the discovered folder names. Fail early for an unknown requested journey.

## Step 2: Suite Preflight

Load `journey-runner` and run its cross-platform preflight before creating any workspace or Azure resource.

The union of selected-journey requirements may include:

- Node.js 24 LTS or later
- Azure CLI and valid authentication
- `azd` 1.28.0 or later with `auth.useAzCliAuth=true`
- GitHub Copilot CLI
- Node.js 24 LTS or later for hooks, tests, and verifiers
- Azure Functions Core Tools v4, Azurite, and Go-based `sqlcmd` for SmartTodo
- The pinned Playwright package and bundled Chromium for web screenshots
- Xcode 16+ only when SmartTodo iOS execution is requested on macOS

Use `.github/skills/journey-runner/scripts/check-prerequisites.mjs` with the union of required tools. Missing required tools stop the whole suite before provider registration. Do not install system tools during the suite.

## Step 3: Azure Preparation

Check Azure CLI and `azd` authentication separately. Confirm the intended subscription and location.

Register only providers required by selected journeys. Run provider commands as individual processes with argument arrays, not shell loops. Wait for required registrations before starting the first deployment.

Record the subscription ID and each provider's state in the suite report.

## Step 4: Create Suite and Journey Workspaces

Create directories through Node.js filesystem APIs or the active agent's file tools:

```text
<journey-runs-root>/test-suite-<UTC timestamp>/
├── test-report.md
├── screenshots/
└── runs/
    └── <journey>-<UTC timestamp>/
```

Use `path.join()` and absolute paths. Don't embed `~/`, `date`, `mkdir`, or shell-specific separators in executable instructions.

Copy `PLAN.md` with `fs.copyFile()` when needed. Generated application code, infrastructure, logs, and secrets stay inside the isolated run directory, never the source repository.

## Step 5: Run Each Journey

Invoke `journey-runner` with:

```text
Journey: <journey-source-path>
Stack: <stack>
Location: <location>
Working directory: <absolute-run-directory>
Cleanup: after-verification
```

The runner owns per-journey preflight, prompts, local ports, deployment, verification, screenshots, and scoped cleanup.

Run serially by default. Parallel runs require:

- Distinct local ports
- Distinct `azd` environment names
- Distinct resource groups
- Sufficient regional quota
- Independent log and screenshot paths

Never share an `azd` environment across journeys.

## Step 6: Preserve Evidence

Before removing a run directory, copy these artifacts with Node.js filesystem APIs:

- `run-report.md`
- `issues.md`
- `screenshot-*.png`
- Sanitized deployment and verification logs

Use the mapping below:

| Journey | Web output | Screenshot |
|---|---|---|
| Grafana | `GRAFANA_URL` | Login page |
| n8n | `N8N_URL` | Owner-setup or login page |
| Superset | `SUPERSET_URL` | Authenticated welcome page when credentials are available |
| AIMarket | `WEB_URL` | Storefront with all images loaded |
| SmartTodo | None | No screenshot on Windows/Linux; simulator screenshot only on a suitable macOS/Xcode host |

Use journey-runner's pinned Playwright Chromium helper. Never use a branded Chrome channel.

## Step 7: Guaranteed Scoped Cleanup

Cleanup runs in a `finally` path after each deployment attempt, including build, deployment, verification, or screenshot failures.

For each journey, delete only:

- Its explicitly recorded `azd` environment
- Its explicitly recorded resource groups and managed resource groups
- Soft-deleted resources whose names were recorded as owned by that run

Never run a pipeline over every row from `azd env list`. Other environments may belong to unrelated work.

After `azd down --force --purge --no-prompt`, verify:

- Recorded resource groups return not found
- No active resource remains with that run's environment tag
- Any owned soft-deleted resource selected for purge is absent
- Unrelated environments and resource groups remain unchanged

If cleanup is incomplete, preserve the workspace and list exact remaining resource IDs in the consolidated report.

## Step 8: Workspace Retention

Delete a per-journey working directory only when all of these are true:

1. Evidence was copied successfully.
2. Azure cleanup was live-verified.
3. The user didn't request generated code retention.
4. No unresolved cleanup or debugging artifact depends on the directory.

Use Node.js `fs.rm(path, { recursive: true, force: true })` on the exact recorded run directory. Never construct a deletion path from untrusted output.

## Step 9: Consolidated Report

Write `test-report.md` directly with file tools or Node.js. Don't build Markdown through a large shell one-liner.

Include:

- UTC start/end and total duration
- Host OS and architecture
- Tool versions
- Subscription and location
- Selected journeys and stack
- Build, deployment, verification, screenshot, and cleanup status per journey
- Preserved artifact paths
- Exact blockers and remaining resource IDs

Example result table:

| Journey | Build | Deploy | Verify | Screenshot | Cleanup | Result |
|---|---:|---:|---:|---:|---:|---:|
| Grafana | PASS | PASS | PASS | PASS | PASS | PASS |
| n8n | PASS | PASS | PASS | PASS | PASS | PASS |
| Superset | PASS | PASS | PASS | PASS | PASS | PASS |
| AIMarket | PASS | PASS | PASS | PASS | PASS | PASS |
| SmartTodo | PASS | PASS | PASS | N/A on Linux/Windows | PASS | PASS |

A journey can't receive PASS when cleanup was requested but not verified.

## Failure Policy

- Missing prerequisite: stop before Azure work.
- Build failure: one evidence-based repair, then mark FAIL.
- Deployment failure: collect diagnostics, then run scoped cleanup.
- Verification failure: retry only documented transient cases, then mark FAIL.
- Screenshot failure: preserve logs and continue to cleanup; mark PARTIAL only if all functional checks passed.
- Cleanup failure: mark FAIL and preserve the run directory.

## Safety Rules

- Never install system packages or privileged emulation automatically.
- Never delete all `azd` environments.
- Never broaden cleanup scope after a failed deletion.
- Never expose credentials, cookies, authorization headers, connection strings, or generated secrets.
- Never claim macOS, Windows, iOS, or browser verification that didn't actually run.
