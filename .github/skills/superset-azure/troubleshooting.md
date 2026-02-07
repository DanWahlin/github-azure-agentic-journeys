# Superset Azure Troubleshooting Guide

This guide covers common issues when deploying Apache Superset on Azure Kubernetes Service.

## Issue 1: psycopg2 Not Found

### Symptoms
```
ModuleNotFoundError: No module named 'psycopg2'
```
or
```
Context impl SQLiteImpl
```
in logs instead of `PostgresqlImpl`

### Root Cause
The official `apache/superset:latest` Docker image does NOT include psycopg2 (the PostgreSQL driver). Without it, Superset falls back to SQLite.

### Why Simple Solutions Don't Work

1. **`pip install psycopg2-binary`** - Goes to user site-packages which the venv Python doesn't see
2. **`pip install --target=/app/.venv/lib/.../site-packages`** - Permission denied (read-only)
3. **Setting PYTHONPATH** - The venv Python ignores PYTHONPATH for certain locations
4. **`uv pip install`** - Also fails with permission denied

### Solution

Use an emptyDir volume as the installation target:

```yaml
volumes:
- name: psycopg2-install
  emptyDir: {}

initContainers:
- name: superset-init
  volumeMounts:
  - name: psycopg2-install
    mountPath: /psycopg2-lib
  command: ["/bin/sh", "-c"]
  args:
    - |
      pip install psycopg2-binary --target=/psycopg2-lib
      PYTHONPATH=/psycopg2-lib superset db upgrade
      # ...

containers:
- name: superset
  env:
  - name: PYTHONPATH
    value: "/psycopg2-lib"
  volumeMounts:
  - name: psycopg2-install
    mountPath: /psycopg2-lib
```

### Verification
```bash
# Should output "PostgresqlImpl"
kubectl logs -n superset <pod> -c superset-init | grep -i impl

# Should not error
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"
```

---

## Issue 2: SQLALCHEMY_DATABASE_URI Not Recognized

### Symptoms
- Superset uses SQLite even though SQLALCHEMY_DATABASE_URI env var is set
- Logs show "SQLiteImpl" instead of "PostgresqlImpl"

### Root Cause
Superset does NOT read SQLALCHEMY_DATABASE_URI directly from the environment. It requires a `superset_config.py` file that explicitly reads the environment variable.

### Solution

Create a ConfigMap with superset_config.py:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: superset-config
  namespace: superset
data:
  superset_config.py: |
    import os
    SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////app/superset_home/superset.db')
    SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'change-me')
```

Mount it and set the path:
```yaml
env:
- name: SUPERSET_CONFIG_PATH
  value: /app/pythonpath/superset_config.py
volumeMounts:
- name: superset-config
  mountPath: /app/pythonpath
```

### Verification
```bash
# Should show "Loaded your LOCAL configuration"
kubectl logs -n superset <pod> -c superset | grep -i "loaded.*config"
```

---

## Issue 3: "'tcp' is not a valid port number"

### Symptoms
```
Error: 'tcp' is not a valid port number
```

### Root Cause
This error is misleading - it's actually caused by psycopg2 not being installed. The error occurs during SQLAlchemy connection string parsing.

### Solution
See Issue 1 - install psycopg2-binary.

---

## Issue 4: Pod Stuck in Init:0/1

### Symptoms
- Pod shows `Init:0/1` status for a long time
- Eventually crashes with `Init:Error` or `Init:CrashLoopBackOff`

### Possible Causes

1. **Database not reachable** - Check PostgreSQL firewall rules
2. **Wrong credentials** - Verify connection string
3. **psycopg2 not installed** - See Issue 1
4. **Config file not mounted** - See Issue 2

### Debugging Steps

```bash
# Check init container logs
kubectl logs -n superset <pod> -c superset-init

# Describe pod for events
kubectl describe pod -n superset <pod>

# Check if PostgreSQL is reachable from inside the cluster
kubectl run -it --rm debug-pg --image=postgres:15 --restart=Never -- \
  psql "postgresql://USER:PASS@HOST:5432/superset?sslmode=require" -c "SELECT 1;"
