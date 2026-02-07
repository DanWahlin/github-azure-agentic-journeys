# Grafana Health Probe Configuration

Grafana is a fast-starting application compared to n8n or Superset, but still needs proper health probe configuration to handle scale-to-zero cold starts.

## The Problem

While Grafana starts quickly (~30 seconds), Azure Container Apps still needs proper health probe configuration to:
1. Handle scale-from-zero cold starts gracefully
2. Avoid premature container kills during startup
3. Ensure traffic only routes to healthy instances

## Required Configuration

### Bicep

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: {
      port: 3000
      path: '/api/health'
      scheme: 'HTTP'
    }
    initialDelaySeconds: 15       // Grafana starts fast
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  }
  {
    type: 'readiness'
    httpGet: {
      port: 3000
      path: '/api/health'
      scheme: 'HTTP'
    }
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
    successThreshold: 1
  }
  {
    type: 'startup'
    httpGet: {
      port: 3000
      path: '/api/health'
      scheme: 'HTTP'
    }
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30          // Allows 5 minutes total for cold start
  }
]
```

### Terraform

```hcl
liveness_probe {
  transport               = "HTTP"
  port                    = 3000
  path                    = "/api/health"
  initial_delay           = 15        # Grafana starts faster than n8n
  interval_seconds        = 30
  timeout                 = 10
  failure_count_threshold = 3
}

readiness_probe {
  transport               = "HTTP"
  port                    = 3000
  path                    = "/api/health"
  interval_seconds        = 10
  timeout                 = 5
  failure_count_threshold = 3
  success_count_threshold = 1
}

startup_probe {
  transport               = "HTTP"
  port                    = 3000
  path                    = "/api/health"
  interval_seconds        = 10
  timeout                 = 5
  failure_count_threshold = 30        # 5 min total for edge cases
}
```

## Probe Comparison: Grafana vs n8n

| Setting | Grafana | n8n | Reason |
|---------|---------|-----|--------|
| Port | 3000 | 5678 | Application defaults |
| Health path | `/api/health` | `/` | Grafana has dedicated endpoint |
| Liveness `initialDelaySeconds` | 15 | 60 | Grafana starts faster |
| Startup `failureThreshold` | 30 | 30 | Same - allows 5 min for edge cases |

## Grafana Health Endpoint

Grafana provides a dedicated health endpoint that returns:

```json
{
  "commit": "abc123",
  "database": "ok",
  "version": "10.x.x"
}
```

**Use `/api/health`** instead of `/` for health checks because:
- Returns JSON with database status
- More reliable than HTML page
- Faster response time

## Verifying Health Probe Configuration

After deployment:

```bash
# Check direct health endpoint
curl https://<GRAFANA_FQDN>/api/health

# Expected response (HTTP 200):
# {"commit":"...","database":"ok","version":"10.x.x"}

# Check container status
az containerapp show --name <app-name> --resource-group <rg-name> \
  --query "properties.runningStatus"
```

## Common Health Probe Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Cold start takes 30-60s | Scale-to-zero + image pull | Normal - startup probe handles this |
| 502 Bad Gateway | Container not ready yet | Wait for startup probe to complete |
| Container keeps restarting | Wrong port or path | Verify 3000 and `/api/health` |
| Database check fails | SQLite lock or PostgreSQL down | Check database logs |
