# Grafana Azure Deployment Skill

Deploy Grafana OSS to Azure Container Apps using Azure CLI with Bicep.

> **Reproducibility Verified**: This deployment has been tested multiple times from scratch. Deploy time: ~2 minutes.

## Overview

Grafana is an open-source observability platform for metrics, logs, and traces visualization. This skill deploys Grafana OSS (not Azure Managed Grafana) to Azure Container Apps.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Resource Group                         │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │ Log Analytics   │───▶│ Container Apps Environment  │ │
│  │ Workspace       │    │                             │ │
│  └─────────────────┘    │  ┌───────────────────────┐  │ │
│                         │  │ Grafana Container App │  │ │
│                         │  │ - Port 3000           │  │ │
│                         │  │ - SQLite (default)    │  │ │
│                         │  │ - Scale 0-3 replicas  │  │ │
│                         │  └───────────────────────┘  │ │
│                         └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### Deploy with Azure CLI (Recommended)

```bash
cd ~/projects/oss-to-azure/infra-grafana

# Generate a secure password
GRAFANA_PASSWORD=$(openssl rand -base64 16)
echo "Admin password: $GRAFANA_PASSWORD"

# Deploy
az deployment sub create \
  --name grafana-$(date +%s) \
  --location westus \
  --template-file main.bicep \
  --parameters environmentName=grafana-prod \
               location=westus \
               grafanaAdminPassword="$GRAFANA_PASSWORD" \
  --query "properties.outputs" \
  -o json
```

### Alternative: Azure Developer CLI (azd)

> **Note**: azd has a bug with `--no-prompt` and secure parameters. Use interactive mode or Azure CLI instead.

```bash
cd ~/projects/oss-to-azure

# Create azure.yaml pointing to infra-grafana
cat > azure.yaml << 'EOF'
name: grafana-azure
metadata:
  template: grafana-azure-container-apps
infra:
  provider: bicep
  path: infra-grafana
EOF

# Interactive deploy (will prompt for values)
azd init -e grafana-prod
azd up
```

## Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `environmentName` | Environment name (used for resource naming) | - | Yes |
| `location` | Azure region | westus | No |
| `grafanaImage` | Container image | docker.io/grafana/grafana:latest | No |
| `grafanaAdminUser` | Admin username | admin | No |
| `grafanaAdminPassword` | Admin password | - | Yes |

## Environment Variables

Grafana is configured via environment variables in the Container App:

| Variable | Description | Value |
|----------|-------------|-------|
| `GF_SECURITY_ADMIN_USER` | Admin username | From parameter |
| `GF_SECURITY_ADMIN_PASSWORD` | Admin password | From secret |
| `GF_SERVER_HTTP_PORT` | HTTP port | 3000 |
| `GF_SERVER_ROOT_URL` | Public URL | Auto-configured |
| `GF_AUTH_ANONYMOUS_ENABLED` | Anonymous access | false |

See [config/environment-variables.md](config/environment-variables.md) for full list.

## Health Probes

| Type | Path | Port | Interval |
|------|------|------|----------|
| Liveness | /api/health | 3000 | 30s |
| Readiness | /api/health | 3000 | 10s |
| Startup | /api/health | 3000 | 10s (30 failures allowed) |

## Outputs

After deployment:
- **GRAFANA_URL**: Public HTTPS URL
- **GRAFANA_FQDN**: Container App FQDN
- **GRAFANA_ADMIN_USER**: Admin username

## Verification

```bash
# Health check
curl https://<GRAFANA_FQDN>/api/health

# Admin login test
curl -u admin:YourPassword https://<GRAFANA_FQDN>/api/org
```

## Scaling

- **Min replicas**: 0 (scale to zero when idle)
- **Max replicas**: 3
- **Scaling rule**: HTTP concurrent requests (10 per replica)

## Storage Considerations

By default, Grafana uses SQLite which stores data in the container. For production:
1. Add Azure Files for persistent storage
2. Or use PostgreSQL/MySQL backend

## Tear Down

```bash
# Option 1: Delete resource group
az group delete --name rg-grafana-prod --yes --no-wait

# Option 2: azd
azd down --force --purge
```

## Comparison with n8n Deployment

| Aspect | Grafana | n8n |
|--------|---------|-----|
| Database | SQLite (default) | PostgreSQL (required) |
| Port | 3000 | 5678 |
| Resources | 0.5 CPU, 1GB RAM | 1 CPU, 2GB RAM |
| Complexity | Simple | Moderate |
| Deploy Time | ~2 minutes | ~5 minutes |

## Lessons Learned

Based on multiple deployment iterations:

1. **Use Azure CLI over azd**: The `azd` CLI has a bug where `--no-prompt` panics on secure parameters. Azure CLI with Bicep is more reliable.

2. **Simple passwords work best**: Avoid special shell characters (`!`, `$`, etc.) in passwords when passing via command line. Use alphanumeric or properly escape.

3. **Grafana starts fast**: Unlike n8n (which needs PostgreSQL), Grafana with SQLite starts in ~30 seconds.

4. **Resource group deletion takes time**: Container Apps environments can take 3-5 minutes to delete. Use `--no-wait` and move on.

5. **Health endpoint is reliable**: `/api/health` returns immediately when Grafana is ready - good for probes.

6. **Scale-to-zero works well**: First request after idle takes ~30-60 seconds due to cold start, but saves costs.

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.
