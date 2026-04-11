---
on:
  schedule: weekly on monday around 6:00
  workflow_dispatch:
    inputs:
      language:
        description: 'Language for full-stack journeys'
        required: false
        type: choice
        options:
          - Node.js
          - Python
          - .NET
          - Java
        default: Node.js
      journeys:
        description: 'Comma-separated journey names or "all"'
        required: false
        type: string
        default: all
      location:
        description: 'Azure region for deployments'
        required: false
        type: string
        default: westus
  reaction: "rocket"
  status-comment: true

description: "End-to-end test harness that deploys every journey to Azure, verifies, screenshots, and tears down."
labels: ["testing", "azure", "journeys"]
timeout-minutes: 120

engine:
  id: copilot

permissions:
  contents: read
  actions: read
  issues: read
  id-token: write

tools:
  edit:
  bash: [":*"]
  playwright:
  web-fetch:
  github:
    toolsets: [repos, issues]

network:
  allowed:
    - defaults
    - python
    - node
    - azure

safe-outputs:
  create-issue:
    title-prefix: "[Journey E2E] "
    labels: [test-report, automated]
    close-older-issues: true
    max: 1
  add-comment:
    max: 1
  upload-asset:
    max: 10
---

# Journey End-to-End Test Harness

You are the journey test harness. Your job is to run every journey in this repository end-to-end, verify it works, capture screenshots, tear down Azure resources, and produce a consolidated report.

## Configuration

- **Language**: ${{ github.event.inputs.language || 'Node.js' }}
- **Journeys**: ${{ github.event.inputs.journeys || 'all' }}
- **Location**: ${{ github.event.inputs.location || 'westus' }}

## Setup — Azure CLI and Azure Developer CLI

Before running any journey, install and authenticate the Azure tooling.

### Install Azure CLI

```bash
if ! command -v az &>/dev/null; then
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi
az version --output table
```

### Install Azure Developer CLI

```bash
if ! command -v azd &>/dev/null; then
  curl -fsSL https://aka.ms/install-azd.sh | bash
fi
azd version
```

### Authenticate to Azure

Use the service principal credentials stored in repository secrets to authenticate:

```bash
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

Verify authentication:

```bash
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
```

### Register Azure Resource Providers

Register all providers that journeys might need (idempotent):

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.ContainerRegistry
```

## Environment Variables Available

These are set from repository secrets and variables:

- `AZURE_CLIENT_ID` — Service principal app ID
- `AZURE_CLIENT_SECRET` — Service principal secret
- `AZURE_TENANT_ID` — Entra ID tenant
- `AZURE_SUBSCRIPTION_ID` — Target subscription

## Execution Instructions

### Step 1: Discover Journeys

List all journey directories in `journeys/`:

```bash
ls -d journeys/*/README.md | sed 's|journeys/||;s|/README.md||' | sort
```

If the journeys input is not "all", filter to only the requested journeys (comma-separated).

### Step 2: Run Each Journey Sequentially

For each journey, follow this exact sequence:

#### 2a. Load the journey-runner skill

Read `.github/skills/journey-runner/SKILL.md` to understand the execution pipeline.

#### 2b. Execute the journey

Run the journey end-to-end using the journey-runner approach:

1. **Parse** the journey's `README.md` — extract journey type (OSS vs full-stack), phases, prompts, shell commands, and verification checks
2. **Set up working directory**: `~/journey-runs/<journey>-$(date +%Y%m%d-%H%M%S)`
3. **Copy PLAN.md** if it exists (full-stack journeys)
4. **Execute phases** — run prompts and shell commands in order
   - For full-stack journeys, replace `[YOUR LANGUAGE]` with the configured language
   - For smart-todo, **skip Phase 2 (iOS/SwiftUI)** since Xcode is not available in CI
5. **Deploy**: Run `azd up --no-prompt` (set `AZURE_LOCATION` to the configured location)
6. **Verify**: Run verification commands from the README
7. **Screenshot**: If the journey has a web frontend URL, use Playwright to capture a screenshot:
   - Navigate to the URL, wait for `networkidle`, wait 3 extra seconds, take a full-page screenshot
   - Save as `screenshot-<journey>.png` in the working directory
8. **Tear down**: Always run `azd down --force --purge` regardless of success or failure
9. **Log results**: Record pass/fail for build, deploy, verify, cleanup phases

#### 2c. Clean state between journeys

```bash
cd ~
rm -rf ~/journey-runs/<previous-journey>-*  # optional: keep for report
```

### Step 3: Generate Consolidated Report

After all journeys complete, create a markdown report with:

- Date, language, location, total duration
- Per-journey table: journey name, type (OSS/full-stack), build/deploy/verify/cleanup status, overall result
- Summary counts: PASS / PARTIAL / FAIL / SKIPPED
- Screenshot file list
- Detailed failure/warning messages for any non-PASS results

Format the report as a GitHub issue body. Include any screenshots as uploaded assets.

### Step 4: Create GitHub Issue

Use the `create-issue` safe output to create a GitHub issue with:
- Title: `Journey E2E Test Report — <date>`
- Body: The consolidated report markdown
- Labels: `test-report`, `automated`

If screenshots were captured, reference them in the issue body.

## Journey Reference

| Journey | Type | Deploy Time | Web UI | Screenshot URL Key |
|---------|------|-------------|--------|-------------------|
| n8n | OSS (Container Apps + PostgreSQL) | ~7 min | Yes | `N8N_URL` |
| grafana | OSS (Container Apps, no DB) | ~2 min | Yes | `GRAFANA_URL` |
| superset | OSS (AKS + PostgreSQL) | ~15 min | Yes | `SUPERSET_URL` |
| smart-todo | Full-stack (Functions + SQL + AI) | ~10 min | No (iOS) | — |
| aimarket | Full-stack (Container Apps + AI) | ~12 min | Yes | `WEB_URL` |

## Error Recovery

- If `azd up` fails, still run `azd down --force --purge` to clean up partial resources
- If a journey fails, log the error and **continue to the next journey** — do not stop the suite
- If Azure quota is exceeded, log as BLOCKED and skip that journey's deployment
- If a screenshot fails (e.g., 502 on first load), retry once after 60 seconds (cold start)
- If verification returns 5xx, retry once after 10 seconds before marking as failed
