---
name: journey-template
description: |
  Create new agentic journeys from app ideas. Generates README.md (learner walkthrough), PLAN.md (AI-readable spec), and app-specific skills for OSS deployments. Supports any stack (Node.js, Python, .NET, Java, Swift, Kotlin) and Azure service (Container Apps, AKS, Functions, App Service).
  USE FOR: new journey, scaffold journey, create learning experience, generate journey template, add journey to repo, build and deploy app to Azure, create journey README, generate PLAN.md spec, new OSS deployment, new full-stack journey, journey from idea.
  DO NOT USE FOR: modifying existing journeys (use coder), reviewing journey content (use content-reviewer), deploying apps (use oss-to-azure-deployer agent).
---

# Journey Template Skill

Generate a complete agentic journey from a user's app idea. A journey is a hands-on learning experience where developers use Copilot CLI to build and deploy an app to Azure.

## Journey Types

| Dimension | Full-Stack (e.g. AIMarket) | OSS Deployment (e.g. n8n, Grafana, Superset) |
|-----------|---------------------------|----------------------------------------------|
| **What the learner does** | Builds an app from scratch with Copilot CLI | Deploys an existing OSS app via `@oss-to-azure-deployer` agent |
| **Files generated** | README.md + PLAN.md | README.md + app-specific skill in `.github/skills/` |
| **README structure** | "The Journey" with 3-5 phases (adapt to app complexity) | "Deploy with the Agent" with 3 steps (Setup → Deploy → Verify) |
| **Time** | 2-3 hours | 15-30 minutes |
| **Images** | 4-6 (one per phase boundary) | 2 (hero + deployment) |
| **Unique sections** | "The Spec", "How Agentic AI is Used" | "Configuration Reference", "Key Learnings" |
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
3. **Critical: Subscription Context** — `azd env set AZURE_SUBSCRIPTION_ID $(az account show --query id -o tsv)` before deployment
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
# Agentic Journey NN: <App Name> — <Subtitle>

> ✨ **<One-sentence hook — what makes this journey interesting, not a summary>**

<p align="center">
  <img src="./images/<hero-image>.jpg" alt="<Alt text>" width="800" />
</p>

<1-2 sentence intro. Focus on what the learner will accomplish, not a feature list.>

## Learning Objectives

- <Concrete outcomes: "you'll know how to X" not "use X">

