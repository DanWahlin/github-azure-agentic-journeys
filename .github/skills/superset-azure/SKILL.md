---
name: superset-azure
description: Deploy Apache Superset on Azure. Use when deploying Superset for BI/data visualization with PostgreSQL backend.
---

# Apache Superset on Azure Skill

Deploy Apache Superset data visualization platform on Azure Kubernetes Service.

> **Complexity Note**: Superset is the most complex deployment in this project due to psycopg2 requirements and AKS architecture. Deploy time: ~15-20 minutes.

## Critical: Infrastructure Generation

This skill provides Superset-specific configuration only. Infrastructure (Bicep, azure.yaml, K8s manifests) should be generated fresh each time by the official `azure-prepare` → `azure-validate` → `azure-deploy` pipeline. Do NOT rely on pre-existing infra code.

## Critical: Subscription Context

**ALWAYS set AZURE_SUBSCRIPTION_ID explicitly before running `azd up`:**
```bash
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
```
Without this, azd and Azure MCP tools will fail silently or produce incomplete deployments.

## Critical: PostgreSQL SKU Format

Azure PostgreSQL Flexible Server requires BOTH `sku.name` and `sku.tier`:
```bicep
sku: {
  name: 'Standard_B1ms'    // NOT 'B_Standard_B1ms'
  tier: 'Burstable'        // REQUIRED - omitting causes deployment failure
}
```

## Critical: PostgreSQL AVM Module Defaults

The AVM PostgreSQL module (`br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2`) has defaults that break password-based apps:

```bicep
module postgresServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2' = {
  params: {
    // ... other params
    publicNetworkAccess: 'Enabled'    // Default is Disabled — firewall rules silently ignored
    highAvailability: 'Disabled'      // Required for Burstable tier
    authConfig: {
      passwordAuth: 'Enabled'         // Default is Disabled (Entra-only)!
      activeDirectoryAuth: 'Disabled'
    }
  }
}
```

Without these, Superset will fail with "authentication failed" or "connection timeout".

## Critical: AKS AVM Module Defaults

The AVM AKS module (`br/public:avm/res/container-service/managed-cluster`) has defaults that cause deployment failures:

```bicep
module aksCluster 'br/public:avm/res/container-service/managed-cluster:0.9.0' = {
  params: {
    // ... other params
    disableLocalAccounts: false       // Default requires AAD integration
    primaryAgentPoolProfiles: [
      {
        name: 'system'
        availabilityZones: []         // Some regions (e.g., westus) don't support AZ
        // ...
      }
    ]
  }
}
```

- **`disableLocalAccounts: false`** — AVM defaults to disabling local accounts, which requires AAD integration. Without AAD, deployment fails with "disableLocalAccounts can only be set on Azure AD integration enabled cluster."
- **`availabilityZones: []`** — AVM may default to zone 1. Some regions (westus) don't support AZ for AKS. Explicitly set to empty array to avoid "AvailabilityZoneNotSupported" errors.

## Critical: Pin Passwords for Redeploy Safety

**Do NOT rely on `newGuid()` for PostgreSQL passwords.** See n8n-azure skill for details. Pin passwords to azd env variables:

```bash
azd env set POSTGRES_PASSWORD "$(openssl rand -hex 16)"
azd env set SUPERSET_SECRET_KEY "$(openssl rand -hex 32)"
azd env set SUPERSET_ADMIN_PASSWORD "$(openssl rand -hex 16)"
```

## Quick Start (Verified)

```bash
# 1. Register providers (one-time per subscription)
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Create environment
azd env new my-superset-env

# 3. Set required variables (passwords pinned — safe for redeploy)
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "$(openssl rand -hex 16)"
azd env set SUPERSET_SECRET_KEY "$(openssl rand -hex 32)"
azd env set SUPERSET_ADMIN_PASSWORD "$(openssl rand -hex 16)"

# 4. Deploy (~15-20 minutes)
azd up

# 5. Access Superset
azd env get-value SUPERSET_URL
# Login: admin / $(azd env get-value SUPERSET_ADMIN_PASSWORD)
```

**Deployment time breakdown:**
- Resource Group: ~4s
- PostgreSQL Flexible Server: ~4-5 min
- AKS Cluster: ~8-10 min
- Kubernetes resources: ~2-3 min
- **Total: ~15-20 minutes**

## Key Configuration Files

| File | Purpose |
|------|---------|
| `config/environment-variables.md` | All Superset environment variables |
| `config/health-probes.md` | Health probe timing for Superset startup |
| `troubleshooting.md` | Common issues and solutions |

## Superset Overview

Apache Superset is a modern data exploration and visualization platform. It requires:
- **Backend Database**: PostgreSQL (production) or SQLite (dev only)
- **PostgreSQL Driver**: psycopg2-binary (NOT included in official image!)
- **Cache/Celery Broker**: Redis (optional but recommended)
- **Web Server**: Gunicorn serving Flask app on port 8088
- **Config File**: superset_config.py that reads SQLALCHEMY_DATABASE_URI from env
- **Initialization**: Database migrations and admin user creation on first run

## Architecture on AKS

