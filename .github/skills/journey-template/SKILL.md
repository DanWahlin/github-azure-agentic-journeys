---
name: journey-template
description: |
  Create new agentic journeys from app ideas. Generates README.md (learner walkthrough), PLAN.md (AI-readable spec), and app-specific skills for OSS deployments. Supports any stack (Node.js, Python, .NET, Java, Swift, Kotlin) and Azure service (Container Apps, AKS, Functions, App Service).
  USE FOR: new journey, scaffold journey, create learning experience, generate journey template, add journey to repo, build and deploy app to Azure, create journey README, generate PLAN.md spec, new OSS deployment, new full-stack journey, journey from idea.
  DO NOT USE FOR: modifying existing journeys (use coder), reviewing journey content (use content-reviewer), deploying apps (use oss-to-azure-deployer agent).
---

# Journey Template Skill

Generate a complete agentic journey from a user's app idea. A journey is a hands-on learning experience where developers use GitHub Copilot (CLI, app, or IDE) to build and deploy an app to Azure.

## Curriculum packaging (required)

**Every journey README must include:**
- No journey-sequence or learning-path numbering such as "Journey 2 of 5" — journeys are self-contained. Numbered phases and steps inside one journey are encouraged when they clarify the flow.
- Honest first-run time + cost **if left running** + same-day teardown
- **Done when** checklist with concrete manual verification steps
- Full-stack: **one-line default stack** at the first generate prompt (not a defaults table); put stack details in PLAN.md
- Plugin commands: only `microsoft/azure-skills` / `azure@azure-skills`
- What's Next uses plain links to related journeys, not prescribed-path or completion language
- OSS: shared deploy recipe (location, secrets, probes, resolve issues, issues.md)
- An isolated-workspace setup prompt that copies the journey, `.github/agents`, `.github/skills`, `.github/scripts`, and `docs` without modifying the source repository
- A prerequisite table, concrete local/Azure acceptance criteria, and a reusable exact-error recovery prompt
- A prompt that **creates every generated verifier or diagnostic script before the README tells the learner to run it**
- A read-only pre-deployment review with READY/NOT READY, PASS/FAIL evidence, and fail-closed blockers
- Agent-led azd environment preparation, followed by the learner running the consequential `azd up` command
- No checked-in journey `issues.md`: prompts create it only in the isolated learner workspace when a real issue occurs

Update root `README.md` learning path + journey table when adding a journey.

## Journey Types

| Dimension | Full-Stack (e.g. AIMarket) | OSS Deployment (e.g. n8n, Grafana, Superset) |
|-----------|---------------------------|----------------------------------------------|
| **What the learner does** | Builds an app from scratch with GitHub Copilot | Deploys an existing OSS app via `@oss-to-azure-deployer` agent |
| **Files generated** | README.md + PLAN.md | README.md + app-specific skill in `.github/skills/` |
| **README structure** | "The Journey" with 3-5 phases (adapt to app complexity) | "Deploy with the Agent" with 3 steps (Setup → Deploy → Verify) |
| **Images** | 4-6 (one per phase boundary) | 2 (hero + deployment) |
| **Unique sections** | "The Spec", "How Agentic AI is Used", one-line default stack at first prompt | "Configuration Reference", "Key Learnings", skip rules if expensive |
| **Compute target** | Container Apps, App Service, Functions, Static Web Apps, AKS | Container Apps, AKS, App Service |

## Output Structure

```
journeys/<app-name>/
├── README.md          # Learner-facing walkthrough
├── PLAN.md            # AI-readable spec (full-stack journeys only)
└── images/            # Generated images (added separately)
```

For OSS deployment journeys, also create an app-specific skill:

```
.github/skills/<app>-azure/
├── SKILL.md              # Overview, quick start, architecture, verification
├── config/
│   ├── environment-variables.md
│   └── health-probes.md
└── troubleshooting.md
```

The SKILL.md needs YAML frontmatter:

```yaml
---
name: <app>-azure
description: Deploy <App> to Azure. Use when deploying <App> for <purpose>.
---
```

### OSS Skill SKILL.md Structure

The skill is what the `@oss-to-azure-deployer` agent reads. Follow this section order (reference `n8n-azure` as the primary example):

