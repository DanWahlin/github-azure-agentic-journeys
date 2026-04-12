# n8n Health Probe Configuration

n8n requires extended startup time. **Without proper health probes, Azure will kill the container before initialization completes.**

## The Problem

n8n takes **60+ seconds** to start because it:
1. Connects to PostgreSQL
2. Runs database migrations
3. Initializes the workflow engine
4. Loads existing workflows

Default Container Apps health probes check too early and too frequently, causing:
- Container marked unhealthy
- Container killed and restarted
- CrashLoopBackOff cycle
- Deployment appears stuck

## Required Configuration

### Bicep

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: {
      port: 5678
      path: '/'
      scheme: 'HTTP'
    }
    initialDelaySeconds: 60    // CRITICAL: Wait 60s before first check
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  }
  {
    type: 'readiness'
    httpGet: {
      port: 5678
      path: '/'
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
      port: 5678
      path: '/'
      scheme: 'HTTP'
    }
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30       // CRITICAL: Allows 5 minutes total
  }
]
```

### Terraform

```hcl
liveness_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/"
  initial_delay           = 60        # CRITICAL: Wait 60s
  interval_seconds        = 30
  timeout                 = 10
  failure_count_threshold = 3
}

readiness_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/"
  interval_seconds        = 10
  timeout                 = 5
  failure_count_threshold = 3
  success_count_threshold = 1
}

startup_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/"
  interval_seconds        = 10
  timeout                 = 5
  failure_count_threshold = 30        # CRITICAL: 5 min total
}
```

## Probe Timing Explained

### Liveness Probe
- **Purpose:** Detect if container is stuck/deadlocked
- **`initialDelaySeconds: 60`** - n8n needs this time to start
- After initial delay, checks every 30 seconds
- 3 consecutive failures = restart container

### Readiness Probe
- **Purpose:** Determine when to send traffic
- Faster checks (every 10s) once container is ready
- No initial delay (startup probe handles that)

### Startup Probe
- **Purpose:** Allow extended startup time
- **`failureThreshold: 30`** × 10s interval = **5 minutes max**
- Until startup probe succeeds, liveness/readiness are disabled
- Essential for first-time deployments with database migrations
- **⚠️ AVM Note:** The AVM container-app module (`br/public:avm/res/app/container-app`) caps `failureThreshold` at 10. To achieve the same 5-minute window, use `periodSeconds: 30` with `failureThreshold: 10` (30s × 10 = 300s).

## Why These Specific Values?

| Setting | Value | Reason |
|---------|-------|--------|
| Liveness `initialDelaySeconds` | 60 | n8n initialization time |
| Liveness `periodSeconds` | 30 | Reduce check frequency once running |
| Startup `failureThreshold` | 30 | Allow 5 min for cold start + migrations |
| Health check path | `/` | n8n serves UI at root |
| Port | 5678 | n8n default port |

## Verifying Health Probe Configuration

After deployment, check container logs:

```bash
# Get app name
APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)

# Stream logs
az containerapp logs show --name $APP_NAME --resource-group $RG --follow

# Check container status
az containerapp show --name $APP_NAME --resource-group $RG \
  --query "properties.runningStatus"
```

## Common Health Probe Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| CrashLoopBackOff | `initialDelaySeconds` too low | Increase to 60+ |
| Deployment hangs | Startup `failureThreshold` too low | Increase to 30 |
| Container keeps restarting | Wrong port or path | Verify 5678 and `/` |
| First deploy fails, retry works | Database migration time | Increase startup threshold |
