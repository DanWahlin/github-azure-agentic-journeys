---
name: journey-runner
description: |
  Run an agentic journey end-to-end: extract prompts from a journey README, execute them in sequence, build the app, deploy to Azure, and verify. Use for full-stack and OSS journeys.
  USE FOR: test a journey, run a journey end-to-end, validate journey prompts, deploy a journey to Azure, walk through a journey, execute journey steps, CI journey test.
  DO NOT USE FOR: creating new journeys (use journey-template), reviewing journey content (use content-reviewer), modifying journey code (use coder).
---

# Journey Runner Skill

Execute an agentic journey end-to-end by reading its README, extracting the prompts and commands, running them in sequence, and verifying the results. This is the automated equivalent of a learner walking through the journey manually.

## When to Use

- Testing a new or updated journey before publishing
- CI validation that a journey's prompts produce working code
- Reproducing a journey to verify deployment works
- Onboarding — running a journey to generate a working app

## Inputs

The runner needs:

1. **Journey path** — e.g., `journeys/smart-todo/`
2. **Stack choice** (if multi-stack) — e.g., "Node.js" for journeys that offer language options
3. **Azure subscription** — for deployment phases (skip if user requests local-only run)

## Execution Pipeline

### Step 0: Parse the Journey

Read the journey's `README.md` and extract:

1. **Journey type**: full-stack (has `PLAN.md`) or OSS deployment (uses `@oss-to-azure-deployer`)
2. **Phases**: each `### Phase N` or `### Step N` section
3. **Prompts**: code blocks prefixed with `>` inside Copilot CLI sessions — these are the prompts to execute
4. **Shell commands**: fenced `bash` blocks — these are commands to run directly
5. **Verification commands**: commands inside "🧪 Test it yourself" or "Verification Checklist" sections
6. **Prerequisites**: tools needed (Node.js, Python, Xcode, Docker, etc.)

Output a structured execution plan before starting:

```
Journey: SmartTodo (full-stack)
Phases: 3
Prompts to execute: 12
Shell commands: 8
Verification checks: 5
Prerequisites: Node.js 20+, Azure Functions Core Tools v4, Xcode 16+
Estimated time: ~2.5 hours
```

### Step 1: Prerequisites Check

Verify all required tools are installed:

```bash
# Check each prerequisite listed in the journey
node --version        # Need 20+
func --version        # Azure Functions Core Tools v4
az --version          # Azure CLI
azd version           # Azure Developer CLI
docker --version      # If Docker is required
xcode-select -p       # If Xcode is required (macOS only)
```

If a prerequisite is missing, report it and stop. Do not attempt to install tools.

### Step 2: Set Up Working Directory

Create an isolated working directory for the journey run:

```bash
WORK_DIR=~/journey-runs/<journey-name>-$(date +%Y%m%d-%H%M%S)
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
```

Copy the PLAN.md (if full-stack journey):

```bash
cp /path/to/journeys/<journey-name>/PLAN.md .
```

### Step 3: Execute Phases Sequentially

For each phase in the journey:

#### 3a. Execute Copilot CLI Prompts

Prompts in journey READMEs look like this:

```
> Read the PLAN.md file in this directory. Create a [YOUR LANGUAGE] project...
```

For each prompt:
1. Replace `[YOUR LANGUAGE]` with the chosen stack (e.g., "Node.js/Express with TypeScript")
2. Execute the prompt as a code generation task — treat it as an instruction to generate/modify code in the working directory
3. Wait for completion before proceeding to the next prompt

#### 3b. Execute Shell Commands

Commands in `bash` blocks are run directly:

```bash
cd src/api
npm install
npm start
```

For dev servers (`npm start`, `npm run dev`, `func start`):
- Start in the background
- Wait for the server to be ready (poll health endpoint or wait for stdout)
- Keep running for verification commands
- Stop after verification

#### 3c. Run Verification Commands

