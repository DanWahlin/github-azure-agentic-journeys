---
name: n8n-azure-bicep
description: Deploy n8n workflow automation to Azure using Bicep and Azure Developer CLI (azd)
---

# n8n Azure Deployment Skill

Deploy n8n (workflow automation platform) to Azure Container Apps with PostgreSQL using Bicep and azd.

## When to Use This Skill

- User wants to deploy n8n to Azure
- User mentions "n8n", "workflow automation", or "Azure Container Apps"
- User asks about Bicep deployment for n8n

## Quick Start

```bash
cd <project-directory>
# 1. Register Azure providers (one-time)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Initialize and deploy
azd init -e n8n
azd up
```

## Required References

Load these based on what you're doing:

| Task | Load Reference |
|------|----------------|
| Writing Bicep code | `references/bicep-requirements.md` |
| Configuring n8n environment | `references/n8n-config.md` |
| Debugging deployment issues | `references/troubleshooting.md` |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                      │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │  n8n Container App  │────│  Log Analytics Workspace    │ │
│  │  (0-3 replicas)     │    │  (monitoring)               │ │
│  └─────────┬───────────┘    └─────────────────────────────┘ │
└────────────┼────────────────────────────────────────────────┘
             │ SSL/TLS
             ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure Database for PostgreSQL Flexible Server              │
│  (B_Standard_B1ms, 32GB, version 16)                       │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Workflow

### Step 1: Create Project Structure

```
project/
├── azure.yaml                    # azd configuration
├── infra/
│   ├── main.bicep               # Main Bicep template
│   ├── main.parameters.json     # Parameters (gitignored)
│   └── hooks/
│       ├── postprovision.sh     # Linux/macOS hook
│       └── postprovision.ps1    # Windows hook
└── .gitignore
```

### Step 2: Create azure.yaml

Use template from `assets/templates/azure.yaml`:
- Provider: bicep
- Path: infra
- Post-provision hooks for both platforms

### Step 3: Create main.bicep

**Load `references/bicep-requirements.md` for:**
- Resource definitions (Container App, PostgreSQL, Log Analytics)
- Health probe configuration (CRITICAL - see troubleshooting)
- Required outputs for post-provision hooks
- Parameter definitions with proper defaults

### Step 4: Create Parameters File

Use `assets/templates/main.parameters.json.example` as reference.
Required parameters:
- `postgresPassword` - Strong password for PostgreSQL
- `n8nBasicAuthPassword` - Password for n8n web UI

### Step 5: Create Post-Provision Hooks

Copy from `assets/templates/`:
- `postprovision.sh` - Make executable: `chmod +x`
- `postprovision.ps1` - Windows support

### Step 6: Deploy

```bash
# Initialize azd environment
azd init -e n8n

# Deploy (will prompt for missing parameters)
azd up
```

## Key Configuration Points

| Setting | Value | Notes |
|---------|-------|-------|
| Region | westus | Default, configurable |
| Container CPU | 1.0 | Sufficient for dev |
| Container Memory | 2Gi | n8n recommended |
| Replicas | 0-3 | Scale-to-zero enabled |
| PostgreSQL SKU | B_Standard_B1ms | Cost-optimized |
| PostgreSQL Storage | 32GB | Expandable |
| n8n Port | 5678 | Default n8n port |

## Post-Deployment

After `azd up` completes:

1. **Access n8n**: URL shown in output (`https://<app-name>.<region>.azurecontainerapps.io`)
2. **Login**: Use credentials from parameters file
3. **WEBHOOK_URL**: Automatically configured by post-provision hook

## Cleanup

```bash
azd down --force --purge
```

## Troubleshooting

If deployment fails, load `references/troubleshooting.md` for:
- Container crash loops (health probe issues)
- Database connection failures
- Resource provider conflicts
- SSL/certificate issues

## Cost Estimate (Dev Environment)

| Resource | Monthly Cost |
|----------|--------------|
| Container Apps (scale-to-zero) | ~$5-15 |
| PostgreSQL Flexible Server | ~$15 |
| Log Analytics | ~$2-5 |
| **Total** | **~$25-35/month** |

---

**Important**: Always load the appropriate reference file before generating Bicep code or troubleshooting issues.
