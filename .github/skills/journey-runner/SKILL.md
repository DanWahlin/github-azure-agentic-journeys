---
name: journey-runner
description: |
  Run an agentic journey end-to-end: preflight the host, extract prompts, execute them in an isolated workspace, build, deploy to Azure, verify with real requests and screenshots, and clean up only owned resources.
  USE FOR: test a journey, run a journey end-to-end, validate journey prompts, deploy a journey to Azure, walk through a journey, execute journey steps, CI journey test.
  DO NOT USE FOR: creating new journeys (use journey-template), reviewing journey content (use content-reviewer), or modifying unrelated code.
---

# Journey Runner Skill

Run a journey like a learner would, but with strict preflight, isolated state, evidence-backed verification, and scoped cleanup. The workflow must work on Windows, macOS, and Linux.

## Required Runner Tools

The runner itself requires:

- Node.js 24 LTS or later
- Azure CLI
- Azure Developer CLI (`azd`) 1.28.0 or later
- GitHub Copilot CLI

Screenshot runs additionally require the local Playwright package and bundled Chromium under `scripts/`. Installation options for all operating systems are in [`../../../docs/tool-installation.md`](../../../docs/tool-installation.md).

Do not install system tools during a run. Report the missing tool, its install link, and the validation command, then stop before generating code or creating Azure resources. Project-local `npm ci` for the checked-in runner helpers is allowed only during explicit runner setup, not as a surprise halfway through a journey.

## Inputs and Defaults

Inputs:

1. Journey path, such as `journeys/smart-todo/`
2. Stack choice when the journey supports multiple stacks
3. Azure subscription for deployment runs
4. Cleanup policy: `after-verification` or `leave-running`

Defaults:

| Behavior | Default |
|---|---|
| Deploy to Azure | Yes, when the journey contains a deployment phase |
| Cleanup | `after-verification` |
| Stack | Use the only option; ask before starting when multiple materially different stacks exist |
| Verification failure | Record the failure, attempt one evidence-based repair, then stop that phase if it still fails |
| Output | Concise phase summary plus artifact paths and actual command results |

Only use `leave-running` when the user explicitly requests it.

## Step 0: Parse the Journey

Read the journey's `README.md`, `PLAN.md` when present, and every associated journey skill. Extract:

- Journey type and phases
- Prompts to send to Copilot
- Commands and generated scripts
- Required and optional host tools
- Local ports
- Deployment outputs
- Verification criteria
- Platform gates such as Xcode

Build a prerequisite list from the journey's own prerequisite section. Do not rely on a hard-coded generic list when the journey requires Helm, `sqlcmd`, Azure Functions Core Tools, Docker, or another host tool.

Before execution, print a plan containing the journey, stack, host OS/architecture, phases, required tools, optional tools, planned ports, deployment choice, and cleanup policy.

## Step 1: Cross-Platform Preflight

Detect the host with Node.js `process.platform`, `process.arch`, and `os.release()`. Never infer the operating system from path syntax.

Run the helper from this skill directory:

```text
node scripts/check-prerequisites.mjs --required node,az,azd,copilot,<journey-tools> --optional <optional-tools>
```

Journey-specific minimums:

| Journey | Additional required tools | Optional or platform-gated tools |
|---|---|---|
| Grafana | None | Playwright for screenshots |
| n8n | Node.js 24 LTS or later | Playwright for screenshots |
| Superset | Node.js 24 LTS or later, `kubectl`, Helm 3 | Playwright for screenshots |
| AIMarket | Node.js 24 LTS or later, Docker CLI and running daemon, GitHub CLI | Playwright; local AMD64 emulation only when remote builds are unavailable |
| SmartTodo | Node.js 24 LTS or later, Azure Functions Core Tools v4, `sqlcmd` | Project-local Azurite for local execution; Docker for alternate stacks or local SQL; Xcode 16+ only for macOS iOS execution |

### Authentication preflight

Check Azure CLI and `azd` separately:

