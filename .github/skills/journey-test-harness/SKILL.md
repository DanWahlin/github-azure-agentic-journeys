---
name: journey-test-harness
description: |
  Run all journeys end-to-end as a test suite. Discovers every journey in journeys/*, runs each through journey-runner with deploy + teardown, captures screenshots of web apps, and produces a summary report.
  USE FOR: test all journeys, regression test, CI journey validation, nightly journey test, end-to-end journey suite, validate all journeys deploy correctly.
  DO NOT USE FOR: running a single journey interactively (use journey-runner), creating new journeys (use journey-template), reviewing journey content (use content-reviewer).
---

# Journey Test Harness

Orchestrate the `journey-runner` skill across every journey in this repository. This skill discovers journeys, runs each one end-to-end (build → deploy → screenshot → teardown), and produces a consolidated pass/fail report.

## When to Use

- Regression testing after changes to skills, agents, or journey READMEs
- Nightly or weekly CI validation that all journeys still deploy successfully
- Pre-release gate to confirm nothing is broken before merging

## Inputs

The harness accepts these parameters from the user prompt:

1. **Language** (optional) — default `Node.js/TypeScript`. Applies to full-stack journeys (smart-todo, aimarket) that have a `[YOUR LANGUAGE]` placeholder. OSS journeys ignore this.
2. **Journeys** (optional) — default `all`. A comma-separated list of journey folder names (e.g., `n8n,grafana`) or `all` to run everything in `journeys/*/`.
3. **Skip deploy** (optional) — default `false`. If `true`, only build/test locally without deploying to Azure.
4. **Location** (optional) — default `westus`. Azure region for deployments.

## Execution Flow

### Step 1: Discover Journeys

Scan `journeys/*/README.md` to build the list of journeys to test:

```bash
JOURNEYS=$(ls -d journeys/*/README.md | sed 's|journeys/||;s|/README.md||')
```

If the user specified a subset (e.g., `journeys=n8n,grafana`), filter to only those.

Output the discovery result:

```
═══════════════════════════════════════════
  Journey Test Harness
  Journeys found: 5
  Language: Node.js/TypeScript
  Deploy: Yes
  Location: westus
═══════════════════════════════════════════

  1. aimarket    (full-stack)
  2. grafana     (OSS)
  3. n8n         (OSS)
  4. smart-todo  (full-stack)
  5. superset    (OSS)
```

### Step 2: Prerequisites Check

Before running any journey, verify shared prerequisites:

```bash
az --version
azd version
node --version
docker --version 2>/dev/null || echo "Docker not available (some journeys may skip)"
```

Also verify Azure authentication:

```bash
az account show --query "{subscription:name, id:id}" -o table
```

If not authenticated, stop and report.

### Step 3: Register Azure Providers (once)

Run provider registration once before the first journey:

```bash
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.DBforPostgreSQL --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.ContainerService --wait
az provider register --namespace Microsoft.Web --wait
az provider register --namespace Microsoft.Sql --wait
az provider register --namespace Microsoft.CognitiveServices --wait
```

### Step 4: Run Each Journey

For each journey, invoke the **journey-runner** skill with these parameters:

```
Run the <journey-name> journey end-to-end and tear down when done.
Stack: <language>
Location: <location>
```

The journey-runner skill handles:
1. Parsing the journey README
2. Setting up a working directory
3. Executing prompts and shell commands phase by phase
4. Deploying to Azure (`azd up`)
5. Running verification checks
6. Capturing screenshots (if web frontend exists)
7. Tearing down (`azd down --force --purge`)
8. Generating a per-journey report

**Between journeys**, ensure clean state:

```bash
# Clear any lingering azd environment
azd env list 2>/dev/null | grep -v "NAME" | awk '{print $1}' | xargs -I{} azd env delete {} --yes 2>/dev/null
```

### Step 5: Capture Screenshots

For each journey that has a web-accessible frontend, the journey-runner already handles screenshots. If running outside of journey-runner (e.g., verifying an existing deployment), use Playwright:

```javascript
const { chromium } = require('playwright');

async function captureScreenshot(url, outputPath) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: outputPath, fullPage: true });
  await browser.close();
}
```

Screenshot mapping by journey:

| Journey | Web URL Output | Screenshot? |
|---------|---------------|-------------|
| n8n | `N8N_URL` | Yes (login page) |
| grafana | `GRAFANA_URL` | Yes (login page) |
| superset | `SUPERSET_URL` | Yes (login page) |
| aimarket | `WEB_URL` or `FRONTEND_URL` | Yes (storefront) |
| smart-todo | None (iOS app) | No — API only |

### Step 6: Generate Consolidated Report

After all journeys complete, generate a summary report:

```
═══════════════════════════════════════════════════════
  Journey Test Harness — Consolidated Report
  Date: 2026-04-12T00:00:00Z
  Language: Node.js/TypeScript
  Location: westus
  Total Duration: 2h 15m
═══════════════════════════════════════════════════════

  Journey         Type        Build   Deploy  Verify  Cleanup  Result
  ─────────────────────────────────────────────────────────────────────
  n8n             OSS         ✅      ✅      ✅      ✅       PASS
  grafana         OSS         ✅      ✅      ✅      ✅       PASS
  superset        OSS         ✅      ✅      ⚠️      ✅       PARTIAL
  smart-todo      full-stack  ✅      ✅      ✅      ✅       PASS
  aimarket        full-stack  ✅      ❌      —       ✅       FAIL

  Summary: 3 PASS | 1 PARTIAL | 1 FAIL
  Screenshots: 3 captured (n8n, grafana, superset)

  Details:
    superset: Verification warning — /health returned 503 on first attempt (cold start), passed on retry
    aimarket: Deploy failed — quota exceeded for Microsoft.CognitiveServices in westus

═══════════════════════════════════════════════════════
```

Save this report to `~/journey-runs/test-report-<timestamp>.md`.

## Journey-Specific Notes

### OSS Journeys (n8n, grafana, superset)

- Use `@oss-to-azure-deployer` agent flow
- No language choice needed
- Infrastructure is generated fresh each run
- Superset uses AKS (longer deploy, ~15 min)

### Full-Stack Journeys (smart-todo, aimarket)

- Replace `[YOUR LANGUAGE]` with the chosen stack
- Copy `PLAN.md` to working directory
- smart-todo: Skip Phase 2 (iOS/SwiftUI) in CI — no Xcode available. Test API + deploy only.
- aimarket: Needs Docker for container image builds

## Error Handling

| Scenario | Action |
|----------|--------|
| Journey fails to build | Log as FAIL, continue to next journey |
| Deployment fails | Log error, attempt `azd down` cleanup anyway, continue |
| Verification fails | Log as PARTIAL (if some pass) or FAIL (if all fail), continue |
| Teardown fails | Log warning, continue (Azure resources may be orphaned) |
| Azure quota exceeded | Log as BLOCKED, skip deployment, continue |
| Timeout (>30 min per journey) | Kill deployment, attempt cleanup, log as TIMEOUT |

## How to Invoke

```
> Run the journey test harness
```

```
> Run the journey test harness with Python for full-stack journeys
```

```
> Run the journey test harness for n8n and grafana only
```

```
> Run the journey test harness but skip deployment
```
