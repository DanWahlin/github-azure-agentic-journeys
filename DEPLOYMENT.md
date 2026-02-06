# n8n Azure Deployment Guide

Deploy n8n workflow automation to Azure Container Apps with PostgreSQL in ~7 minutes.

## Prerequisites

1. **Azure CLI** - Logged in (`az login`)
2. **Azure Developer CLI (azd)** - Version 1.5+
3. **Subscription** - With permissions to create resources

### One-Time Setup

Register required Azure providers (only needed once per subscription):

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# Verify registration
az provider show --namespace Microsoft.App --query "registrationState"
```

## Quick Start

```bash
# 1. Clone and navigate to project
cd ~/projects/oss-to-azure

# 2. Create a new environment
azd env new my-n8n-env
# Answer 'y' to set as default

# 3. Configure required variables
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"  # or your preferred region
azd env set POSTGRES_PASSWORD "$(openssl rand -base64 16)"
azd env set N8N_BASIC_AUTH_PASSWORD "$(openssl rand -base64 16)"

# 4. Deploy
azd up

# 5. Get URL
azd env get-value N8N_URL
```

## What Gets Deployed

| Resource | Purpose | Approximate Time |
|----------|---------|------------------|
| Resource Group | Container for all resources | ~4s |
| Log Analytics | Monitoring and logs | ~25s |
| Container Apps Environment | Hosting environment | ~38s |
| PostgreSQL Flexible Server | Database (v16, B1ms) | ~4-5 min |
| n8n Container App | The application | ~20s |

**Total deployment time:** ~7 minutes

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                      │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │  n8n Container App  │────│  Log Analytics Workspace    │ │
│  │  (0-3 replicas)     │    │  (monitoring)               │ │
│  └─────────┬───────────┘    └─────────────────────────────┘ │
└────────────┼────────────────────────────────────────────────┘
             │ SSL/TLS (port 5678)
             ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure Database for PostgreSQL Flexible Server              │
│  (Standard_B1ms, 32GB, version 16)                         │
└─────────────────────────────────────────────────────────────┘
```

## Accessing n8n

After deployment:

1. Get the URL: `azd env get-value N8N_URL`
2. Open in browser
3. Login with:
   - **Username:** `admin`
   - **Password:** The value you set for `N8N_BASIC_AUTH_PASSWORD`

## Tear Down

```bash
azd down --force --purge
```

This deletes all resources and purges soft-deleted items (Log Analytics, etc.).

**Note:** Teardown can take 5-10 minutes due to PostgreSQL deletion.

## Cost Estimate (Development)

| Resource | Monthly Cost |
|----------|--------------|
| Container Apps (scale-to-zero) | ~$5-15 |
| PostgreSQL Flexible Server (B1ms) | ~$15 |
| Log Analytics | ~$2-5 |
| **Total** | **~$25-35/month** |

## Configuration Files

| File | Purpose |
|------|---------|
| `azure.yaml` | azd project configuration |
| `infra/main.bicep` | Main infrastructure template |
| `infra/main.parameters.json` | Parameter mapping (uses `${VAR}` interpolation) |
| `infra/modules/*.bicep` | Modular resource definitions |
| `infra/hooks/postprovision.sh` | Sets WEBHOOK_URL after deployment |

## Troubleshooting

### Deployment fails with "no default response for prompt"

The `main.parameters.json` file uses `${VAR_NAME}` syntax to map environment variables. Ensure you've set all required variables:

```bash
azd env get-values  # Check what's set
```

Required variables:
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `POSTGRES_PASSWORD`
- `N8N_BASIC_AUTH_PASSWORD`

### Container in CrashLoopBackOff

n8n needs ~60 seconds to start. The health probes are configured with appropriate delays, but if issues persist:

```bash
# Check logs
az containerapp logs show --name <app-name> --resource-group <rg-name> --follow
```

### Database connection errors

Verify PostgreSQL is accessible and SSL is configured:

```bash
# Check PostgreSQL FQDN
azd env get-value POSTGRES_FQDN

# Verify firewall rule exists
az postgres flexible-server firewall-rule list \
  --resource-group <rg-name> \
  --name <server-name>
```

### Wrong infrastructure deployed (e.g., Grafana instead of n8n)

Check `azure.yaml` points to the correct infrastructure:

```yaml
infra:
  provider: bicep
  path: infra  # Should be 'infra' for n8n, not 'infra-grafana'
```

## Reproducibility Verified

This deployment has been tested multiple times:
- ✅ Fresh environment deployment
- ✅ Teardown and redeploy
- ✅ Parameter interpolation working
- ✅ Post-provision hook sets WEBHOOK_URL
- ✅ HTTP 200 from endpoint
- ✅ n8n login page loads

## Related Skills

- `.github/skills/azure-bicep-generation/` - Bicep patterns
- `.github/skills/azd-deployment/` - azd configuration
- `.github/skills/n8n-azure/` - n8n-specific settings