Commands in "🧪 Test it yourself" sections verify the phase worked:

```bash
curl http://localhost:7071/api/todos?userId=user-1
```

For each verification:
1. Run the command
2. Check for expected output (non-error HTTP status, valid JSON, etc.)
3. Log PASS/FAIL with the actual output
4. If FAIL, log the error but continue to the next verification (don't stop the run)

#### 3d. Log Phase Results

After each phase, output a summary:

```
Phase 1: Build the API
  ✅ Project scaffolded (src/api/ created)
  ✅ Data models generated (Todo, ActionStep)
  ✅ Repository pattern implemented (interfaces + SQLite)
  ✅ API endpoints created (6 functions)
  ✅ AI step generation wired up
  ⚠️ Verification: GET /api/todos returned 200 but empty array (seed data may not have loaded)
  ✅ Verification: POST /api/todos returned 201
```

### Step 4: Deploy to Azure (if applicable)

Only execute if the journey has a deployment phase AND the user didn't request to skip deployment.

#### 4a. Pre-deployment

```bash
# Register providers (idempotent)
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Sql
# ... (per journey requirements)

# Set subscription
azd env set AZURE_SUBSCRIPTION_ID $(az account show --query id -o tsv)
```

#### 4b. Deploy

```bash
azd up
```

This is the longest step (5-15 minutes). Monitor for errors.

#### 4c. Post-deployment Verification

Run the Verification Checklist from the README against the live deployment:

```bash
API_URL=$(azd env get-value API_URL)
curl -s "$API_URL/api/todos?userId=user-1"
# ... etc
```

#### 4d. Screenshot Web Frontends

If the journey has a web frontend deployed to Azure (a `web` or `frontend` service in `azure.yaml`, or a URL output like `WEB_URL`), capture a screenshot of the running app using Playwright:

1. Get the frontend URL from azd outputs (e.g., `azd env get-value WEB_URL`)
2. Use Playwright to navigate to the URL, wait for the page to load, and take a full-page screenshot
3. Save the screenshot to the working directory as `screenshot-<journey-name>.png`

```javascript
// Playwright screenshot capture
const { chromium } = require('playwright');

async function captureScreenshot(url, outputPath) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  // Wait an extra 3 seconds for async data to load (API calls, images, etc.)
  await page.waitForTimeout(3000);
  await page.screenshot({ path: outputPath, fullPage: true });
  await browser.close();
}
```

**When to capture:**
- Journey has a web frontend URL in its azd outputs (`WEB_URL`, `FRONTEND_URL`, etc.)
- The URL returns HTTP 200 (skip screenshot if the frontend isn't reachable)

**When to skip:**
- API-only journeys (no frontend)
- Mobile-only frontends (iOS/Android — can't screenshot a simulator remotely)
- OSS deployments where the app requires login before showing content (capture the login page instead)

Include the screenshot path in the final report.

#### 4e. Cleanup (if requested)

If the user asked to clean up after verification:

```bash
azd down --force --purge
```

### Step 5: Generate Report

Output a final report:

```
═══════════════════════════════════════════
  Journey Run Report: SmartTodo
  Date: 2026-04-05T08:30:00Z
  Duration: 47 minutes
  Stack: Node.js + TypeScript
═══════════════════════════════════════════

  Phase 1: Build the API         ✅ PASS (12/12 checks)
  Phase 2: Build the iOS App     ✅ PASS (6/6 checks)
  Phase 3: Deploy to Azure       ⚠️ PARTIAL (4/5 checks)
    ❌ AI step generation returned 503 (model still deploying)

  Prompts executed:  12/12
  Verifications:     22/23 passed
  Deployment:        Succeeded
  Screenshot:        ~/journey-runs/smart-todo-20260405-083000/screenshot-smart-todo.png
  Cleanup:           Skipped (not requested)

  Working directory: ~/journey-runs/smart-todo-20260405-083000
═══════════════════════════════════════════
```

---

## Journey Type Variations

### Full-Stack Journeys (e.g., AIMarket, SmartTodo)

- Copy `PLAN.md` to working directory first
- Execute prompts phase-by-phase (API → Frontend/Mobile → AI → Deploy)
- For multi-stack journeys, replace `[YOUR LANGUAGE]` in all prompts
- Mobile frontends (iOS/Android) are built locally, not deployed — verify via simulator check or build success only
- Frontend rebuild step (VITE_API_URL) may be needed after initial deploy

### OSS Deployment Journeys (e.g., n8n, Grafana, Superset)

- No PLAN.md — prompts go through `@oss-to-azure-deployer` agent
- Simpler flow: Setup → Deploy → Verify
- Agent loads the app-specific skill automatically
- Verification is curl-based (health endpoint, UI loading)

---

## How to Invoke

This skill is triggered by natural language. The user's prompt controls the behavior. Here are example prompts and how to interpret them:

**Run a full journey end-to-end:**
> "Run the smart-todo journey"
- Execute all phases including deployment
- Use the default stack if only one is offered
- Do not clean up Azure resources after

**Skip deployment:**
> "Run the AIMarket journey locally — don't deploy to Azure"
- Execute all build/test phases
- Stop before the deployment phase
- No `azd up`, no Azure resources created

**Choose a stack:**
> "Run the AIMarket journey with Python"
- Replace all `[YOUR LANGUAGE]` placeholders with Python/FastAPI
- Use the Python column from the "Choose Your Stack" table in PLAN.md

**Clean up after:**
> "Run the n8n journey end-to-end and tear down when done"
- Execute all phases including deployment and verification
- Run `azd down --force --purge` after verification passes

**Stop on failure:**
> "Run the smart-todo journey but stop if anything fails"
- Halt execution on the first verification failure instead of continuing

**Verbose output:**
> "Run the Grafana journey with full output"
- Log complete command output for every step, not just pass/fail summaries

### Defaults (when the user doesn't specify)

| Behavior | Default |
|----------|---------|
| Deploy to Azure | Yes — execute the deployment phase |
| Cleanup after | No — leave Azure resources running |
| Stack choice | Use the only option, or ask the user if multiple exist |
| On failure | Log and continue to next step |
| Output verbosity | Summary only (pass/fail per step) |

---

## Error Handling

### Prompt Execution Failures

If a Copilot CLI prompt produces code that doesn't compile or has errors:
1. Log the error
2. Attempt one self-correction: describe the error and ask for a fix
3. If the fix works, continue
4. If it fails again, log as FAIL and continue to next step

### Deployment Failures

Common deployment issues and automatic recovery:

| Error | Recovery |
|-------|----------|
| Provider not registered | Run `az provider register` and retry |
| Soft-deleted Cognitive Services | Run `az cognitiveservices account purge` and retry |
| Quota exceeded | Log error, skip deployment, report as BLOCKED |
| Role assignment delay | Wait 60 seconds after `azd up`, retry verification |

### Verification Failures

- HTTP 5xx → retry once after 10 seconds (cold start)
- Empty response → check if seed data was loaded
- Connection refused → check if server is running
- 503 from AI → model may still be deploying, wait 60s and retry

---

## Checklist for Adding Runner Support to a Journey

When creating a new journey, ensure it's runner-compatible:

- [ ] All Copilot CLI prompts are in `>` prefixed code blocks
- [ ] All shell commands are in fenced `bash` blocks
- [ ] Verification commands use `curl` with predictable output (JSON, HTTP status codes)
- [ ] Dev server start commands are identifiable (contain `npm start`, `npm run dev`, `func start`, etc.)
- [ ] `PLAN.md` is self-contained — no references to files outside the journey directory
- [ ] Deployment outputs use `azd env get-value` for all dynamic values
- [ ] Cleanup is a single `azd down --force --purge` command
