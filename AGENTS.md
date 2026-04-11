# Agents and Skills

This repository contains agentic journeys that build and deploy applications to Azure using GitHub Copilot agents, skills, and Azure Developer CLI (azd).

## Prerequisites

Install the **Azure Skills plugin** for access to Azure-specific MCP and skills tools (Bicep schemas, deployment planning, architecture diagrams, log analysis):

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

## Agent & Skill System

This repo uses GitHub Copilot's **agents** and **skills** for organized AI assistance:

- **Agents = WHO** - Personas with specific jobs (~100 lines, workflow-focused)
- **Skills = HOW** - Reusable patterns and implementation details

### Available Agents

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@oss-to-azure-deployer` | Deploy OSS apps to Azure | Full deployment journey: requirements -> IaC -> deploy -> verify |

### Available Skills

Skills are loaded automatically based on context:

**App-specific skills:**
| Skill | Purpose |
|-------|---------|
| `n8n-azure` | n8n workflow automation (Container Apps + PostgreSQL) |
| `grafana-azure` | Grafana visualization (Container Apps + SQLite/PostgreSQL) |
| `superset-azure` | Apache Superset BI platform (AKS + PostgreSQL) |

**Development patterns:**
| Skill | Purpose |
|-------|---------|
| `data-access-abstraction` | Repository pattern for swappable data layers (SQLite, Cosmos DB, PostgreSQL) |
| `journey-runner` | Run a journey end-to-end: extract prompts, build, deploy, verify |
| `journey-template` | Create a new agentic journey from an app idea (full-stack or OSS deployment) |
| `journey-test-harness` | Run all journeys as a test suite: build, deploy, screenshot, teardown, report |

### Workflow

1. **OSS deployments:** Use `@oss-to-azure-deployer` to guide the entire journey
2. **Full-stack journeys (e.g., AIMarket):** Follow the journey's PLAN.md and use skills as needed
3. **Skills load automatically** based on the app being deployed
4. **Azure MCP tools** provide real-time schema lookups, deployment planning, and troubleshooting
5. **Troubleshooting:** Reference app-specific troubleshooting.md files and use `azure_deploy_app_logs`

---

## Azure MCP Server Tools

The Azure MCP plugin provides these tools for use throughout the deployment lifecycle:

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `azure_bicep_schema` | Get latest API versions + property definitions | When generating or updating Bicep resource definitions |
| `azure_deploy_iac_guidance` | Bicep/Terraform best practices with azd | When choosing IaC approach or setting up project structure |
| `azure_deploy_plan` | Generate deployment plans | Before `azd up` -- validates configuration and dependencies |
| `azure_deploy_architecture` | Generate Mermaid architecture diagrams | When documenting or visualizing deployment architecture |
| `azure_deploy_app_logs` | Fetch Log Analytics logs | Post-deployment troubleshooting (CrashLoopBackOff, connection errors) |
| `azure_deploy_pipeline` | CI/CD pipeline guidance | When setting up GitHub Actions for automated deployments |
| `azure_terraform_best_practices` | Terraform-specific Azure guidance | When using Terraform instead of Bicep |

---

## Commands

```bash
# Deploy infrastructure
azd up

# Tear down all resources
azd down --purge

# View deployment outputs
azd env get-value <OUTPUT_NAME>

# View container logs
az containerapp logs show --name $(azd env get-value CONTAINER_APP_NAME) \
  --resource-group $(azd env get-value RESOURCE_GROUP_NAME) --follow
