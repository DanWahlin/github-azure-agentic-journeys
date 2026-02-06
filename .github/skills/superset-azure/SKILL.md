---
name: superset-azure
description: Deploy Apache Superset on Azure. Use when deploying Superset for BI/data visualization with PostgreSQL backend.
---

# Apache Superset on Azure Skill

Deploy Apache Superset data visualization platform on Azure Kubernetes Service.

> **Complexity Note**: Superset is the most complex deployment in this project due to psycopg2 requirements and AKS architecture. Deploy time: ~15-20 minutes.

## Quick Start

```bash
# 1. Register providers (one-time per subscription)
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Deploy infrastructure (PostgreSQL + AKS)
cd ~/projects/oss-to-azure/infra-superset
az deployment sub create \
  --name superset-$(date +%s) \
  --location westus \
  --template-file main.bicep \
  --parameters environmentName=superset-prod \
               location=westus \
               postgresPassword="$(openssl rand -base64 16)"

# 3. Get AKS credentials
az aks get-credentials -g rg-superset-prod -n <aks-name> --overwrite-existing

# 4. Deploy Kubernetes resources
kubectl apply -f kubernetes/

# 5. Get external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 6. Access Superset
# URL: http://<EXTERNAL_IP>/login/
# Default: admin / <your admin password>
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

## ⚠️ Critical: psycopg2-binary Installation

The official `apache/superset:latest` image does NOT include psycopg2 for PostgreSQL connections. Without it, Superset falls back to SQLite.

### The Problem
- The image's virtualenv at `/app/.venv` is read-only
- `pip install --user` installs to a location the venv Python doesn't see
- PYTHONPATH alone doesn't work because the venv ignores it

### The Solution
1. Install psycopg2-binary to a writable emptyDir volume:
   ```bash
   pip install psycopg2-binary --target=/psycopg2-lib
   ```

2. Set PYTHONPATH to include this directory in BOTH init and main containers:
   ```yaml
   env:
   - name: PYTHONPATH
     value: "/psycopg2-lib"
   ```

3. Mount the emptyDir in both containers so init installs it and main uses it:
   ```yaml
   volumes:
   - name: psycopg2-install
     emptyDir: {}
   ```

## Critical Configuration

### 1. superset_config.py (ConfigMap)

Superset does NOT read SQLALCHEMY_DATABASE_URI from environment directly. You MUST create a config file:

```python
import os

SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////app/superset_home/superset.db')
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

Mount this at `/app/pythonpath/superset_config.py` and set:
```yaml
env:
- name: SUPERSET_CONFIG_PATH
  value: /app/pythonpath/superset_config.py
```

### 2. Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SQLALCHEMY_DATABASE_URI` | PostgreSQL connection string | `postgresql://...` |
| `SUPERSET_SECRET_KEY` | Flask secret key (required) | 32+ char random string |
| `SUPERSET_CONFIG_PATH` | Path to config file | `/app/pythonpath/superset_config.py` |
| `PYTHONPATH` | Include psycopg2 location | `/psycopg2-lib` |

### 3. Database Connection String Format

```
postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require
```

**Critical**: Azure PostgreSQL requires `sslmode=require`

### 4. Complete Kubernetes Manifest Pattern

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      volumes:
      - name: psycopg2-install
        emptyDir: {}
      - name: superset-config
        configMap:
          name: superset-config
      initContainers:
      - name: superset-init
        image: apache/superset:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            pip install psycopg2-binary --target=/psycopg2-lib
            PYTHONPATH=/psycopg2-lib superset db upgrade
            PYTHONPATH=/psycopg2-lib superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password "$ADMIN_PASSWORD" || true
            PYTHONPATH=/psycopg2-lib superset init
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
      containers:
      - name: superset
        image: apache/superset:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            export PYTHONPATH=/psycopg2-lib:$PYTHONPATH
            exec gunicorn --bind 0.0.0.0:8088 --workers 2 --timeout 120 "superset.app:create_app()"
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        - name: PYTHONPATH
          value: "/psycopg2-lib"
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
```

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
# Option 1: Delete resource group (includes AKS + PostgreSQL)
az group delete --name rg-superset-prod --yes --no-wait

# Option 2: Delete Kubernetes resources only
kubectl delete namespace superset
kubectl delete namespace ingress-nginx
```

**Note:** Resource group deletion takes 5-10 minutes.

## Verification Checklist

After deployment completes:

```bash
# 1. Check pod status
kubectl get pods -n superset
# Expected: 1/1 Running

# 2. Verify PostgreSQL (not SQLite)
kubectl logs -n superset <pod> -c superset-init | grep -i "PostgresqlImpl"
# Expected: "Context impl PostgresqlImpl"

# 3. Check config loaded
kubectl logs -n superset <pod> -c superset | grep -i "Loaded"
# Expected: "Loaded your LOCAL configuration"

# 4. Test health endpoint
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://$EXTERNAL_IP/health
# Expected: HTTP/1.1 200 OK

# 5. Test login page
curl -I http://$EXTERNAL_IP/login/
# Expected: HTTP/1.1 200 OK
```

## Verification Commands

```bash
# Check if using PostgreSQL (should show PostgresqlImpl)
kubectl logs -n superset <pod> -c superset | grep -i impl

# Verify psycopg2 is installed
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"

# Check pod status
kubectl get pods -n superset

# Test URL
curl -I http://<EXTERNAL_IP>/login/
```