> ⏱️ **Estimated Time**: ~NN minutes
>
> 💰 **Estimated Cost**: ~$X-Y/month (<main cost driver> — see [Cost Breakdown](#cost-breakdown)). **Clean up with `azd down` when done!**
>
> 📋 **Prerequisites**: See [prerequisites](../../README.md#prerequisites) for standard installation links.
>
> **Additional prerequisites for this journey:**
> - [Tool](https://link) — why it's needed

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

> **Already installed?** The plugin persists across sessions. If you've done a previous journey, skip the install commands.

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

```bash
azd down --force --purge
```

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

<Link to next journey in the progression>

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
| `Deploy with the Agent` (3 steps) | `The Journey` (4 phases: Build API → Frontend → AI → Deploy) |
| `Configuration Reference` | Omit — specs live in PLAN.md |
| `Key Learnings` | `How Agentic AI is Used` — table of agentic use cases |

Full-stack journeys also add:
- **"The Spec"** section after Architecture — links to PLAN.md with a note: *"This is a spec for AI agents. You don't need to read it — Copilot CLI will."*
- **Phase-level images** — one image at each phase boundary (e.g., spec-to-code, storefront, AI features, deployment)
- **Teaching markers** within each phase (🔍 Inspect, 💡 What you're learning, 🧪 Test it yourself)
- **Two deployment options** in final phase: Option A (Copilot CLI) and Option B (GitHub Copilot cloud agent)

For mobile frontends (iOS/Android), note in the README:
- Backend is deployed to Azure with `azd up`; mobile app runs locally or via TestFlight / Play Store internal testing
- API URL must be configurable (not hardcoded) — use environment config or build schemes
- Mobile app is NOT deployed by azd — only the Azure backend is
- Include device testing instructions (simulator/emulator + physical device)

For AKS deployments (e.g., Superset), add:
- **"Why AKS Instead of Container Apps?"** section after Architecture with architectural justification
- **kubectl-based verification** commands alongside curl commands
- **Complexity note** in the opening if deploy time exceeds 15 minutes

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
| ⏱️ | Time estimate |
| 💰 | Cost estimate |
| 📋 | Prerequisites |
| 🔍 | Inspect what was generated (full-stack only) |
| 💡 | Meta-learning insight (full-stack only) |
| 🧪 | Test it yourself (full-stack only) |
| ⚠️ | Warning or critical note |

---

## PLAN.md Template (Full-Stack Journeys Only)

The PLAN.md is a spec document that Copilot CLI reads to generate code. It is NOT tutorial content. Add a note at the top: "This is a spec for AI agents. You don't need to read it — Copilot CLI will." Reference `journeys/aimarket/PLAN.md` for the complete example.

### Required Sections

```markdown
# <App Name>: <Subtitle> — Spec

<One-sentence description>. This document is the spec — Copilot CLI reads it to generate the implementation.

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
- **Model references** — use gpt-5-mini as primary model, gpt-4o as fallback
- **Data access** — if the app supports multiple database backends, reference the `data-access-abstraction` skill for the repository pattern

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

### Dockerfile Patterns

**API (Node.js with native deps):**
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npx tsc -p tsconfig.json

FROM node:20-alpine
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
FROM node:20-alpine AS builder
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
1. azd up                          → provisions infra + deploys services
2. Verify backend with curl
3. If frontend needs backend URL at build time:
   a. Get the backend URL: API_URL=$(azd env get-value API_URL)
   b. Get the registry: ACR=$(azd env get-value AZURE_CONTAINER_REGISTRY_ENDPOINT)
   c. Rebuild frontend image with the URL as a build arg
   d. Push to ACR and update the container app
4. Verify all services
```

Step 3 is only needed when the frontend bakes in a backend URL at build time (e.g., Vite's `VITE_API_URL`, Angular's `environment.ts`). API-only apps or apps that configure the URL at runtime skip this step.

**Apple Silicon (M1/M2/M3):** Always add `--platform linux/amd64` to `docker build`.

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
- **kubectl verification**: `kubectl get pods`, `kubectl logs`, `kubectl port-forward`
- **Init containers**: for database migrations (e.g., `superset db upgrade`)

### Post-Provision Hooks

Use when configuration needs a value only available after deployment (circular dependency). Place scripts in `infra/hooks/`:

```yaml
# azure.yaml
hooks:
  postprovision:
    - shell: sh
      run: ./infra/hooks/postprovision.sh
```

Example — n8n's `WEBHOOK_URL` needs the Container App URL, which isn't known until after provisioning:

```bash
#!/bin/bash
# infra/hooks/postprovision.sh
CONTAINER_APP_URL=$(azd env get-value CONTAINER_APP_URL)
az containerapp update --name "$APP_NAME" --resource-group "$RG_NAME" \
  --set-env-vars "WEBHOOK_URL=$CONTAINER_APP_URL"
```

---

## Bicep Patterns

### AVM Modules

Always use Azure Verified Modules from `br/public:avm/...`. Common modules:

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

### Wrapper Module Pattern (Critical)

At subscription scope, `existing` resource refs can't use `dependsOn`, so `listKeys()` / `listCredentials()` fail. Solution: create wrapper modules scoped at resource group level.

```bicep
// infra/modules/container-registry.bicep (resource group scope)
param name string
param location string
param tags object

module registry 'br/public:avm/res/container-registry/registry:0.9.3' = {
  name: 'acrModule'
  params: { name: name, location: location, tags: tags, acrSku: 'Basic', acrAdminUserEnabled: true }
}

resource acrRef 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: name
  dependsOn: [registry]   // This works at resource group scope!
}

output loginServer string = '${name}.azurecr.io'
output username string = acrRef.listCredentials().username
output password string = acrRef.listCredentials().passwords[0].value
```

Main template calls the wrapper and reads keys from outputs:
```bicep
module containerRegistry './modules/container-registry.bicep' = {
  name: 'containerRegistry'
  scope: rg
  params: { name: acrName, location: location, tags: tags }
}
// Use: containerRegistry.outputs.password
```

### Required Bicep Settings

- **`azd-service-name` tags** on each container app — azd maps services by these tags
- **Container App startup probe:** `failureThreshold` max is 10 (not 30) with the AVM module
- **AI Search:** SKU `basic`, `disableLocalAuth: false`, `semanticSearch: 'free'`
- **AI Services (Foundry):** `disableLocalAuth: false`, system-assigned managed identity, `allowProjectManagement: true`
- **Container Apps:** `zoneRedundant: false` for regions that don't support it (e.g., West US)
- **Outputs:** Use SCREAMING_SNAKE_CASE (e.g., `AZURE_CONTAINER_REGISTRY_ENDPOINT`)
- **PostgreSQL SKU:** Include both `name` AND `tier` — omitting tier causes deployment failure

### Soft-Deleted Cognitive Services

If a previous deployment was torn down, AI Services resources are soft-deleted for 48 hours and block re-creation. Before redeploying:

```bash
az cognitiveservices account list-deleted
az cognitiveservices account purge --name <name> --resource-group <rg> --location <location>
```

---

## Teaching Markers (Full-Stack Journeys)

Place these after each Copilot CLI generation step:

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
human review. Copilot CLI gets CRUD right but often misses multi-step validation.
```

**🧪 Try it yourself** — manual verification with curl:
```markdown
**🧪 Test it yourself:**
```bash
curl -X POST http://localhost:3000/api/orders ...
```

---

## Writing Rules

### Opening Hook
- Lead with what the learner gets, not what the app is
- Bad: "In this journey, you'll deploy X, a Y platform, to Azure..."
- Good: "Want Y on Azure without writing Bicep? Tell an agent what you want and it deploys it in 20 minutes."

### Time Estimates
- Be honest. If it takes 2 hours with debugging, say 2 hours
- OSS deployments: 15-30 minutes
- Full-stack builds: 2-3 hours

### Cost Callouts
- Always show cost in the prereqs box
- For expensive journeys ($100+/month), add a bold warning
- Use human-readable SKU names (not "PerGB2018")

### Tone
- Conversational and direct, like a senior dev pair-programming with you
- No AI-generated filler: "crucial", "comprehensive", "leverage", "seamless", "fostering"
- No "In this agentic journey, you'll..." opening pattern
- Use "you" not "the learner" or "the developer"

### Copilot Naming
- Terminal tool: "Copilot CLI"
- In GitHub (issues/PRs): "GitHub Copilot cloud agent"
- Never standalone "Copilot" without qualifier

### Images
- Hero image at top, deployment architecture image before deploy step
- Titles in dark navy (#1e3a5f), tight placement (minimal whitespace)
- Optimize: 1200px max width, JPEG quality 80, progressive, <100KB each

---

## Repo Integration

After creating a new journey, update these files:

1. **Root `README.md`** — add the journey to the journey listing table:
   ```markdown
   | NN | [<App Name>](journeys/<app-name>/README.md) | Highlights |
   ```

2. **`AGENTS.md`** — update the project structure tree and add any new skills to the skills table

3. **Root prerequisites** — only tools common to ALL journeys (Azure CLI, azd, Copilot CLI, Git). Language runtimes (Node.js, Python, .NET SDK, Java JDK) and other tools (Docker, kubectl) go in the journey's "Additional prerequisites" section.

4. **Journey numbering** — journeys are numbered sequentially (01, 02, 03...). New journeys get the next number.

5. **Images** — generate with the `technical-image-generator` skill using the established palette:
   - White background, soft light blue and gray accents
   - Titles in dark navy (#1e3a5f) Helvetica Bold 42pt
   - Optimize: 1200px max width, JPEG quality 80, progressive, <100KB each

---

## Checklist

Before considering a journey complete:

### Content & Quality

- [ ] Opening hook passes the "does a developer care yet?" test
- [ ] Time estimate is honest (tested by actually doing it)
- [ ] Cost in prereqs box with main cost driver called out
- [ ] No standalone "Copilot" — always "Copilot CLI" or "GitHub Copilot cloud agent"
- [ ] No AI-generated filler words or summary paragraphs
- [ ] All JSON examples are valid (check closing brackets!)
- [ ] SKU names are human-readable in cost tables (not "PerGB2018")
- [ ] gpt-5-mini is primary model (fallback to gpt-4o)
- [ ] Images optimized (1200px, JPEG, <100KB)

### Structure & Sections

- [ ] Architecture diagram shows all Azure resources
- [ ] Plugin setup section with exact marketplace/install commands
- [ ] Troubleshooting covers real errors from actual deployments (Symptom/Cause/Fix format)
- [ ] Assignment guides discovery (do → observe → ask agent → fix)
- [ ] Cleanup section with `azd down --force --purge`
- [ ] OSS journeys: Configuration Reference section (env vars, container resources, health probes)
- [ ] OSS journeys: Key Learnings (4-5 max) don't repeat troubleshooting content
- [ ] Full-stack journeys: "The Spec" section linking to PLAN.md
- [ ] Full-stack journeys: Teaching markers (🔍, 💡, 🧪) in each phase
- [ ] Full-stack journeys: "How Agentic AI is Used" section with use case table

### Deployment & Infrastructure

- [ ] `azd-service-name` tags on all container apps in Bicep
- [ ] Pre-deployment provider registration commands included
- [ ] `AZURE_SUBSCRIPTION_ID` set explicitly before `azd up`
- [ ] VITE_API_URL rebuild workaround documented (if React frontend)
- [ ] Soft-deleted Cognitive Services warning (if using AI services)
- [ ] Platform flag `--platform linux/amd64` documented (if Docker builds)
- [ ] Wrapper module pattern used for resources needing `listKeys()` (if subscription-scoped)
- [ ] Health probe timing tested with actual startup time

### Repo Integration

- [ ] Journey added to root README journey table
- [ ] AGENTS.md updated (project structure + skills table)
- [ ] Additional prerequisites in journey README (not root)
- [ ] Journey numbered sequentially