```

**Pre-deployment requirement** (run once per subscription):
```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ContainerService  # AKS only
```

---

## Architecture

- **Infrastructure as Code**: Bicep with modular structure per journey
- **Deployment Tool**: Azure Developer CLI (azd) configured via `azure.yaml`
- **Container Hosting**: Azure Container Apps (n8n, Grafana) or AKS (Superset)
- **Database**: Azure Database for PostgreSQL Flexible Server, Cosmos DB, or SQLite (local dev)
- **Post-provisioning**: Hooks configure app-specific settings after deployment (e.g., WEBHOOK_URL)

### Infrastructure Pattern

Each journey contains its own infrastructure. For OSS deployments, infrastructure is generated fresh by the `azure-prepare` plugin skill. For full-stack journeys, infrastructure lives alongside the application code:

```
journeys/<app>/
├── README.md
├── PLAN.md               # Full-stack journeys only
├── azure.yaml
├── infra/
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── abbreviations.json
│   ├── modules/
│   └── hooks/
└── src/                   # Full-stack journeys only
```

---

## Key Conventions

### Bicep Patterns

- **Always use Azure Verified Modules (AVM)** from the `br/public:avm/...` Bicep public registry. Do not write raw resource definitions -- use AVM modules. This ensures best practices, security defaults, and consistency. Reference: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/
- **AI resources** -- use `br/public:avm/ptn/ai-ml/ai-foundry` for Microsoft Foundry (AIServices + Project + model deployments)
- **Monitoring** -- use `br/public:avm/ptn/azd/monitoring` for Log Analytics + Application Insights
- **Container Apps** -- use `br/public:avm/res/app/container-app` and `br/public:avm/res/app/managed-environment`
- **Container Registry** -- use `br/public:avm/res/container-registry/registry`
- **Search** -- use `br/public:avm/res/search/search-service`
- Use `newGuid()` only as parameter defaults (Bicep limitation): `param encryptionKey string = newGuid()`
- Generate unique resource names with: `uniqueString(subscription().id, environmentName, location)`
- Store abbreviations in `infra/abbreviations.json` for consistent naming
- Output names use SCREAMING_SNAKE_CASE to match azd conventions

### Health Probes (Critical for Container Apps)

Slow-starting apps require extended startup time:
- **Liveness probe**: `initialDelaySeconds: 60`
- **Startup probe**: `failureThreshold: 30` (allows 5 minutes)

Without this, containers enter CrashLoopBackOff before initialization completes.

### PostgreSQL Connectivity

Azure PostgreSQL requires specific environment variables:
```
DB_POSTGRESDB_SSL_ENABLED=true
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
DB_POSTGRESDB_CONNECTION_TIMEOUT=60000
```

Always use the FQDN from `postgresServer.properties.fullyQualifiedDomainName`.

---

## Adding New Journeys

### OSS Deployment Journeys

To add a new OSS app deployment (e.g., Gitea, Plausible):

**Step 1: Create app-specific skill** in `.github/skills/<app>-azure/`:
```
<app>-azure/
├── SKILL.md              # Overview, quick start, architecture, verification
├── config/
│   ├── environment-variables.md
│   └── health-probes.md
└── troubleshooting.md
```

SKILL.md must include YAML frontmatter:
```yaml
---
name: <app>-azure
description: Deploy <App> to Azure. Use when deploying <App> for <purpose>.
---
```

**Step 2: Create journey directory** in `journeys/<app>/` with a README.md.

**Step 3: Document app quirks** -- required env vars, health probe timing, database requirements, post-deployment configuration.

### Full-Stack Journeys

To add a new full-stack journey (e.g., AIMarket):

**Step 1: Create journey directory** in `journeys/<app>/` with README.md and PLAN.md.

**Step 2: Create any needed skills** in `.github/skills/` for reusable patterns.

**Step 3: Infrastructure** goes in `journeys/<app>/infra/` with Bicep modules.

---

## Project Structure

```
journeys/
├── n8n/                          # n8n OSS deployment journey
│   └── README.md
├── grafana/                      # Grafana OSS deployment journey
│   └── README.md
├── superset/                     # Apache Superset OSS deployment journey
│   └── README.md
├── smart-todo/                   # Full-stack journey (iOS + Functions + AI)
│   ├── README.md
│   └── PLAN.md
└── aimarket/                    # Full-stack journey (API + frontend + AI)
    ├── README.md
    ├── PLAN.md
    ├── issues.md
    └── src/
.github/
├── agents/
│   └── oss-to-azure-deployer.agent.md
└── skills/
    ├── n8n-azure/                # n8n-specific config
    │   ├── SKILL.md
    │   ├── config/
    │   └── troubleshooting.md
    ├── grafana-azure/            # Grafana-specific config
    │   ├── SKILL.md
    │   ├── config/
    │   └── troubleshooting.md
    ├── superset-azure/           # Superset-specific config
    │   ├── SKILL.md
    │   ├── config/
    │   └── troubleshooting.md
    └── data-access-abstraction/  # Repository pattern for swappable data layers
        └── SKILL.md
    └── journey-template/        # Template for creating new agentic journeys
        └── SKILL.md
    └── journey-runner/          # Run journeys end-to-end: prompts → build → deploy → verify
        └── SKILL.md
    └── journey-test-harness/   # Test suite: run all journeys, deploy, screenshot, teardown
        └── SKILL.md
scripts/
└── setup-journey-tests.sh       # Configure GitHub secrets/variables for CI
AGENTS.md                         # This file
README.md
```
