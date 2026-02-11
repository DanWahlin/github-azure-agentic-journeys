# Chapter 03: Apache Superset — BI Platform on Azure Kubernetes Service

> **When Container Apps isn't enough, Kubernetes steps in — and the agent knows exactly when and why.**

In this final chapter, you'll deploy [Apache Superset](https://superset.apache.org/) — a powerful data exploration and BI platform — to Azure Kubernetes Service (AKS). This is the most complex deployment in the project: init containers, shared volumes, psycopg2 installation, ConfigMap mounting, and a managed PostgreSQL database. You'll learn why some applications *need* Kubernetes and how the agent handles the complexity for you.

## Learning Objectives

- Understand when AKS is required instead of Container Apps
- Deploy Superset with init containers, shared volumes, and ConfigMap mounting
- Install psycopg2-binary into a shared emptyDir volume for PostgreSQL connectivity
- Use `azure_deploy_plan` with `target=AKS` for Kubernetes deployment planning
- Debug AKS-specific issues: init container failures, CrashLoopBackOff, SQLite fallback

> ⏱️ **Estimated Time**: ~30 minutes (Path 1) or ~20 minutes (Path 2)
>
> 💰 **Estimated Cost**: ~$135-185/month (see [Cost Breakdown](#cost-breakdown)) — remember to clean up with `azd down` when done!
>
> 📋 **Prerequisites**: Azure CLI, Azure Developer CLI, `kubectl`, and optionally GitHub Copilot CLI. See [root README prerequisites](../README.md#prerequisites) for installation links.

---

## Real-World Analogy: The Factory vs The Workshop

Chapters 01 and 02 used Container Apps — like a workshop where you bring in equipment and start working. Superset needs a factory: assembly lines (init containers), shared storage rooms (emptyDir volumes), instruction manuals bolted to the wall (ConfigMaps), and a loading dock (NGINX Ingress).

| Factory | Superset on AKS |
|---------|----------------|
| Assembly line (step 1 → step 2) | Init container installs psycopg2, runs migrations, creates admin |
| Shared storage room | emptyDir volume at `/psycopg2-lib` shared between containers |
| Instruction manual on the wall | ConfigMap with `superset_config.py` mounted at `/app/pythonpath/` |
| Loading dock for deliveries | NGINX Ingress Controller with Load Balancer |
| Quality control station | Health probes at `/health` with 90s initial delay |
| Factory lease | AKS cluster (~$100-150/month vs ~$10-20 for Container Apps) |

The factory is more expensive and complex, but some products simply can't be made in a workshop.

---

## Architecture

```mermaid
graph TB
    LB["Load Balancer<br/>(Public IP)"]

    subgraph RG["Azure Resource Group"]
        LA["Log Analytics Workspace"]
        subgraph AKS["AKS Cluster"]
            NGINX["NGINX Ingress Controller"]
            subgraph POD["Superset Pod"]
                INIT["Init Container<br/>(migrate + psycopg2)"]
                MAIN["Main Container<br/>(Gunicorn · port 8088)"]
                CM["ConfigMap<br/>(superset_config.py)"]
                VOL["emptyDir<br/>(psycopg2-lib)"]
            end
        end
        PG["Azure PostgreSQL Flexible Server<br/>(Managed PaaS)"]
    end

    LB --> NGINX --> POD
    INIT --> VOL
    MAIN --> VOL
    MAIN --> CM
    POD -->|sslmode=require| PG
    AKS -->|logs & metrics| LA

    style RG fill:#e8f4fd,stroke:#0078D4
    style AKS fill:#f0f9ff,stroke:#50e6ff
    style POD fill:#fff,stroke:#0078D4
    style LB fill:#fff,stroke:#0078D4
    style PG fill:#fff,stroke:#0078D4
    style LA fill:#fff,stroke:#50e6ff
```

**Azure resources created:**

- **Azure Kubernetes Service (AKS)** — Managed Kubernetes cluster (2x Standard_D2s_v3 nodes)
- **Azure Database for PostgreSQL Flexible Server** — Managed database (required)
- **Azure Load Balancer** — Public IP for external access
- **NGINX Ingress Controller** — HTTP routing within the cluster
- **Azure Log Analytics** — Monitoring and diagnostics

**Infrastructure directory:** [`../infra-superset/`](../infra-superset/)

### Why AKS Instead of Container Apps?

Superset requires:
- **Init containers** for database migrations and psycopg2 installation
- **Shared volumes** (emptyDir) between init and main containers
- **ConfigMap mounting** for `superset_config.py`
- **More control** over the deployment lifecycle

These patterns are natural in Kubernetes but complex or unavailable in Container Apps.

> **Where does NGINX come from?** The post-provision hook installs the NGINX Ingress Controller into the cluster using Helm. It provides HTTP routing and a public Load Balancer IP for external access.

---

## Path 1: Generate Infrastructure with the Agent

### Step 1: Start Copilot and Install the Azure MCP Plugin

Make sure you're in the repo root first:

```bash
cd oss-to-azure
```

Then start Copilot CLI:

```bash
copilot
```

Once inside the interactive session, install the Azure MCP plugin:

```
> /plugin install microsoft/github-copilot-for-azure:plugin
```

> **Already installed?** If you completed a previous chapter, the plugin persists across sessions — skip this step.

### Step 2: Select the Agent

```
> /agent
```

Select **`oss-to-azure-deployer`** from the list.

### Step 3: Ask the Agent to Deploy Superset

```
> Deploy Apache Superset to Azure using Bicep and azd
```

The agent will:

1. **Load the right skills** — `superset-azure`, `azure-aks-deployment`, `azure-bicep-generation`, and `azd-deployment`
2. **Recommend AKS over Container Apps** — it knows Superset needs init containers, shared volumes, and ConfigMap mounting
3. **Use Azure MCP tools** — `azure_bicep_schema` for API versions, `azure_deploy_iac_guidance` with `resource_type=aks` for AKS-specific best practices
4. **Generate the Bicep + Kubernetes infrastructure** in `infra-superset/`

### Step 4: Review the Generated Infrastructure

Once the agent finishes, check what it created:

```bash
ls -R infra-superset/
```

You should see a more complex structure than Chapters 01-02:

```
infra-superset/
├── main.bicep
├── main.parameters.json
├── abbreviations.json
├── modules/
│   ├── log-analytics.bicep
│   ├── aks.bicep                     # AKS cluster with RBAC
│   ├── postgresql.bicep              # PostgreSQL Flexible Server
│   └── managed-identity.bicep        # For deployment scripts
├── kubernetes/
│   ├── namespace.yaml
│   ├── configmap.yaml                # superset_config.py
│   ├── secrets.yaml                  # Database credentials
│   ├── deployment.yaml               # Init + main containers
│   ├── service.yaml                  # ClusterIP service
│   └── ingress.yaml                  # NGINX ingress
└── hooks/
    ├── postprovision.sh              # kubectl apply + get external IP
    └── postprovision.ps1
```

You can ask follow-up questions in the same session:

```
> Why do you need an init container for psycopg2?
```

The agent explains: The official `apache/superset:latest` image doesn't include psycopg2 for PostgreSQL. Without it, Superset silently falls back to SQLite. The init container installs `psycopg2-binary` to an emptyDir volume, then the main container adds that path to `PYTHONPATH`.

### Step 5: Deploy to Azure

Stay in the same Copilot session and ask the agent to deploy:

```
> Run azd up for the Superset infrastructure you just generated. Set the location to westus and generate secure passwords for all credentials. If there are any issues, resolve them.
```

The agent will:

1. Update `azure.yaml` to point to `infra-superset`
2. Register required providers (`Microsoft.ContainerService`, `Microsoft.DBforPostgreSQL`, `Microsoft.OperationalInsights`)
3. Create an azd environment and set variables (location, passwords, secret key)
4. Run `azd up` (~15-20 minutes)
5. If anything fails — diagnose and fix automatically
6. Run the post-provision hooks (`kubectl apply` for Kubernetes manifests, wait for external IP)

### Step 6: Verify

Once the agent reports success, ask it to verify:

```
> Verify the Superset deployment is working. Check that it's using PostgreSQL not SQLite.
```

You can also verify manually (open a new terminal or exit Copilot CLI with `Ctrl+C` first):

```bash
# Check pod status (expect 1/1 Running)
kubectl get pods -n superset

# Get the pod name
POD=$(kubectl get pods -n superset -o jsonpath='{.items[0].metadata.name}')

# Verify PostgreSQL is being used (not SQLite — look for "PostgresqlImpl")
kubectl logs -n superset $POD -c superset-init | grep -i "PostgresqlImpl"

# Get the external URL
SUPERSET_URL=$(azd env get-value SUPERSET_URL)
curl -I "$SUPERSET_URL/health"  # Expect HTTP 200
```

If the pod is stuck, just ask — you're still in the same session:

```
> My Superset pod is stuck in Init:0/1
```

The agent will use `azure_deploy_app_logs` to diagnose whether it's a PostgreSQL connection issue, psycopg2 installation failure, or credential problem.

---

## Path 2: Deploy Pre-Built Infrastructure

> **No GitHub Copilot CLI required.** This path uses Azure CLI, Azure Developer CLI, and `kubectl`.

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
azd env set POSTGRES_PASSWORD "$(openssl rand -hex 16)"
azd env set SUPERSET_SECRET_KEY "$(openssl rand -hex 32)"
azd env set SUPERSET_ADMIN_PASSWORD "$(openssl rand -hex 16)"
```

### 3. Update azure.yaml

Edit the existing `azure.yaml` in the repo root to point to the Superset infra directory:

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

---

## Configuration Reference

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
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365  # 1 year — extended for long dashboard sessions

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

---

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| AKS Cluster | 2x Standard_D2s_v3 | ~$100-150 |
| PostgreSQL Flexible Server | B_Standard_B1ms | ~$15 |
| Load Balancer | Standard | ~$20 |
| **Total** | | **~$135-185/month** |

⚠️ **Superset on AKS is significantly more expensive** than the Container Apps deployments (n8n ~$25-35, Grafana ~$10-20). Consider Container Apps if AKS features aren't required.

---

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

> **Agent tip:** Ask `@oss-to-azure-deployer` — *"Superset logs show SQLiteImpl"* — and it knows this means psycopg2 isn't installed or PYTHONPATH isn't set.

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

---

## Verification Checklist

```bash
# Get pod name first
POD=$(kubectl get pods -n superset -o jsonpath='{.items[0].metadata.name}')

# 1. Pod is running (expect 1/1 Running)
kubectl get pods -n superset

# 2. Using PostgreSQL not SQLite (expect "PostgresqlImpl")
kubectl logs -n superset $POD -c superset-init | grep -i "PostgresqlImpl"

# 3. Config file loaded (expect "Loaded your LOCAL configuration")
kubectl logs -n superset $POD -c superset | grep -i "Loaded"

# 4. psycopg2 installed
kubectl exec -n superset $POD -c superset -- python -c "import psycopg2; print('OK')"

# 5. Health endpoint (expect HTTP 200)
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://$EXTERNAL_IP/health

# 6. Login page works (expect HTTP 200)
curl -I http://$EXTERNAL_IP/login/
```

---

## Cleanup

```bash
azd down --force --purge
```

Teardown takes 5-10 minutes (AKS + PostgreSQL deletion is slow).

---

## Key Learnings

- **psycopg2-binary is mandatory** — official image doesn't include it; install to emptyDir with `--target`
- **superset_config.py is required** — Superset won't read env vars directly; ConfigMap is essential
- **PYTHONPATH must include `/psycopg2-lib`** in both init and main containers
- **emptyDir volume shares data between containers** — init installs, main uses
- **Azure PostgreSQL requires `sslmode=require`** — always include in connection string
- **"SQLiteImpl" in logs = misconfiguration** — must see "PostgresqlImpl"
- **Init container logs are separate** — use `-c superset-init` to debug migrations
- **Most expensive deployment** — AKS costs ~$135-185/month vs ~$25-35 for Container Apps
- **The agent knows when to use AKS** — it recommends Kubernetes when Container Apps can't handle the requirements

---

## Assignment

**Practice what you learned:**

1. Deploy Superset using **Path 2** — get comfortable with the longer deployment time and AKS workflow
2. Verify that Superset is using PostgreSQL, not SQLite: check for "PostgresqlImpl" in init container logs
3. Try connecting to a sample dataset in the Superset UI — create a chart and a dashboard
4. Start a Copilot CLI session and ask: *"How would I add Redis caching to my Superset deployment?"*
5. Compare the three deployments: Grafana (~$10-20, 2 min), n8n (~$25-35, 7 min), Superset (~$135-185, 15-20 min) — when would you choose each?
6. Clean up with `azd down --force --purge`

---

## What's Next

You've completed all three deployments! Here's where to go from here:

- **Extend the project** — Add a new OSS app by following the guide in [`.github/copilot-instructions.md`](../.github/copilot-instructions.md)
- **Ask the agent** — Start a session with `@oss-to-azure-deployer` and ask *"How would I deploy Gitea to Azure?"*
- **Contribute** — Found a bug or want to add an app? [Open an issue](https://github.com/DanWahlin/oss-to-azure/issues)

---

## Resources

- [Apache Superset Documentation](https://superset.apache.org/docs/intro)
- [Azure Kubernetes Service](https://learn.microsoft.com/azure/aks/)
- [Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
