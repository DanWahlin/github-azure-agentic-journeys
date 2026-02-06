# Superset Health Probe Configuration

Superset requires extended startup time due to database migrations and initialization. Proper health probe configuration is critical for successful deployment on AKS.

## The Problem

Superset takes **60-90+ seconds** to start because it:
1. Connects to PostgreSQL
2. Runs database migrations (on first deploy)
3. Initializes the Flask application
4. Loads metadata and configurations

Without proper health probes, Kubernetes will:
- Mark the pod as unhealthy
- Kill and restart the container
- Create a CrashLoopBackOff cycle

## Required Configuration

### Kubernetes Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8088
  initialDelaySeconds: 90         # CRITICAL: Wait 90s before first check
  periodSeconds: 15
  timeoutSeconds: 10
  failureThreshold: 5
```

### Kubernetes Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8088
  initialDelaySeconds: 45         # Start checking earlier than liveness
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5
  successThreshold: 1
```

### Kubernetes Startup Probe (Recommended)

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8088
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 60            # CRITICAL: Allows 10 minutes total
```

## Why These Values?

| Setting | Value | Reason |
|---------|-------|--------|
| Liveness `initialDelaySeconds` | 90 | Superset + migrations need this time |
| Startup `failureThreshold` | 60 | First deploy with migrations can take 5-10 minutes |
| Health check path | `/health` | Superset's built-in health endpoint |
| Port | 8088 | Superset default port |

## Complete Deployment Spec

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: superset
spec:
  template:
    spec:
      containers:
      - name: superset
        image: apache/superset:latest
        ports:
        - containerPort: 8088
        livenessProbe:
          httpGet:
            path: /health
            port: 8088
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 10
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8088
          initialDelaySeconds: 45
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 5
        startupProbe:
          httpGet:
            path: /health
            port: 8088
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 60
```

## Probe Comparison: Superset vs Other Apps

| Setting | Superset (AKS) | n8n (Container Apps) | Grafana (Container Apps) |
|---------|----------------|---------------------|-------------------------|
| Port | 8088 | 5678 | 3000 |
| Health path | `/health` | `/` | `/api/health` |
| Liveness `initialDelaySeconds` | 90 | 60 | 15 |
| Startup `failureThreshold` | 60 | 30 | 30 |
| Typical startup time | 60-90s | 60-90s | 15-30s |

## Superset Health Endpoint

Superset's `/health` endpoint returns:

```json
{
  "status": "OK"
}
```

HTTP 200 indicates the application is ready.

## Init Container Considerations

When using init containers for database migrations:

```yaml
initContainers:
- name: superset-init
  image: apache/superset:latest
  command: ["/bin/sh", "-c"]
  args:
    - |
      pip install psycopg2-binary --target=/psycopg2-lib
      PYTHONPATH=/psycopg2-lib superset db upgrade
      PYTHONPATH=/psycopg2-lib superset fab create-admin ... || true
      PYTHONPATH=/psycopg2-lib superset init
```

**Important:** Init containers don't use health probes. Give them ample time:
- Database migrations can take 2-5 minutes on first run
- Set reasonable resource limits to prevent OOM kills
- Check init container logs separately from main container

## Verifying Health Probes

```bash
# Check pod status
kubectl get pods -n superset -w

# Check probe events
kubectl describe pod -n superset <pod-name> | grep -A5 "Events"

# Test health endpoint directly
kubectl exec -n superset <pod> -- curl -s localhost:8088/health

# Or via port-forward
kubectl port-forward -n superset <pod> 8088:8088 &
curl localhost:8088/health
```

## Common Health Probe Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Pod stuck in `Init:0/1` | Migration taking long | Check init container logs |
| `0/1 Running` for minutes | Startup probe in progress | Wait or increase `failureThreshold` |
| CrashLoopBackOff | Probe kills container too early | Increase `initialDelaySeconds` |
| Health returns 500 | Database connection failed | Check PostgreSQL connectivity |
| `/health` returns 404 | Wrong Superset version | Try `/healthcheck` or `/` |

## Debugging Commands

```bash
# Watch pod status
kubectl get pods -n superset -w

# Check all events
kubectl get events -n superset --sort-by='.lastTimestamp'

# Init container logs
kubectl logs -n superset <pod> -c superset-init

# Main container logs
kubectl logs -n superset <pod> -c superset

# Describe for detailed probe status
kubectl describe pod -n superset <pod>
```