1. `az account show` must succeed and show the intended subscription.
2. Configure `azd` to reuse Azure CLI authentication with `azd config set auth.useAzCliAuth true`.
3. Run an `azd` command that reads account/environment state before creating resources.
4. If Azure CLI works but `azd` still reports an expired token, stop and report the mismatch. Do not assume `az login` fixed `azd`.

### Architecture preflight

For Container Apps images, compare host architecture with the required `linux/amd64` target.

- Prefer a remote ACR build on any ARM64 host.
- If a local cross-build is required, verify Buildx and AMD64 emulation before provisioning.
- Never install privileged QEMU/binfmt handlers automatically.
- Require frontend Dockerfiles with native `$BUILDPLATFORM` builder stages when native tools such as esbuild are involved.

### Mobile platform matrix

- macOS with Xcode: build and run the iOS app or simulator when the journey requires it.
- Windows or Linux: generate and inspect SwiftUI source, build and test the backend, deploy Azure resources, and run backend API verification. Do not claim an iOS simulator or Xcode test occurred.

Any missing required prerequisite stops the journey before Phase 1.

## Step 2: Create an Isolated Workspace

Create a unique directory without shell-specific date or path expressions. Use Node.js filesystem APIs or the active agent's file tools.

Recommended shape:

```text
<journey-runs-root>/<journey-name>-<UTC timestamp>/
```

Copy only `PLAN.md` and other explicitly required source documents. Never write generated application files into the source journey directory.

Record:

- Absolute workspace path
- Source commit
- Host OS and architecture
- Tool versions
- Selected stack
- Selected local ports
- Cleanup policy

Before starting a local server, test whether its preferred port is available. Select a supported free port rather than stopping an unrelated process.

## Step 3: Invoke Copilot Correctly

Copilot CLI accepts prompt text with `-p`; it does not accept a `--prompt-file` CLI option. Do not launch background jobs with an unverified flag.

Write each prompt to a UTF-8 file, then use the cross-platform helper:

```text
node scripts/run-copilot-prompt.mjs --prompt-file <prompt-path> --cwd <workspace>
```

The helper reads the file and calls `copilot -p <prompt>` with `shell: false`, avoiding Bash and PowerShell quoting differences.

Before launching a batch, run `copilot --help` and one harmless prompt smoke test. If that fails, do not start parallel or background journey processes.

Execute prompts sequentially within a journey. Wait for each prompt to finish, inspect the files it produced, and only then continue.

## Step 4: Execute Commands Portably

Do not execute a fenced `bash` block verbatim in PowerShell.

Priority order:

1. Run checked-in or generated Node.js verification and lifecycle scripts.
2. Run individual CLIs with argument arrays and `shell: false`.
3. Use a journey-provided PowerShell or Bash variant that matches the host.
4. If only an OS-specific command exists, stop and log a documentation defect rather than inventing a translation after resources exist.

Generated `azd` lifecycle hooks must be `.mjs` or `.ts` files referenced directly from `azure.yaml`. Do not generate `.sh` hooks, `shell: sh`, `chmod`, shell traps, command substitution, or pipelines for required deployment behavior.

For development servers:

- Start a tracked background process.
- Wait for a health endpoint or explicit ready signal.
- Run verification against the actual selected port.
- Stop only the process started by this run.

## Step 5: Build and Local Verification

Run the journey's build, lint, and tests before Azure deployment. Verification must assert behavior, not merely process exit.

For each check, record:

- Command or script
- Expected result
- Actual status and key output
- PASS, FAIL, or BLOCKED

If a check fails, make one targeted repair based on the real error and rerun the failing check. Never replace unavailable execution with plausible output.

## Step 6: Azure Deployment

Before `azd up`:

1. Register only providers required by the journey.
2. Record the `azd` environment name, intended resource-group name, expected managed resource groups, deployment tags, and names of soft-deletable resources.
3. Read the subscription ID with `az account show --query id -o tsv`, then pass that value to `azd env set AZURE_SUBSCRIPTION_ID <value>` without shell command substitution.
4. Validate generated Bicep and `azure.yaml`.
5. Confirm required host hooks and tools passed preflight.

