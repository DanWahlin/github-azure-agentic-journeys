# 📈 Apache Superset on Azure Kubernetes Service

Deploy [Apache Superset](https://superset.apache.org/) (data exploration and BI platform) to Azure using Bicep, AKS, and Azure Developer CLI (azd).

> **Deploy time:** ~15-20 minutes | **Cost:** ~$135-185/month (dev) | **Complexity:** Complex

## Architecture

```
                    ┌──────────────────────────────────┐
                    │        Load Balancer             │
                    │     (Public IP: External)        │
                    └──────────────┬───────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │              AKS Cluster               │
              │    ┌───────────────┴───────────────┐   │
              │    │     NGINX Ingress Controller   │   │
              │    └───────────────┬───────────────┘   │
              │                    │                    │
              │    ┌───────────────┴───────────────┐   │
              │    │     Superset Deployment        │   │
              │    │    - Init Container (migrate)  │   │
              │    │    - Main Container (web)      │   │
              │    │    - ConfigMap (config.py)     │   │
              │    │    - emptyDir (psycopg2)       │   │
              │    │    Port: 8088                  │   │
              │    └───────────────┬───────────────┘   │
              └────────────────────┼────────────────────┘
                                   │
                    ┌──────────────┴───────────────┐
                    │   PostgreSQL Flexible Server  │
                    │     (Azure Managed PaaS)      │
                    └──────────────────────────────┘
```

**Azure resources created:**

- **Azure Kubernetes Service (AKS)** — Managed Kubernetes cluster (2x Standard_D2s_v3 nodes)
- **Azure Database for PostgreSQL Flexible Server** — Managed database (required)
- **Azure Load Balancer** — Public IP for external access
- **NGINX Ingress Controller** — HTTP routing within the cluster
- **Azure Log Analytics** — Monitoring and diagnostics

**Infrastructure directory:** [`../infra-superset/`](../infra-superset/)

## Why AKS Instead of Container Apps?

Superset requires:
- **Init containers** for database migrations and psycopg2 installation
- **Shared volumes** (emptyDir) between init and main containers
- **ConfigMap mounting** for `superset_config.py`
- **More control** over the deployment lifecycle

These patterns are natural in Kubernetes but complex or unavailable in Container Apps.

## Prerequisites

- **Azure Subscription** with permissions to create resources
- **Azure CLI** (`az`) — [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Azure Developer CLI** (`azd`) — [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- **kubectl** — [Install](https://kubernetes.io/docs/tasks/tools/) (for verification and troubleshooting)

## Quick Start

### 1. Register Azure Resource Providers

```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights
```

### 2. Set Required Variables

```bash
azd env new my-superset-env
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "$(openssl rand -base64 16)"
azd env set SUPERSET_SECRET_KEY "$(openssl rand -base64 32)"
azd env set SUPERSET_ADMIN_PASSWORD "$(openssl rand -base64 16)"
```

### 3. Update azure.yaml

Make sure the root `azure.yaml` points to the Superset infra directory:

```yaml
name: superset-azure

infra:
  provider: bicep
  path: infra-superset

hooks:
  postprovision:
    posix:
      shell: sh
      run: ./infra-superset/hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./infra-superset/hooks/postprovision.ps1
```

### 4. Deploy

```bash
azd up
```

**Deployment time breakdown:**
| Stage | Time |
|-------|------|
| Resource Group | ~4s |
| PostgreSQL Flexible Server | ~4-5 min |
| AKS Cluster | ~8-10 min |
| Kubernetes resources (Deployment, Service, Ingress) | ~2-3 min |
| **Total** | **~15-20 minutes** |

### 5. Access Superset

```bash
azd env get-value SUPERSET_URL
# Login: admin / <your SUPERSET_ADMIN_PASSWORD>
```

## Configuration

### Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `SQLALCHEMY_DATABASE_URI` | `postgresql://...?sslmode=require` | Full PostgreSQL connection string |
| `SUPERSET_SECRET_KEY` | (32+ char string) | Flask secret key for session signing |
| `SUPERSET_CONFIG_PATH` | `/app/pythonpath/superset_config.py` | Path to config file |
| `PYTHONPATH` | `/psycopg2-lib` | Include psycopg2 installation location |
| `ADMIN_USERNAME` | `admin` | Admin username |
| `ADMIN_PASSWORD` | (secret) | Admin password |
| `SUPERSET_WEBSERVER_PORT` | `8088` | Default Superset port |
| `GUNICORN_WORKERS` | `2` | Number of Gunicorn workers |
| `GUNICORN_TIMEOUT` | `120` | Request timeout in seconds |

**Critical:** Azure PostgreSQL requires `?sslmode=require` in the connection string.

### superset_config.py (Required)

⚠️ **Superset does NOT read environment variables directly for database configuration.** You must create a `superset_config.py` that bridges env vars to Superset's config:

```python
import os

SQLALCHEMY_DATABASE_URI = os.environ.get(
    'SQLALCHEMY_DATABASE_URI',
    'sqlite:////app/superset_home/superset.db'
)
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'change-me')

WTF_CSRF_ENABLED = True
WTF_CSRF_EXEMPT_LIST = []
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}
```

This is deployed as a Kubernetes ConfigMap mounted at `/app/pythonpath/`.

### psycopg2 Installation (Critical)

The official `apache/superset:latest` image **does NOT include psycopg2** for PostgreSQL. Without it, Superset silently falls back to SQLite.

**Solution:** Install to an emptyDir volume shared between init and main containers:

```yaml
volumes:
- name: psycopg2-install
  emptyDir: {}

initContainers:
- name: superset-init
  command: ["/bin/sh", "-c"]
  args:
    - |
      pip install psycopg2-binary --target=/psycopg2-lib
      PYTHONPATH=/psycopg2-lib superset db upgrade
      PYTHONPATH=/psycopg2-lib superset fab create-admin ... || true
      PYTHONPATH=/psycopg2-lib superset init
  volumeMounts:
  - name: psycopg2-install
    mountPath: /psycopg2-lib

containers:
- name: superset
  env:
  - name: PYTHONPATH
    value: "/psycopg2-lib"
  volumeMounts:
  - name: psycopg2-install
    mountPath: /psycopg2-lib
```

### Container Resources

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Superset Web | 250m | 1000m | 512Mi | 2Gi |
| Init Container | 100m | 500m | 256Mi | 1Gi |

### Health Probes

Superset takes **60-90+ seconds** to start due to database migrations and Flask initialization.

| Probe | Initial Delay | Period | Failure Threshold | Max Wait |
|-------|---------------|--------|-------------------|----------|
| Startup | — | 10s | 60 | 10 minutes |
| Liveness | 90s | 15s | 5 | — |
| Readiness | 45s | 10s | 5 | — |

Health endpoint: `GET /health` → `{"status": "OK"}` (HTTP 200)

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| AKS Cluster | 2x Standard_D2s_v3 | ~$100-150 |
| PostgreSQL Flexible Server | B_Standard_B1ms | ~$15 |
| Load Balancer | Standard | ~$20 |
| **Total** | | **~$135-185/month** |

⚠️ **Superset on AKS is significantly more expensive** than the Container Apps deployments (n8n ~$25-35, Grafana ~$10-20). Consider Container Apps if AKS features aren't required.

## Troubleshooting

### ModuleNotFoundError: No module named 'psycopg2'

**Also appears as:** `Context impl SQLiteImpl` in logs (should be `PostgresqlImpl`).

**Cause:** psycopg2-binary not installed or not in PYTHONPATH.

**Fix:** Install with `pip install psycopg2-binary --target=/psycopg2-lib` and set `PYTHONPATH=/psycopg2-lib` in **both** init and main containers.

```bash
# Verify psycopg2 is working
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"

# Check which database is in use (expect PostgresqlImpl)
kubectl logs -n superset <pod> -c superset-init | grep -i impl
```

### SQLALCHEMY_DATABASE_URI Not Recognized

**Symptom:** Superset uses SQLite even though the env var is set.

**Cause:** Superset doesn't read env vars directly — it needs `superset_config.py`.

**Fix:** Create a ConfigMap with `superset_config.py` that reads `os.environ.get('SQLALCHEMY_DATABASE_URI')`, mount it, and set `SUPERSET_CONFIG_PATH`.

### Pod Stuck in Init:0/1

**Possible causes:**
1. PostgreSQL not reachable — check firewall rules
2. Wrong credentials — verify connection string
3. psycopg2 not installed — see above

```bash
# Check init container logs
kubectl logs -n superset <pod> -c superset-init

# Test PostgreSQL connectivity from inside the cluster
kubectl run -it --rm debug-pg --image=postgres:15 --restart=Never -- \
  psql "postgresql://USER:PASS@HOST:5432/superset?sslmode=require" -c "SELECT 1;"
```

### "'tcp' is not a valid port number"

**Misleading error.** Actually caused by psycopg2 not being installed. See the psycopg2 fix above.

### Permission Denied During pip install

**Cause:** The Superset container runs as non-root with read-only virtualenv.

**Writable locations:** `/psycopg2-lib` (emptyDir), `/tmp`, `/app/superset_home/.local/`

**Fix:** Always use `pip install --target=/psycopg2-lib` with an emptyDir volume.

### 500 Internal Server Error

**Check:**
1. Main container logs: `kubectl logs -n superset <pod> -c superset`
2. Database connection at runtime vs init (different containers, same config?)
3. Pending migrations: `grep -i "pending\|migration" <logs>`

### Secret Key Error

**Symptom:** `SUPERSET_SECRET_KEY must be a non-empty string`

**Fix:** Ensure `SUPERSET_SECRET_KEY` is set in Kubernetes secrets (32+ characters).

## Verification Checklist

```bash
# 1. Pod is running (expect 1/1 Running)
kubectl get pods -n superset

# 2. Using PostgreSQL not SQLite (expect "PostgresqlImpl")
kubectl logs -n superset <pod> -c superset-init | grep -i "PostgresqlImpl"

# 3. Config file loaded (expect "Loaded your LOCAL configuration")
kubectl logs -n superset <pod> -c superset | grep -i "Loaded"

# 4. psycopg2 installed
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"

# 5. Health endpoint (expect HTTP 200)
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://$EXTERNAL_IP/health

# 6. Login page works (expect HTTP 200)
curl -I http://$EXTERNAL_IP/login/
```

## Cleanup

```bash
azd down --force --purge
```

Teardown takes 5-10 minutes (AKS + PostgreSQL deletion is slow).

## 🤖 Copilot Agent & Skills

This deployment is powered by the **`@oss-to-azure-deployer`** Copilot agent ([`.github/agents/oss-to-azure-deployer.agent.md`](../.github/agents/oss-to-azure-deployer.agent.md)) with these skills:

| Skill | Purpose |
|-------|---------|
| [`superset-azure`](../.github/skills/superset-azure/SKILL.md) | Superset-specific configuration, psycopg2 setup, AKS patterns, troubleshooting |
| [`azure-aks-deployment`](../.github/skills/azure-aks-deployment/SKILL.md) | AKS cluster provisioning, Kubernetes manifest patterns |
| [`azure-bicep-generation`](../.github/skills/azure-bicep-generation/SKILL.md) | Bicep patterns for PostgreSQL, Log Analytics, naming conventions |
| [`azd-deployment`](../.github/skills/azd-deployment/SKILL.md) | azure.yaml configuration, post-provision hooks, deployment workflows |

Ask `@oss-to-azure-deployer` in GitHub Copilot to deploy Superset, debug pod issues, or add Redis caching.

## Key Learnings

- **psycopg2-binary is mandatory** — official image doesn't include it; install to emptyDir with `--target`
- **superset_config.py is required** — Superset won't read env vars directly; ConfigMap is essential
- **PYTHONPATH must include `/psycopg2-lib`** in both init and main containers
- **emptyDir volume shares data between containers** — init installs, main uses
- **Azure PostgreSQL requires `sslmode=require`** — always include in connection string
- **"SQLiteImpl" in logs = misconfiguration** — must see "PostgresqlImpl"
- **Init container logs are separate** — use `-c superset-init` to debug migrations
- **Most expensive deployment** — AKS costs ~$135-185/month vs ~$25-35 for Container Apps

## Resources

- [Apache Superset Documentation](https://superset.apache.org/docs/intro)
- [Azure Kubernetes Service](https://learn.microsoft.com/azure/aks/)
- [Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
