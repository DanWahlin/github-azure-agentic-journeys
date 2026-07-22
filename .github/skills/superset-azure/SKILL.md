---
name: superset-azure
description: Deploy Apache Superset on Azure. Use when deploying Superset for BI/data visualization with PostgreSQL backend.
---

# Apache Superset on Azure Skill

Deploy Apache Superset data visualization platform on Azure Kubernetes Service.

> **Complexity Note**: Superset is the most complex deployment in this project due to psycopg2 requirements and AKS architecture. Deploy time: ~15-20 minutes.

## Prerequisites and Portability

Require Azure CLI, Azure Developer CLI 1.28.0 or later, and Node.js 24 LTS or later. Verify `az version`, `azd version`, and `node --version` before generating infrastructure. The host must not need `kubectl` or Helm. Installation options for Windows, Mac, and Linux are in `../../../docs/tool-installation.md`.

Generate the AKS post-provision workflow as `infra-superset/hooks/postprovision.js` and reference it directly from `azure.yaml`. The hook must attach the Kubernetes manifests and a remote deployment script to `az aks command invoke`. Run Helm and `kubectl` inside Azure. Invoke `az` and `azd` with argument arrays. On Mac and Linux, call each executable directly. On Windows, use the static PowerShell runner and JSON environment payload defined by the `container-apps-deployment` skill so Azure CLI `.cmd` shims aren't launched directly. Reject double quotes for every Windows target and additional shell metacharacters or CR/LF for `.cmd`/`.bat`; use attached scripts for complex remote commands. Do not generate a Bash-only host hook.

Start the long deployment command with `--no-wait`, parse the returned command ID, and poll `az aks command result`. Require `provisioningState` to equal `Succeeded` and `exitCode` to equal `0`. Use a separate short AKS run command to read the ingress IP so URL discovery does not depend on long-command log truncation.

Write generated Kubernetes Secret values to a mode-`0600` temporary manifest as base64 data. Attach the temporary bundle to AKS run command, do not print the values, delete the remote Secret manifest immediately after `kubectl apply`, and remove the local bundle in `finally` after success or failure.

The hook owns `SUPERSET_SECRET_KEY` and `SUPERSET_ADMIN_PASSWORD`. On a clean environment, generate cryptographically random values for either missing setting, persist each with `azd env set`, never print the values, and reuse existing values on reruns. A first deployment must not depend on undocumented manual secret setup.

## Critical: Infrastructure Generation

This skill provides Superset-specific configuration only. Infrastructure (Bicep, azure.yaml, K8s manifests) should be generated fresh each time by the official `azure-prepare` → `azure-validate` → `azure-deploy` pipeline. Do NOT rely on pre-existing infra code.

## Critical: Subscription Context

**ALWAYS set AZURE_SUBSCRIPTION_ID explicitly before running `azd up`.** Read it with `az account show --query id -o tsv`, then pass the returned value to `azd env set AZURE_SUBSCRIPTION_ID <subscription-id>`. Do not use Bash command substitution when the host OS is unknown.

Without this, azd and Azure MCP tools will fail silently or produce incomplete deployments.

## Critical: PostgreSQL AVM Defaults

**📖 See [../config/postgresql-avm-defaults.md](../config/postgresql-avm-defaults.md) for all PostgreSQL AVM gotchas** (publicNetworkAccess, passwordAuth, HA, password pinning). Without these, Superset will fail with "authentication failed" or "connection timeout".

**Superset-specific:** Pin `POSTGRES_PASSWORD`, `SUPERSET_SECRET_KEY`, and `SUPERSET_ADMIN_PASSWORD` in the azd environment. Generate them with Node's `crypto.randomBytes()` or another cryptographically secure platform API. Do not require `openssl`, which is not installed by default on Windows.

## Critical: AKS AVM Module Defaults

```bicep
module aksCluster 'br/public:avm/res/container-service/managed-cluster:0.9.0' = {
  params: {
    disableLocalAccounts: false       // Default requires AAD — fails without it
    primaryAgentPoolProfiles: [
      { name: 'system', availabilityZones: [] }  // westus doesn't support AZ
    ]
  }
}
```

## Quick Start (Verified)

```text
# 1. Register providers (one-time per subscription)
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Create environment
azd env new my-superset-env

# 3. Set required variables (replace placeholders with collected/generated values)
azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "<generated-secret>"
azd env set SUPERSET_SECRET_KEY "<generated-secret>"
azd env set SUPERSET_ADMIN_PASSWORD "<generated-secret>"

# 4. Deploy (~15-20 minutes)
azd up

# 5. Access Superset
azd env get-value SUPERSET_URL
# Login: admin / value returned by azd env get-value SUPERSET_ADMIN_PASSWORD
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

Before verifying: ensure PostgreSQL has a firewall rule, AKS run command is available, remote Helm installed NGINX Ingress, ConfigMap has `superset_config.py`, K8s secret has `SQLALCHEMY_DATABASE_URI` + `SUPERSET_SECRET_KEY` + `ADMIN_PASSWORD`, and `PYTHONPATH=/psycopg2-lib` is set. See [troubleshooting.md](troubleshooting.md) for the full verification checklist.

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

After deployment completes, run the checked-in verifier from `journeys/superset`:

```text
node ../../.github/scripts/verify-superset.mjs
```

The verifier must use `az aks command invoke` for pod status, logs, and in-pod checks. It must not invoke a local `kubectl` or Helm binary.

For automated browser login, use `#username`, `#password`, and the resilient submit selector `input[type="submit"], button[type="submit"]`. Superset 4.1.1 renders a Flask-AppBuilder submit input; other versions may render a button. Verify successful navigation to `/superset/welcome/`.