1. **Overview / When to Use** — one paragraph
2. **Critical: Infrastructure Generation** — infrastructure is generated fresh each deployment via `azure-prepare` plugin, NOT committed to the repo
3. **Critical: Subscription Context** — read the value with `az account show --query id -o tsv`, then pass it to `azd env set AZURE_SUBSCRIPTION_ID <subscription-id>` without shell command substitution
4. **Critical: \<App-Specific Gotcha\>** — the #1 deployment failure cause (e.g., PostgreSQL SKU needs both `name` AND `tier`; Bicep outputs MUST use SCREAMING_SNAKE_CASE)
5. **Official Documentation** — link to app's docs
6. **Quick Start (Verified)** — exact prompt sequence, tested and confirmed
7. **Key Configuration Files** — table pointing to `config/environment-variables.md`, `config/health-probes.md`, `troubleshooting.md`
8. **Architecture** — Mermaid diagram of Azure resources
9. **App-Specific Requirements** — database, networking, storage, ports
10. **Cost Estimate** — table with SKUs and monthly costs
11. **Verification Checklist** — curl / az commands to confirm deployment
12. **Tear Down** — `azd down --force --purge`
13. **Differences from Generic Patterns** — what makes this app non-standard (startup timing, SSL, env vars, ports)

For AKS-based apps (like Superset), also include:
- `references/kubernetes-manifests.md` in the skill directory
- Default credentials section (e.g., admin/admin)
- "Why AKS Instead of Container Apps?" justification in the README
- Resource requirements table (CPU/Memory per pod)

---

## README.md Template

Every journey README MUST follow this exact structure. Reference `journeys/aimarket/README.md` for a full-stack example and `journeys/n8n/README.md` for an OSS deployment example.

### Required Sections (in order)

```markdown
# <App Name> - <Subtitle>

> ✨ **<One-sentence hook — what makes this journey interesting, not a summary>**

<p align="center">
  <img src="./images/<hero-image>.jpg" alt="<Alt text>" width="800" />
</p>

<1-2 sentence intro. Focus on what the learner will accomplish, not a feature list.>

## Learning Objectives

- <Concrete outcomes: "you'll know how to X" not "use X">

> 💰 **Estimated Cost**: ~$X-Y/month (<main cost driver> — see [Cost Breakdown](#cost-breakdown)). **Clean up with `azd down` when done!**

## Prerequisites

<Required/optional/platform-gated tool table with purpose, minimum version, and validation command. Link to the cross-platform tool guide.>

<Read-only preflight command block and explicit stop-on-failure rule.>

### Acceptance criteria

<Concrete local, deployed, screenshot, and cleanup completion checks.>

---

## Architecture

<Mermaid diagram showing Azure resources>

**Azure resources created:**

- **Resource** — what it does

---

## Deploy with the Agent / The Journey

### Step 1: Setup

<Plugin setup — use these EXACT commands:>

```bash
copilot
```

Once inside the interactive session, add the marketplace (first time only):

```
> /plugin marketplace add microsoft/azure-skills
```

Then install the plugin:

```
> /plugin install azure@azure-skills
```

> **Already installed?** If you completed the root [Quick Start](../../../README.md#quick-start) (or already installed `azure@azure-skills`), skip the install commands — the plugin persists across sessions.
> **Canonical only:** `microsoft/azure-skills` — never document alternate marketplace names.

After installation, include a prompt that asks the agent to confirm which Azure Skills and MCP tools are available in the current session. Stop before Azure-file generation if the plugin is unavailable.

<For OSS journeys, select the agent:>

```
> /agent
```

Select **`oss-to-azure-deployer`** from the list.

### Step 2: Deploy

<p align="center">
  <img src="./images/azure-deployment.jpg" alt="Deploy to Azure" width="800" />
</p>

<Step-by-step instructions>

### Step 3: Verify

<Verification steps>

---

## Configuration Reference (OSS journeys only — full-stack journeys put this in PLAN.md)

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| ... | Yes/No | ... |

### Container Resources

| Setting | Value | Notes |
|---------|-------|-------|
| CPU | 0.5 | ... |
| Memory | 1Gi | ... |

### Health Probes

| Probe | Path | Timing |
|-------|------|--------|
| Liveness | /api/health | initialDelay: 30s, period: 10s |
| Startup | /api/health | failureThreshold: 10, period: 10s |

---

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| ... | ... | ~$X |
| **Total** | | **~$X-Y/month** |

Use human-readable SKU names (e.g., "Pay-per-GB" not "PerGB2018").

---

## Troubleshooting

### <Symptom — what the user sees>

**Cause:** <What went wrong>

**Fix:** <How to fix it>

Separate deployment errors from post-deployment usage issues with:
> **Post-Deployment Issues:** The following issues relate to *using* the app after deployment, not the deployment itself.

---

## Verification Checklist

<Comprehensive validation commands — supplements the quick checks in Step 3 with deeper verification (e.g., database connectivity, SSL, scaling behavior)>

---

## Cleanup

> ⚠️ Confirm the selected azd environment belongs to this journey. Save `RESOURCE_GROUP_NAME` before teardown so deletion can be verified without guessing.

```bash
azd down --force --purge
```

Require successful exit, then verify the exact resource group no longer exists with `az group exists --name <resource-group-name>` returning `false`. Include resource-specific soft-delete purge guidance only when the architecture needs it.

---

## Key Learnings

- <4-5 insights NOT already covered in troubleshooting>
- <Focus on architectural decisions and patterns>

---

## Assignment

<Hands-on tasks that guide discovery, not just verification>
<Pattern: do something → observe the result → ask the agent why → fix it>

---

## What's Next

<Plain links to related journeys without prescribed order or completion language>

---

## Resources

<Official docs links>
```

