---
name: superset-azure
description: Deploy Apache Superset on Azure. Use when deploying Superset for BI/data visualization with PostgreSQL backend.
---

# Apache Superset on Azure Skill

Deploy Apache Superset data visualization platform on Azure Kubernetes Service.

> **Complexity Note**: Superset is the most complex deployment in this project due to psycopg2 requirements and AKS architecture. Deploy time: ~15-20 minutes.

## Quick Start (Verified)

```bash
# 1. Register providers (one-time per subscription)
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Create environment
azd env new my-superset-env

# 3. Set required variables
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "$(openssl rand -base64 16)"
azd env set SUPERSET_SECRET_KEY "$(openssl rand -base64 32)"
azd env set SUPERSET_ADMIN_PASSWORD "$(openssl rand -base64 16)"

# 4. Deploy (~15-20 minutes)
azd up

# 5. Access Superset
azd env get-value SUPERSET_URL
# Login: admin / <your SUPERSET_ADMIN_PASSWORD>
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

```
                    ┌──────────────────────────────┐
                    │        Load Balancer         │
                    │     (Public IP: External)    │
                    └──────────────┬───────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │              AKS Cluster               │
              │    ┌───────────────┴───────────────┐   │
              │    │     NGINX Ingress Controller   │   │
              │    └───────────────┬───────────────┘   │
              │                    │                    │
              │    ┌───────────────┴───────────────┐   │
              │    │        Superset Service        │   │
              │    │          ClusterIP:80          │   │
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

### Liveness Probe
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8088
  initialDelaySeconds: 90
  periodSeconds: 15
  timeoutSeconds: 10
  failureThreshold: 5
```

### Readiness Probe
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8088
  initialDelaySeconds: 45
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5
```

## Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Superset Web | 250m | 1000m | 512Mi | 2Gi |
| Init Container | 100m | 500m | 256Mi | 1Gi |

## Common Issues & Solutions

### 1. ModuleNotFoundError: No module named 'psycopg2'
**Symptom**: Init container or main container fails with psycopg2 import error
**Cause**: psycopg2-binary not installed or not in PYTHONPATH
**Fix**: Install with `--target=/psycopg2-lib` and set `PYTHONPATH=/psycopg2-lib`

### 2. "Context impl SQLiteImpl" in logs
**Symptom**: Superset uses SQLite instead of PostgreSQL
**Cause**: superset_config.py missing or SQLALCHEMY_DATABASE_URI not read from env
**Fix**: Create ConfigMap with superset_config.py that reads from os.environ

### 3. Permission denied during pip install
**Symptom**: `PermissionError: [Errno 13] Permission denied`
**Cause**: Trying to install to read-only virtualenv
**Fix**: Use `pip install --target=/psycopg2-lib` with emptyDir volume

### 4. Init Container Fails
**Symptom**: Pod stuck in `Init:Error`
**Cause**: Database not ready or wrong credentials
**Fix**: Check PostgreSQL firewall rules, verify connection string

### 5. Secret Key Error
**Symptom**: "SUPERSET_SECRET_KEY must be a non-empty string"
**Fix**: Ensure `SUPERSET_SECRET_KEY` env var is set (32+ chars)

### 6. SSL Connection Required
**Symptom**: "SSL connection required"
**Fix**: Add `?sslmode=require` to DATABASE_URL

## Deployment Checklist

- [ ] PostgreSQL Flexible Server created with firewall rule
- [ ] AKS cluster running with kubectl access
- [ ] ConfigMap created with superset_config.py
- [ ] Kubernetes secret created with SQLALCHEMY_DATABASE_URI, SUPERSET_SECRET_KEY, ADMIN_PASSWORD
- [ ] emptyDir volume mounted for psycopg2
- [ ] PYTHONPATH set to /psycopg2-lib in both containers
- [ ] SUPERSET_CONFIG_PATH set to config file location
- [ ] Init container installs psycopg2 and runs migrations
- [ ] Logs show "PostgresqlImpl" not "SQLiteImpl"
- [ ] Superset pod reaches 1/1 Running state
- [ ] Ingress configured with external IP
- [ ] `curl http://<IP>/login/` returns HTTP 200
- [ ] Can login with admin credentials

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