```mermaid
graph TB
    LB["Load Balancer<br/>(Public IP)"]

    subgraph AKS["AKS Cluster"]
        NGINX["NGINX Ingress Controller"]
        SVC["Superset Service<br/>(ClusterIP:80)"]
        subgraph POD["Superset Deployment"]
            INIT["Init Container (migrate)"]
            MAIN["Main Container (web · port 8088)"]
            CM["ConfigMap (config.py)"]
            VOL["emptyDir (psycopg2)"]
        end
    end

    PG["PostgreSQL Flexible Server<br/>(Azure Managed PaaS)"]

    LB --> NGINX --> SVC --> POD
    POD --> PG
```

## Critical Configuration

### psycopg2-binary (REQUIRED)

The official Superset image does NOT include psycopg2 for PostgreSQL. Without it, Superset falls back to SQLite. See [references/psycopg2-installation.md](references/psycopg2-installation.md) for the full solution.

**TL;DR**: Install to emptyDir volume with `--target=/psycopg2-lib`, set `PYTHONPATH=/psycopg2-lib` in both init and main containers.

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SQLALCHEMY_DATABASE_URI` | PostgreSQL connection string | `postgresql://USER:PASS@HOST:5432/DB?sslmode=require` |
| `SUPERSET_SECRET_KEY` | Flask secret key (required) | 32+ char random string |
| `SUPERSET_CONFIG_PATH` | Path to config file | `/app/pythonpath/superset_config.py` |
| `PYTHONPATH` | Include psycopg2 location | `/psycopg2-lib` |

See [config/environment-variables.md](config/environment-variables.md) for full details.

**Critical**: Azure PostgreSQL requires `sslmode=require` in the connection string.

### Kubernetes Manifests

See [references/kubernetes-manifests.md](references/kubernetes-manifests.md) for complete Deployment, ConfigMap, and Ingress patterns.

## Health Checks

See [config/health-probes.md](config/health-probes.md) for liveness, readiness, and startup probe configuration. Key values: `/health` on port `8088`, `initialDelaySeconds: 90` for liveness (Superset is slow to start).

## Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Superset Web | 250m | 1000m | 512Mi | 2Gi |
| Init Container | (inherits) | (inherits) | (inherits) | (inherits) |

**⚠️ CPU Gotcha:** Standard_DS2_v2 (2 vCPU) only has ~500m available after AKS system pods. Set CPU **request** to 250m (not 500m) or the pod will be stuck in `Pending` with "Insufficient cpu". CPU **limit** can stay at 1000m for bursting.

## Common Issues & Solutions

See [troubleshooting.md](troubleshooting.md) for detailed fixes. Most common: psycopg2 import errors (install to `/psycopg2-lib` with `PYTHONPATH`), SQLite fallback (check `superset_config.py` ConfigMap), and SSL connection errors (add `?sslmode=require`).

## Azure MCP Tools

Use these Azure MCP Server tools for Superset deployments:

| Tool | When to Use |
|------|-------------|
| `azure_deploy_plan` | Generate a deployment plan — use params: `target=AKS`, `provisioning_tool=AZD` |
| `azure_bicep_schema` | Get latest schemas for `Microsoft.ContainerService/managedClusters` and `Microsoft.DBforPostgreSQL/flexibleServers` |
| `azure_deploy_iac_guidance` | AKS-specific Bicep best practices — use `resource_type=aks` |
| `azure_deploy_app_logs` | Fetch Log Analytics logs post-deployment to troubleshoot pod CrashLoopBackOff or init failures |
| `azure_deploy_architecture` | Generate Mermaid architecture diagrams for the Superset AKS deployment |

## Deployment Checklist

Before verifying: ensure PostgreSQL has a firewall rule, AKS has kubectl access, ConfigMap has `superset_config.py`, K8s secret has `SQLALCHEMY_DATABASE_URI` + `SUPERSET_SECRET_KEY` + `ADMIN_PASSWORD`, and `PYTHONPATH=/psycopg2-lib` is set. See [troubleshooting.md](troubleshooting.md) for the full verification checklist.

## Default Credentials

For testing only (change in production):
- Username: `admin`
- Password: Set via `ADMIN_PASSWORD` env var

## Cost Estimate (Dev Environment)

| Resource | Monthly Cost |
|----------|--------------|
| AKS Cluster (2x Standard_D2s_v3) | ~$100-150 |
| PostgreSQL Flexible Server (B1ms) | ~$15 |
| Load Balancer | ~$20 |
| **Total** | **~$135-185/month** |

**Note:** Superset on AKS is more expensive than Container Apps deployments (n8n, Grafana). Consider Container Apps if AKS features aren't required.

## Tear Down

```bash
azd down --force --purge
```

**Note:** Teardown takes 5-10 minutes (AKS + PostgreSQL deletion is slow).

## Verification

After deployment completes:

```bash
# 1. Check pod status (expected: 1/1 Running)
kubectl get pods -n superset

# 2. Verify PostgreSQL (expected: "Context impl PostgresqlImpl")
kubectl logs -n superset <pod> -c superset-init | grep -i "PostgresqlImpl"

# 3. Verify psycopg2 installed
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"

# 4. Test health endpoint (expected: HTTP 200)
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://$EXTERNAL_IP/health

# 5. Test login page (expected: HTTP 200)
curl -I http://$EXTERNAL_IP/login/
```