```

---

## Issue 5: 500 Internal Server Error

### Symptoms
- Pod shows 1/1 Running
- curl returns 500 error
- Health endpoint may work but /login/ fails

### Possible Causes

1. **Database connection failing at runtime** - Different config than init
2. **SQLite being used instead of PostgreSQL** - See Issue 2
3. **Database migrations incomplete** - Init container may have failed silently

### Debugging Steps

```bash
# Check main container logs
kubectl logs -n superset <pod> -c superset

# Look for "Pending database migrations"
kubectl logs -n superset <pod> -c superset | grep -i "pending\|migration\|error"

# Verify database connection
kubectl exec -n superset <pod> -c superset -- python -c "
import os
from sqlalchemy import create_engine
engine = create_engine(os.environ['SQLALCHEMY_DATABASE_URI'])
print(engine.connect())
"
```

---

## Issue 6: Permission Denied Errors

### Symptoms
```
PermissionError: [Errno 13] Permission denied
```

### Root Cause
The Superset container runs as non-root user `superset` with limited write permissions.

### Locations You CAN Write To
- `/psycopg2-lib` (if using emptyDir volume)
- `/app/superset_home/.local/` (user directory)
- `/tmp`

### Locations You CANNOT Write To
- `/app/.venv/lib/python3.10/site-packages/` (read-only)
- `/usr/local/lib/` (read-only)

---

## Issue 7: Readiness Probe Failing

### Symptoms
- Pod stuck at 0/1 READY for a long time
- Eventually becomes 1/1

### Root Cause
Superset takes time to start up, especially on first request when it syncs configuration.

### Solution
Use generous probe timing:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8088
  initialDelaySeconds: 45    # Give it time to start
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5        # Allow multiple failures before giving up
```

---

## Diagnostic Commands Reference

```bash
# Get all resources in superset namespace
kubectl get all -n superset

# Watch pod status
kubectl get pods -n superset -w

# Check init container logs
kubectl logs -n superset <pod> -c superset-init

# Check main container logs
kubectl logs -n superset <pod> -c superset

# Check previous container logs (after restart)
kubectl logs -n superset <pod> -c superset --previous

# Describe pod for events
kubectl describe pod -n superset <pod>

# Execute commands in container
kubectl exec -n superset <pod> -c superset -- <command>

# Get ingress IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test health endpoint
curl http://<IP>/health

# Test login page
curl -I http://<IP>/login/
```

---

## Quick Verification Checklist

Run these commands to verify a healthy deployment:

```bash
# 1. Pod is running
kubectl get pods -n superset
# Expected: 1/1 Running

# 2. Using PostgreSQL not SQLite
kubectl logs -n superset <pod> -c superset-init | grep -i "PostgresqlImpl"
# Expected: "Context impl PostgresqlImpl"

# 3. Config file loaded
kubectl logs -n superset <pod> -c superset | grep -i "Loaded"
# Expected: "Loaded your LOCAL configuration"

# 4. No pending migrations
kubectl logs -n superset <pod> -c superset | grep -i "pending"
# Expected: Empty (no pending migrations)

# 5. HTTP 200 on login page
curl -I http://<IP>/login/
# Expected: HTTP/1.1 200 OK
```

---

## Key Learnings Summary

1. **psycopg2-binary is mandatory** - Official image doesn't include it; install to emptyDir with `--target`
2. **superset_config.py is required** - Superset won't read env vars directly; ConfigMap is essential
3. **PYTHONPATH must include /psycopg2-lib** - Both init and main containers need this
4. **emptyDir volume shares between containers** - Init installs psycopg2, main uses it
5. **Azure PostgreSQL requires sslmode=require** - Always include in connection string
6. **Startup probe allows 10 minutes** - First deploy with migrations takes time
7. **"SQLiteImpl" in logs = misconfiguration** - Must see "PostgresqlImpl" for PostgreSQL
8. **Init container logs are separate** - Use `-c superset-init` to debug migration issues
