# 🔄 n8n on Azure Container Apps

Deploy [n8n](https://n8n.io) (workflow automation platform) to Azure using Bicep and Azure Developer CLI (azd).

> **Deploy time:** ~7 minutes | **Cost:** ~$25-35/month (dev) | **Complexity:** Medium

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
│  (B_Standard_B1ms, 32GB, version 16)                       │
└─────────────────────────────────────────────────────────────┘
```

**Azure resources created:**

- **Azure Container Apps** — Serverless hosting with scale-to-zero
- **Azure Database for PostgreSQL Flexible Server** — Managed database for persistent storage
- **Azure Log Analytics** — Centralized monitoring and logging
- **User-Assigned Managed Identity** — Secure access to Azure resources

**Infrastructure directory:** [`../infra-n8n/`](../infra-n8n/)

## Prerequisites

- **Azure Subscription** with permissions to create resources
- **Azure CLI** (`az`) — [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Azure Developer CLI** (`azd`) — [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- **Bash or PowerShell** for running deployment scripts

## Quick Start

### 1. Register Azure Resource Providers

**Run these first** to avoid 409 conflicts:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
```

### 2. Set Required Variables

```bash
azd env new my-n8n-env
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "$(openssl rand -base64 16)"
azd env set N8N_BASIC_AUTH_PASSWORD "$(openssl rand -base64 16)"
```

### 3. Update azure.yaml

Make sure the root `azure.yaml` points to the n8n infra directory:

```yaml
name: n8n-azure

infra:
  provider: bicep
  path: infra-n8n

hooks:
  postprovision:
    posix:
      shell: sh
      run: ./infra-n8n/hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./infra-n8n/hooks/postprovision.ps1
```

### 4. Deploy

```bash
azd up
```

This will:
1. Create all Azure resources (Container Apps, PostgreSQL, Log Analytics)
2. Deploy the n8n container
3. Run post-provision hooks to configure `WEBHOOK_URL`

**Deployment time breakdown:**
| Stage | Time |
|-------|------|
| Resource Group | ~4s |
| Log Analytics | ~25s |
| Container Apps Environment | ~38s |
| PostgreSQL Flexible Server | ~4-5 min |
| n8n Container App | ~20s |
| **Total** | **~7 minutes** |

### 5. Access n8n

```bash
azd env get-value N8N_URL
# Login: admin / <your N8N_BASIC_AUTH_PASSWORD>
```

## Configuration

### Environment Variables

The deployment automatically configures these n8n environment variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `DB_TYPE` | `postgresdb` | Database type |
| `DB_POSTGRESDB_HOST` | Azure PostgreSQL FQDN | Database server address |
| `DB_POSTGRESDB_PORT` | `5432` | PostgreSQL port |
| `DB_POSTGRESDB_DATABASE` | `n8n` | Database name |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` | Required for Azure PostgreSQL |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `false` | Azure cert compatibility |
| `DB_POSTGRESDB_CONNECTION_TIMEOUT` | `60000` | 60s timeout for cold starts |
| `N8N_ENCRYPTION_KEY` | Auto-generated | Encryption key for credentials |
| `N8N_BASIC_AUTH_ACTIVE` | `true` | Enable basic authentication |
| `N8N_PORT` | `5678` | n8n default port |
| `N8N_PROTOCOL` | `https` | Protocol for generated URLs |
| `WEBHOOK_URL` | Auto-configured | Set by post-provision hook |

### Container Resources

| Setting | Value |
|---------|-------|
| Image | `docker.io/n8nio/n8n:latest` |
| CPU | 1.0 core |
| Memory | 2 GiB |
| Min Replicas | 0 (scale-to-zero) |
| Max Replicas | 3 |
| Scale Rule | HTTP requests (10 concurrent per replica) |

### Health Probes

n8n requires **60+ seconds** to start. Without proper health probes, Azure kills the container before initialization completes.

| Probe | Initial Delay | Period | Failure Threshold | Max Wait |
|-------|---------------|--------|-------------------|----------|
| Startup | — | 10s | 30 | 5 minutes |
| Liveness | 60s | 30s | 3 | — |
| Readiness | — | 10s | 3 | — |

### Secrets Management

Sensitive values are stored as Container App secrets and referenced via `secretRef`:

- `postgres-password` → `DB_POSTGRESDB_PASSWORD`
- `n8n-encryption-key` → `N8N_ENCRYPTION_KEY`
- `n8n-auth-password` → `N8N_BASIC_AUTH_PASSWORD`

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Container Apps (scale-to-zero) | Consumption (1 vCPU, 2GB) | ~$5-15 |
| PostgreSQL Flexible Server | B_Standard_B1ms (32GB) | ~$15 |
| Log Analytics | PerGB2018 (30-day retention) | ~$2-5 |
| **Total** | | **~$25-35/month** |

Scale-to-zero keeps costs low during idle periods. For production with `minReplicas: 1`, expect ~$60-80/month for Container Apps alone.

## Troubleshooting

### Container CrashLoopBackOff

**Symptom:** Container restarts repeatedly, logs show health check failures.

**Cause:** n8n needs 60+ seconds to start — default health probes kill it too early.

**Fix:** Ensure health probes are configured with `initialDelaySeconds: 60` on liveness and `failureThreshold: 30` on startup. The Bicep templates in `../infra-n8n/` already include this.

```bash
# Check container logs
APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)
az containerapp logs show --name $APP_NAME --resource-group $RG --follow
```

### Database Connection Refused

**Symptom:** n8n logs show `ECONNREFUSED` or SSL handshake errors.

**Fix:**
1. Always use PostgreSQL **FQDN** (not internal hostname)
2. Enable SSL: `DB_POSTGRESDB_SSL_ENABLED=true`
3. Set `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` (Azure cert compatibility)
4. Increase connection timeout to 60s for cold starts

### WEBHOOK_URL Not Set

**Symptom:** Webhooks don't work, static assets fail to load.

**Cause:** Circular dependency — FQDN isn't known until Container App is created.

**Fix:** The post-provision hook handles this automatically. Manual fix:

```bash
N8N_FQDN=$(az containerapp show --name $APP_NAME --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" -o tsv)
az containerapp update --name $APP_NAME --resource-group $RG \
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN"
```

### Resource Provider 409 Conflicts

**Fix:** Register providers before deployment:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
```

### newGuid() Bicep Error

`newGuid()` can only be used as a **parameter default value**:

```bicep
# ❌ Wrong
var encryptionKey = newGuid()

# ✅ Correct
@secure()
param n8nEncryptionKey string = newGuid()
```

## Verification Checklist

After `azd up` completes:

```bash
# 1. Get URL
N8N_URL=$(azd env get-value N8N_URL)

# 2. Test HTTP response (expect 200)
curl -s -o /dev/null -w "%{http_code}" "$N8N_URL"

# 3. Verify n8n page loads
curl -s "$N8N_URL" | grep -o "<title>[^<]*</title>"

# 4. Check WEBHOOK_URL is set
az containerapp show --name $APP_NAME --resource-group $RG \
  --query "properties.template.containers[0].env[?name=='WEBHOOK_URL'].value" -o tsv

# 5. Check container logs
az containerapp logs show --name $APP_NAME --resource-group $RG --tail 20
```

## Cleanup

```bash
azd down --force --purge
```

Teardown takes 5-10 minutes (PostgreSQL deletion is slow). This permanently deletes all data — export workflows first.

## 🤖 Copilot Agent & Skills

This deployment is powered by the **`@oss-to-azure-deployer`** Copilot agent ([`.github/agents/oss-to-azure-deployer.agent.md`](../.github/agents/oss-to-azure-deployer.agent.md)) with these skills:

| Skill | Purpose |
|-------|---------|
| [`n8n-azure`](../.github/skills/n8n-azure/SKILL.md) | n8n-specific configuration, environment variables, health probes, troubleshooting |
| [`azure-bicep-generation`](../.github/skills/azure-bicep-generation/SKILL.md) | Bicep patterns for Container Apps, PostgreSQL, Log Analytics, naming conventions |
| [`azd-deployment`](../.github/skills/azd-deployment/SKILL.md) | azure.yaml configuration, post-provision hooks, deployment workflows |

Ask `@oss-to-azure-deployer` in GitHub Copilot to deploy n8n, troubleshoot issues, or modify the infrastructure.

## Key Learnings

- **Health probes are critical** — n8n needs 60s initial delay and 5-minute startup allowance
- **Always use PostgreSQL FQDN** with SSL enabled
- **`SSL_REJECT_UNAUTHORIZED=false`** is safe for Azure (connection is still encrypted)
- **Post-provision hooks** solve the WEBHOOK_URL circular dependency
- **Register providers first** — prevents 409 conflicts during deployment
- **`newGuid()`** only works as a Bicep parameter default value

## Resources

- [n8n Documentation](https://docs.n8n.io/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