### Structural Variations by Journey Type

**OSS deployment journeys** use the base template as-is. Section order:

`Deploy with the Agent` (3 steps) → `Configuration Reference` → `Cost Breakdown` → `Troubleshooting` → `Verification Checklist` → `Cleanup` → `Key Learnings` → `Assignment` → `What's Next` → `Resources`

**Full-stack journeys** replace several sections:

| Base Template Section | Full-Stack Replacement |
|----------------------|----------------------|
| `Deploy with the Agent` (3 steps) | `The Journey` with app-specific numbered phases that end in Deploy |
| `Configuration Reference` | Omit — specs live in PLAN.md |
| `Key Learnings` | `How Agentic AI is Used` — table of agentic use cases |

Full-stack and from-plan static-web journeys also add:
- **"The Spec"** section after Architecture — links to PLAN.md and explains that it is shared implementation context
- **Phase-level images** — one image at each phase boundary (e.g., spec-to-code, testing, deployment)
- **Teaching markers** within each phase (🔍 Inspect, 💡 What you're learning, 🧪 Test it yourself)
- **Incremental prompts** that generate, inspect, test, and refine one bounded layer at a time
- **Generated-script provenance**: the README prompt must create a verifier or diagnostic before any command runs that path
- **Deployment handoff**: use the agent plus Azure Skills for preparation and review, but have the learner run `azd up` and observe its real output
- A cloud-agent/delegation option only when it teaches a real, self-contained asynchronous task; do not force two deployment options into every journey

For mobile frontends (iOS/Android), note in the README:
- Backend is deployed to Azure with `azd up`; mobile app runs locally or via TestFlight / Play Store internal testing
- API URL must be configurable (not hardcoded) — use environment config or build schemes
- Mobile app is NOT deployed by azd — only the Azure backend is
- Include device testing instructions (simulator/emulator + physical device)

For AKS deployments (e.g., Superset), add:
- **"Why AKS Instead of Container Apps?"** section after Architecture with architectural justification
- **AKS run-command verification** through `az aks command invoke`, not a local `kubectl` dependency
- **Complexity note** in the opening when the deployment is long-running or multi-step

For API-only journeys (no frontend):
- Omit Phase 2 entirely — journey goes straight from API/Backend to Deploy
- Remove `web` service from azure.yaml — single service only
- Skip the frontend rebuild step in the deployment flow
- Verification is curl/API testing only

### Emoji Conventions

Use consistently throughout all journeys:

| Emoji | Usage |
|-------|-------|
| ✨ | Tagline hook (one per journey) |
| 💰 | Cost estimate |
| 📋 | Prerequisites |
| 🔍 | Inspect what was generated (full-stack only) |
| 💡 | Meta-learning insight (full-stack only) |
| 🧪 | Test it yourself (full-stack only) |
| ⚠️ | Warning or critical note |

---

## PLAN.md Template (Full-Stack and From-Plan Journeys)

The PLAN.md is a spec document that GitHub Copilot reads to generate code. It is not tutorial content, but the learner should open it, understand the finished behavior, and keep it available as shared context. README prompts must cite exact PLAN section names; rename both in the same change. Reference current AIMarket and SmartTodo PLANs for examples.

### Required Sections

```markdown
# <App Name>: <Subtitle> — Spec

<One-sentence description>. This document is the spec — GitHub Copilot reads it to generate the implementation.

**Out of scope:** <What this app does NOT do>

---

## Choose Your Stack

| | Node.js | Python | .NET | Java |
|---|---------|--------|------|------|
| **Framework** | Express + TypeScript | FastAPI | ASP.NET Core Minimal APIs | Spring Boot |
| **Database** | `better-sqlite3` | `sqlite3` (stdlib) | `Microsoft.Data.Sqlite` | `JdbcTemplate` + SQLite |

<Adapt this table to your journey's stack. Not limited to these — Go, Rust, Ruby, PHP, etc. are also valid choices.>

Frontend: React, Angular, Vue, Swift/SwiftUI (iOS), Kotlin/Jetpack Compose (Android), React Native, Flutter, or none for API-only journeys. Deploy backend with **azd** + **Bicep using Azure Verified Modules (AVM)**.

## Project Structure

<Adapt phases to your app. Not all phases are required — omit Frontend for API-only apps, omit AI for apps without AI features. The final phase is always Deploy.>

## Phase 1: API / Backend
### Data Access Layer (repository pattern — interfaces → implementations → factory)
### Data Models (with field types, constraints, and validation)
### Endpoints (with request/response JSON examples — VALIDATE ALL JSON IS VALID)
### Error Response Format (status codes, error codes, response schema)
### Seed Data (exact IDs, descriptions, image URLs)

## Phase 2: Frontend / Mobile Client (omit for API-only apps)
### Pages/Screens and Components
### State Management
### API Client
### Platform-Specific Notes (mobile only — Xcode setup, Android Studio, signing, etc.)

## Phase 3: AI Features (omit if not applicable)
### AI Feature 1: <Name>
### AI Feature 2: <Name>
### Environment Variables

## Phase N (final): Deploy to Azure
### Containerization (Dockerfiles, or Functions/App Service config if serverless)
### Azure Resources (AVM modules — list each resource with its module path)
### Bicep Requirements (list every deployment gotcha discovered during testing)
### Deployment (two-stage flow if frontend needs API URL at build time)
### Mobile Distribution (mobile only — TestFlight, Google Play internal testing, API URL configuration)
### Known Deployment Gotchas (document real failures — soft-deleted resources, SKU issues, etc.)
```

Key rules for PLAN.md:
- **Validate ALL JSON** — every request/response example must be valid JSON (check closing brackets)
- **Seed data must be complete** — exact IDs, names, descriptions, prices, image URLs
- **Error format** — specify the exact error response schema the API should return
- **Deployment gotchas** — document every real failure encountered during testing with the fix
- **Model references** — make primary/fallback models journey-specific, verify regional availability, and document model-specific request constraints
- **Data access** — if the app supports multiple database backends, reference the `data-access-abstraction` skill for the repository pattern
- **Stable headings** — README prompts reference exact PLAN section names; rename both in the same change
- **Resolve source contradictions** — when adapting an external plan, state the chosen behavior instead of carrying conflicting decisions into prompts
- **No phantom scripts** — PLAN and README state who creates each generated script, where it lands, and what it verifies

---

## Deployment Patterns

### azure.yaml Structure

```yaml
name: <app-name>
metadata:
  template: <app-name>@0.0.1
services:
  api:
    project: ./api
    host: containerapp
    language: ts
    docker:
      path: ./Dockerfile
  web:
    project: ./client
    host: containerapp
    language: ts
    docker:
      path: ./Dockerfile
infra:
  provider: bicep
  path: ./infra
```

Supported `host` values: `containerapp`, `aks`, `appservice`, `function`, `staticwebapp`, `springapp`. Choose based on your app's compute needs.

### Static Web Apps Pattern

For a browser-only static journey, keep the deployment small:

```yaml
services:
  web:
    project: .
    language: js
    host: staticwebapp
    dist: dist
```

- Prefer `br/public:avm/res/web/static-site`; fall back to raw `Microsoft.Web/staticSites@2023-12-01` only when current AVM inputs block a working deployment, and record why.
- Tag the resource with `azd-service-name: web` and output `WEB_URL`, `STATIC_WEB_APP_NAME`, and `RESOURCE_GROUP_NAME`.
- Use Free SKU and `provider: Custom` when azd deploys directly. Do not create a deployment token or GitHub Actions workflow unless CI/CD is an explicit lesson.
- Static Web Apps has a narrower region list than resource groups. Normalize an unsupported request to a documented supported location such as `eastus2`.
- Use `staticwebapp.config.json` for navigation fallback and security headers.
- Azure Developer CLI rejects a Static Web App whose source and output folder both resolve to `.`. Generate a portable Node.js build script that recreates `dist/`, copies only deployable assets, add an npm `build` script, set `dist: dist`, and inspect the exact output before deployment.
- Record host platform and architecture before Static Web Apps deployment, but do not reject ARM64 automatically. If the SWA publisher returns an architecture error, provide an expandable Troubleshooting recovery. A temporary x64 Azure publisher must require approval, keep the deployment token out of files, logs, and command arguments, delete its exact temporary resource in `finally`, and verify absence. Also offer an approved x64 host when policy prohibits temporary resources. Do not normalize privileged emulation or local Docker.
- Do not add a backend, storage account, persistent application container, local Docker requirement, or unrelated provider registration to a static-only journey. A documented, approved, and verified-deleted temporary ARM64 publisher is a recovery mechanism, not part of the application architecture.

### Dockerfile Patterns

**API (Node.js with native deps):**
```dockerfile
FROM node:24-alpine AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npx tsc -p tsconfig.json

FROM node:24-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi
COPY --from=builder /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

- `.dockerignore`: exclude `node_modules`, `dist`, `*.db`, `.env`. Do NOT exclude `tsconfig.json`.

**API (Python/FastAPI):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- `.dockerignore`: exclude `__pycache__`, `*.pyc`, `.venv`, `*.db`, `.env`.

**Client (React/Vite SPA):**
```dockerfile
FROM node:24-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
COPY . .
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

- `ARG` + `ENV` MUST come BEFORE `npm run build` or the build arg is silently ignored.
- `.dockerignore`: exclude `node_modules`, `dist`, `.env`.

**nginx.conf (SPA routing):**
```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

NO `/api/` proxy block. Each Container App has its own public URL.

For other languages (.NET, Java, Go, etc.), follow the same multi-stage pattern: builder image for compilation → lean runtime image for production. Adapt the base image, package manager, build command, and runtime command for your stack.

### Full Deployment Flow

```
1. Generate azure.yaml with hooks.postdeploy when SPA needs API URL at build time
2. azd env set AZURE_SUBSCRIPTION_ID + azd up
3. postdeploy hook rebuilds frontend (VITE_API_URL) automatically — do not make first success manual
4. Verify the deployed health endpoint and core user flow
5. azd down --force --purge when lab is done
```

If the frontend bakes in a backend URL at build time, always generate `infra/hooks/postdeploy.js` from the `container-apps-deployment` skill and reference it directly from `azure.yaml`. A filtered service deployment may skip project-level hooks, so document direct `node infra/hooks/postdeploy.js` execution. API-only apps skip postdeploy.

**Any host architecture:** Require ACR cloud builds targeting `linux/amd64`. Do not require local Docker, Buildx, emulation, `$BUILDPLATFORM`, or privileged QEMU/binfmt handlers for deployment.

### Pre-Deployment Requirements (once per subscription)

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.DBforPostgreSQL    # if using PostgreSQL
az provider register --namespace Microsoft.ContainerService   # if using AKS
az provider register --namespace Microsoft.CognitiveServices  # if using AI services
az provider register --namespace Microsoft.Search             # if using AI Search
```

### AKS Deployment Pattern

For apps requiring Kubernetes (e.g., Superset with multiple pods, init containers, or complex networking):

```yaml
# azure.yaml for AKS
name: <app-name>
metadata:
  template: <app-name>@0.0.1
services:
  app:
    project: ./src
    host: aks
    language: py    # varies by stack
    docker:
      path: ./Dockerfile
infra:
  provider: bicep
  path: ./infra
```

AKS-specific infrastructure needs:
- **AKS cluster**: `br/public:avm/res/container-service/managed-cluster`
- **Node pool sizing**: D2s_v3 (2 vCores, 8GB) is the minimum practical size (~$85/month each)
- **Standard Load Balancer**: required for public access (~$18/month)
- **Kubernetes manifests**: Deployment, Service, ConfigMap, Secret
- **AKS run-command verification**: route bounded `kubectl` commands through the checked-in fail-closed `node .github/scripts/run-aks-command.mjs` helper; do not require local `kubectl` or accept incomplete/nonzero remote results
- **Init containers**: for database migrations (e.g., `superset db upgrade`)

### Cross-Platform Post-Provision Hooks

Use a hook when configuration needs a value available only after provisioning. Place JavaScript or TypeScript hooks in `infra/hooks/` and reference them directly from `azure.yaml`:

```yaml
hooks:
  postprovision:
    run: ./infra/hooks/postprovision.js
```

For example, n8n's `WEBHOOK_URL` depends on the Container App URL. The CommonJS `.js` hook resolves paths with `__dirname`, reads outputs with `azd env get-value`, and invokes Azure CLI with argument arrays. It must not use Bash variables, `chmod`, pipelines, or interpolated shell strings. On Windows, the only PowerShell-specific code permitted is the static JSON-payload launcher defined by the `container-apps-deployment` skill; don't invoke `.cmd` shims directly through `execFileSync()` or `spawnSync()`. The launcher must reject double quotes for every Windows target and additional shell metacharacters or CR/LF for `.cmd`/`.bat`.

For AKS, attach manifests and a remote script to `az aks command invoke`. Run Helm and `kubectl` inside Azure. Store generated Secret values in a mode-`0600` temporary manifest, never print them, and remove the temporary bundle in `finally`.

---

## Bicep Patterns

### AVM Modules

Prefer Azure Verified Modules from `br/public:avm/...`. If parameter drift, unsupported passthrough, or schema mismatch blocks a working deployment, fall back only that resource to raw `Microsoft.*`, record why, and preserve the same acceptance contract. Common modules:

| Resource | Module |
|----------|--------|
| **Compute** | |
| Container Apps Env | `br/public:avm/res/app/managed-environment` |
| Container Apps | `br/public:avm/res/app/container-app` |
| AKS | `br/public:avm/res/container-service/managed-cluster` |
| App Service Plan | `br/public:avm/res/web/serverfarm` |
| App Service / Functions | `br/public:avm/res/web/site` |
| Static Web App | `br/public:avm/res/web/static-site` |
| **Data** | |
| PostgreSQL Flexible | `br/public:avm/res/db-for-postgre-sql/flexible-server` |
| Azure SQL | `br/public:avm/res/sql/server` |
| Cosmos DB | `br/public:avm/res/document-db/database-account` |
| Redis Cache | `br/public:avm/res/cache/redis` |
| Storage Account | `br/public:avm/res/storage/storage-account` |
| **AI** | |
| AI Search | `br/public:avm/res/search/search-service` |
| AI Foundry | `br/public:avm/ptn/ai-ml/ai-foundry` |
| **Infrastructure** | |
| Monitoring | `br/public:avm/ptn/azd/monitoring` |
| Container Registry | `br/public:avm/res/container-registry/registry` |
| Key Vault | `br/public:avm/res/key-vault/vault` |
| Service Bus | `br/public:avm/res/service-bus/namespace` |

Browse the full AVM catalog: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/

### Managed-Identity ACR Pattern

Don't enable the ACR admin account or pass registry passwords to Container Apps. Use the registry login server as a normal output, then use a two-phase deployment:

1. Provision each Container App with a public placeholder image and system-assigned identity.
2. Assign `AcrPull` on the registry to that identity.
3. Configure the Container App registry entry with the ACR login server and `identity: 'system'`.
4. Deploy the private image only after the role and registry configuration exist.

Some `azd` versions perform the registry step automatically and others don't. Verification must inspect the live Container App registry configuration before declaring success. Use resource-group-scoped wrapper modules only for services that genuinely require `listKeys()`; ACR image pulls don't require admin credentials.

### Required Bicep Settings

- **`azd-service-name` tags** on each container app — azd maps services by these tags
- **Container App startup probe:** `failureThreshold` max is 10 (not 30) with the AVM module
- **AI Search:** SKU `basic`, `disableLocalAuth: false`, `semanticSearch: 'free'`
- **AI Services (Foundry):** `disableLocalAuth: false`, system-assigned managed identity, `allowProjectManagement: true`
- **Raw Foundry fallback:** Deploy the account first, then deploy model children from a nested Bicep module that receives the created account name; do not race account and model creation
- **Entra-admin inputs:** Preflight and persist the complete principal ID, login, and type group, with separate `User` and `ServicePrincipal` handling
- **Azure SQL firewall names:** Use neutral names such as `AllowAzureServices`; avoid reserved words such as `WINDOWS`
- **Container Apps:** `zoneRedundant: false` for regions that don't support it (e.g., West US)
- **Outputs:** Use SCREAMING_SNAKE_CASE (e.g., `AZURE_CONTAINER_REGISTRY_ENDPOINT`)
- **PostgreSQL SKU:** Include both `name` AND `tier` — omitting tier causes deployment failure
- **`uniqueString()` module parameters:** Add `@minLength(13)` and `@maxLength(13)` when passing the token across a module boundary

### Soft-Deleted Cognitive Services

If a previous deployment was torn down, AI Services resources are soft-deleted for 48 hours and block re-creation. Before redeploying:

```bash
az cognitiveservices account list-deleted
az cognitiveservices account purge --name <name> --resource-group <rg> --location <location>
```

---

## Teaching Markers (Full-Stack Journeys)

Place these after each GitHub Copilot generation step:

**🔍 Inspect** — immediately after generation, tell the learner exactly what to check:
```markdown
**🔍 Inspect what was generated:**
Open the order creation route. Look for:
1. Does it validate that all product IDs exist and are active?
2. Does it check inventory before creating the order?
3. Does it capture `priceAtPurchase` from the product's current price (not the request)?
```

**💡 What you're learning** — explain the meta-skill:
```markdown
**💡 What you're learning:** Complex business logic is where AI generation needs the most
human review. GitHub Copilot gets CRUD right but often misses multi-step validation.
```

**🧪 Try it yourself** — portable verification with a generated Node.js script:
````markdown
**🧪 Test it yourself:**
```text
node scripts/verify-api.mjs
```
````

Immediately before this command, the journey must include the exact prompt that creates `scripts/verify-api.mjs`, its required assertions, cleanup behavior, and nonzero failure contract. Never assume a learner already has a workspace-only script.

---

## Writing Rules

### Opening Hook
- Lead with what the learner gets, not what the app is
- Bad: "In this journey, you'll deploy X, a Y platform, to Azure..."
- Good: "Want Y on Azure without writing Bicep? Tell an agent what you want and it deploys it in 20 minutes."

### Time Estimates
- Do not include time estimates anywhere in a journey (no header estimate, no per-phase estimate, no "N hours" claims). Learners work at different speeds and hit different issues.
- Durations that describe Azure behavior (for example "PostgreSQL provisioning takes several minutes") are fine — they describe the platform, not the learner.

### Cost Callouts
- Always show cost in the prereqs box as **if left running**, plus same-day teardown
- For expensive journeys ($100+/month or AKS ~$200), bold skip/budget guidance
- Use human-readable SKU names (not "PerGB2018")

### Plain Language
- Write learner-facing prose in the simplest words that keep the technical meaning. Save precise jargon for prompts and reference tables, where an agent or a returning reader needs it.
- Explain a term the first time it appears, or replace it: "Intel or AMD chip" instead of "x86-64 host", "safe to run again" instead of "idempotent", "same result every run" instead of "deterministic".
- Never put a rare edge case in Prerequisites. If it affects a small subset of machines, move it to Troubleshooting and open with who it applies to and who can skip it.
- In Troubleshooting, lead with what happened in plain terms, then what to do. Give a simpler alternative when one exists.

### Tone
- Conversational and direct, like a senior dev pair-programming with you
- No AI-generated filler: "crucial", "comprehensive", "leverage", "seamless", "fostering"
- No "In this agentic journey, you'll..." opening pattern
- Use "you" not "the learner" or "the developer"

### Copilot Naming
- Narrative / learner instructions: **"GitHub Copilot"** (works for CLI, app, or IDE)
- Terminal product only when showing `copilot` or CLI-only notes: **"GitHub Copilot CLI"** or **"Copilot CLI"**
- In GitHub (issues/PRs): **"GitHub Copilot cloud agent"**
- Never bare **"Copilot"** without qualifier

### Images
- Hero image at top, deployment architecture image before deploy step
- Titles in dark navy (#1e3a5f), tight placement (minimal whitespace)
- Optimize: 1200px max width, JPEG quality 80, progressive, <100KB each

---

## Repo Integration

After creating a new journey, update these files:

1. **Root `README.md`** — Agentic journeys table (what you'll do, cost — no time column; journeys carry no time estimates at all)

2. **`AGENTS.md`** — project structure and skills table

3. **Root prerequisites** — only tools common to ALL journeys (Azure CLI, azd, GitHub Copilot, Git). Language runtimes and optional local Docker or `kubectl` tooling go in the journey's additional prerequisites.

4. **No journey numbering** — journeys are self-contained with no prescribed order. Do not add "Journey N of M", stage numbers, or path-completion language anywhere.

5. **Images** — generate with the `technical-image-generator` skill using the established palette:
   - White background, soft light blue and gray accents
   - Titles in dark navy (#1e3a5f) Helvetica Bold 42pt
   - Optimize: 1200px max width, JPEG quality 80, progressive, <100KB each

6. **Checked-in deployment verifier** — add `.github/scripts/verify-<journey>.mjs`, list it in `AGENTS.md`, and make the README state the exact PASS contract.

7. **Workspace-only issue log** — do not commit `journeys/<app>/issues.md`. Prompts create it only when the learner's generated copy encounters a real issue.

---

## Checklist

Before considering a journey complete:

### Content & Quality

- [ ] Opening hook passes the "does a developer care yet?" test
- [ ] No learner time estimates anywhere (header, phases, or prose)
- [ ] Prose uses plain language; jargon is explained on first use or moved into prompts and reference tables
- [ ] Rare host or platform edge cases live in Troubleshooting, not Prerequisites
- [ ] Cost "if left running" + same-day teardown called out
- [ ] No journey-sequence/path numbering; numbered phases and steps inside the journey are clear and bounded
- [ ] Done when checklist + verify script where applicable
- [ ] Full-stack: one-line default stack at first generate prompt (details live in PLAN.md)
- [ ] Isolated workspace prompt copies all required agent, skill, script, and docs context
- [ ] Acceptance criteria separate local, deployed, screenshot, and cleanup completion
- [ ] Every generated verifier or diagnostic has a creation prompt before its run command
- [ ] No bare "Copilot" — use "GitHub Copilot" in narrative; "GitHub Copilot CLI" / "cloud agent" only when product-specific
- [ ] No AI-generated filler words or summary paragraphs
- [ ] All JSON examples are valid (check closing brackets!)
- [ ] SKU names are human-readable in cost tables (not "PerGB2018")
- [ ] Any AI model and fallback are journey-specific, region-checked, and consistent between PLAN and README
- [ ] Images optimized (1200px, JPEG, <100KB)

### Structure & Sections

- [ ] Architecture diagram shows all Azure resources
- [ ] Plugin setup: only `microsoft/azure-skills` / `azure@azure-skills`
- [ ] Plugin availability confirmation occurs before Azure generation
- [ ] Exact-error recovery prompt asks for root cause, smallest fix, rerun, verifier, and real issue logging
- [ ] Troubleshooting covers real errors from actual deployments (Symptom/Cause/Fix format)
- [ ] Assignment guides discovery (do → observe → ask agent → fix)
- [ ] Cleanup section with `azd down --force --purge`
- [ ] What's Next lists related journeys as plain links (no path/completion language)
- [ ] OSS journeys: Configuration Reference section (env vars, container resources, health probes)
- [ ] OSS journeys: Key Learnings (4-5 max) don't repeat troubleshooting content
- [ ] Full-stack journeys: "The Spec" section linking to PLAN.md
- [ ] Full-stack journeys: Teaching markers (🔍, 💡, 🧪) in each phase
- [ ] Full-stack journeys: "How Agentic AI is Used" section with use case table

### Deployment & Infrastructure

- [ ] `azd-service-name` tags on all container apps in Bicep
- [ ] Pre-deployment provider registration commands included
- [ ] `AZURE_SUBSCRIPTION_ID` set explicitly before `azd up`
- [ ] VITE_API_URL handled via **postdeploy hook** (if React frontend) — not manual-only first success
- [ ] Soft-deleted Cognitive Services warning (if using AI services)
- [ ] Platform flag `--platform linux/amd64` documented (if Docker builds)
- [ ] Windows, Mac, and Linux prerequisite and command paths reviewed
- [ ] Stateful verification uses portable scripts or paired Bash and PowerShell examples
- [ ] Browser verification uses Playwright's bundled Chromium
- [ ] Read-only pre-deployment review fails closed with file/line evidence
- [ ] Agent prepares provider and environment inputs; learner runs `azd up`
- [ ] Required lifecycle hooks are CommonJS `.js` or `.ts`, not unsupported `.mjs` or host-specific `.sh`/`.ps1`
- [ ] Wrapper module pattern used for resources needing `listKeys()` (if subscription-scoped)
- [ ] Health probe timing tested with actual startup time

### Repo Integration

- [ ] Journey added to root README journey table
- [ ] AGENTS.md updated (project structure + skills table)
- [ ] Checked-in deployment verifier added and listed in AGENTS.md
- [ ] No source-journey `issues.md` was added
- [ ] Additional prerequisites in journey README (not root)