Run `azd up` and capture its real output. Monitor long-running deployment processes rather than assuming they completed.

For Container Apps using ACR, verify all of these before the first private image deployment:

- System-assigned identity exists.
- `AcrPull` is assigned to that identity.
- The Container App registry configuration contains the ACR login server and `identity: system`.
- The deployed image architecture is compatible with `linux/amd64`.

A filtered command such as `azd deploy web` can skip project-level hooks. Run the documented hook directly after a filtered deployment and repeat production verification.

## Step 7: Production Verification

Run the journey's portable verification script against live outputs. Do not stop at HTTP 200 when the journey requires data, authentication, images, or mutations.

Examples:

- Grafana: root HTTP 200 and `/api/health` reports database `ok`.
- n8n: `/healthz` HTTP 200 and owner-setup or login page renders.
- Superset: pod `1/1 Running`, `/health` HTTP 200, login succeeds with the documented selectors.
- AIMarket: 10 products, search and chat work, production API URL is baked into the frontend, and every product image loads.
- SmartTodo: seed read, create, AI step generation, fetch, step update, delete, and absence confirmation all pass.

Temporary verification records must be deleted in `finally`.

## Step 8: Screenshot Web Frontends

The runner helper uses Playwright's bundled Chromium. Do not require the branded Chrome channel, especially on Linux ARM64.

One-time runner setup from the `scripts/` directory:

```text
npm ci
npx playwright install chromium
```

Linux hosts may require the administrator-approved command `npx playwright install --with-deps chromium`. Do not run it silently.

Capture a public page:

```text
node scripts/capture-screenshot.mjs --url <url> --output <png> --fail-on-resource-errors true
```

For Superset login, additionally pass:

```text
--username admin --password <secret> --username-selector #username --password-selector #password --submit-selector "button:has-text('Sign in')" --success-path /superset/welcome/
```

Never print credentials. Visually inspect the saved image and review failed document, script, XHR, fetch, and image requests. A broken product image fails AIMarket acceptance.

Skip screenshots for API-only journeys and for iOS on Windows/Linux. A mobile screenshot is only required on a suitable macOS/Xcode host.

## Step 9: Scoped Cleanup

With the default `after-verification` policy, preserve reports and screenshots, then run:

```text
azd down --force --purge --no-prompt
```

Cleanup must use the ownership inventory recorded before deployment. Delete only the exact `azd` environment, resource groups, managed resource groups, and soft-deleted resources created by this run.

Verify cleanup with live Azure queries:

- Every recorded resource group returns not found.
- No active resource remains with the run's `azd-env-name` tag.
- Any purged soft-deletable resource is absent.
- Unrelated resource groups and deployments remain untouched.

If cleanup fails, report the exact remaining resource IDs. Never broaden deletion scope to make the report look clean.

## Step 10: Report

Write `run-report.md` and include:

- Journey, stack, host OS/architecture, and tool versions
- Source commit and workspace path
- Phase results with real pass/fail counts
- Deployment environment and owned resource groups
- Verification requests and actual outcomes
- Screenshot paths and browser resource failures
- Cleanup policy and verification result
- Remaining blockers or platform limitations

Write sanitized journey defects to that journey's `issues.md`. Keep shared orchestration defects in the runner issue section. Never include credentials, tokens, cookies, connection strings, SQL passwords, or authorization headers.

## Runner-Compatible Journey Checklist

- [ ] The journey prerequisite section lists every required host tool and links to OS-specific installation options.
- [ ] Commands work on Windows, macOS, and Linux, or clearly state a platform gate.
- [ ] Required hooks are JavaScript/TypeScript, not shell-specific scripts.
- [ ] Verification uses portable scripts with deterministic exit codes.
- [ ] Local ports are configurable.
- [ ] ARM64 and AMD64 image behavior is explicit.
- [ ] Browser checks use bundled Chromium rather than a branded Chrome channel.
- [ ] Dynamic values come from `azd env get-value` without shell substitution.
- [ ] Cleanup can identify and verify only the resources owned by the run.
