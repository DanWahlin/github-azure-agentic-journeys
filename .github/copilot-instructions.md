# Copilot Instructions

This repository deploys open-source applications (like n8n) to Azure using Bicep/Terraform and Azure Developer CLI (azd).

## Agent & Skill System

This repo uses GitHub Copilot's **agents** and **skills** for organized AI assistance:

- **Agents = WHO** - Personas with specific jobs (~100 lines, workflow-focused)
- **Skills = HOW** - Reusable patterns and implementation details

### Available Agents

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| `@oss-to-azure-deployer` | Deploy OSS apps to Azure | Full deployment journey: requirements → IaC → deploy → verify |

### Available Skills

Skills are loaded automatically based on context:

**Infrastructure patterns:**
| Skill | Purpose |
|-------|---------|
| `azure-bicep-generation` | Generic Bicep patterns (Container Apps, PostgreSQL, Log Analytics, naming) |
| `azure-aks-deployment` | AKS patterns for Kubernetes-based deployments |
| `azd-deployment` | Azure Developer CLI workflows, azure.yaml, post-provision hooks |

**App-specific skills:**
| Skill | Purpose |
|-------|---------|
| `n8n-azure` | n8n workflow automation (Container Apps + PostgreSQL) |
| `grafana-azure` | Grafana visualization (Container Apps + SQLite/PostgreSQL) |
| `superset-azure` | Apache Superset BI platform (AKS + PostgreSQL) |

### Workflow

1. **New deployments:** Use `@oss-to-azure-deployer` to guide the entire journey
2. **Skills load automatically** based on the app being deployed
3. **Troubleshooting:** Reference app-specific troubleshooting.md files

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
az containerapp logs show --name $(azd env get-value N8N_CONTAINER_APP_NAME) \
  --resource-group $(azd env get-value RESOURCE_GROUP_NAME) --follow
```

**Pre-deployment requirement** (run once per subscription):
```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
```

---

## Architecture

- **Infrastructure as Code**: Bicep with modular structure in `infra/modules/`
- **Deployment Tool**: Azure Developer CLI (azd) configured via `azure.yaml`
- **Container Hosting**: Azure Container Apps with scale-to-zero
- **Database**: Azure Database for PostgreSQL Flexible Server
- **Post-provisioning**: Hooks in `infra/hooks/` configure WEBHOOK_URL after deployment

---

## Key Conventions

### Bicep Patterns

- Use `newGuid()` only as parameter defaults (Bicep limitation): `param n8nEncryptionKey string = newGuid()`
- Generate unique resource names with: `uniqueString(subscription().id, environmentName, location)`
- Store abbreviations in `infra/abbreviations.json` for consistent naming
- Output names use SCREAMING_SNAKE_CASE to match azd conventions

### Health Probes (Critical for Container Apps)

Slow-starting apps (like n8n) require extended startup time:
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

## Adding New OSS Applications

To add a new application (e.g., Gitea, Plausible):

### Step 1: Create App-Specific Skill

Create `.github/skills/<app>-azure/` with:
```
<app>-azure/
├── SKILL.md              # Overview, quick start, architecture
├── config/
│   ├── environment-variables.md  # App-specific env vars
│   └── health-probes.md          # Startup timing requirements
└── troubleshooting.md            # Common issues
```

### Step 2: Reuse Generic Skills

Reference existing skills for implementation:
- `azure-bicep-generation` for Container Apps, PostgreSQL, Log Analytics patterns
- `azd-deployment` for azure.yaml and hooks

### Step 3: Document App Quirks

In the app-specific skill, document:
- Required environment variables
- Health probe timing (how long does the app take to start?)
- Database requirements (SSL, connection strings)
- Post-deployment configuration needs

### Example: Adding Gitea

1. Create `.github/skills/gitea-azure/SKILL.md`
2. Document Gitea's environment variables (SSH port, root URL, etc.)
3. Note Gitea's startup time for health probe configuration
4. Use existing `azure-bicep-generation` patterns for infrastructure

**The goal:** Generic patterns stay in `azure-bicep-generation`, app-specific quirks go in the app skill.

---

## Project Structure

```
.github/
├── copilot-instructions.md       # This file (always loaded)
├── agents/
│   └── oss-to-azure-deployer.agent.md  # Main deployment orchestrator
└── skills/
    ├── azure-bicep-generation/   # Generic Bicep patterns
    │   ├── SKILL.md
    │   └── patterns/
    │       ├── container-apps.md
    │       ├── postgresql.md
    │       ├── log-analytics.md
    │       └── naming-conventions.md
    ├── azure-aks-deployment/     # AKS deployment patterns
    │   └── SKILL.md
    ├── azd-deployment/           # azd workflows
    │   └── SKILL.md
    ├── n8n-azure/                # n8n-specific config
    │   ├── SKILL.md
    │   ├── config/
    │   │   ├── environment-variables.md
    │   │   └── health-probes.md
    │   └── troubleshooting.md
    ├── grafana-azure/            # Grafana-specific config
    │   ├── SKILL.md
    │   ├── config/
    │   │   ├── environment-variables.md
    │   │   └── health-probes.md
    │   └── troubleshooting.md
    └── superset-azure/           # Superset-specific config
        ├── SKILL.md
        ├── config/
        │   ├── environment-variables.md
        │   └── health-probes.md
        └── troubleshooting.md
```
