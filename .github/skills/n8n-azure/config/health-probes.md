# n8n Health Probe Configuration

n8n requires extended startup time. **Without proper health probes, Azure will kill the container before initialization completes.**

## The Problem

n8n takes **60+ seconds** to start because it:
1. Connects to PostgreSQL
2. Runs database migrations
3. Initializes the workflow engine
4. Loads existing workflows

Default Container Apps health probes check too early or check the wrong endpoint, causing:
- Container marked unhealthy
- Container killed and restarted
- CrashLoopBackOff cycle
- Deployment appears stuck
- CI verification sees HTTP `000`/timeouts even though TLS/ingress exists

## Required Configuration

### Bicep

n8n exposes a dedicated health endpoint at `/healthz` (`N8N_ENDPOINT_HEALTH`, default `healthz`). Use `/healthz` for Container Apps probes instead of `/`; the UI root can hang or redirect while startup/auth/session assets initialize, which makes it a poor readiness signal.

For CI/end-to-end tests, keep one replica warm with `minReplicas: 1`. Scale-to-zero is fine for demos after validation, but it introduces cold-start ambiguity into automated verification.

```bicep
scale: {
  minReplicas: 1
  maxReplicas: 3
}

probes: [
  {
    type: 'liveness'
    httpGet: {
      port: 5678
      path: '/healthz'
      scheme: 'HTTP'
    }
    initialDelaySeconds: 60
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  }
  {
    type: 'readiness'
    httpGet: {
      port: 5678
      path: '/healthz'
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
      path: '/healthz'
      scheme: 'HTTP'
    }
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 10
  }
]
```

> AVM note: The AVM container app module (`br/public:avm/res/app/container-app`) caps `failureThreshold` at 10. Use `periodSeconds: 30` with `failureThreshold: 10` for the same five-minute startup window. Do not emit `failureThreshold: 30` when using AVM, because it may be rejected or normalized away.

### Terraform

```hcl
liveness_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/healthz"
  initial_delay           = 60
  interval_seconds        = 30
  timeout                 = 10
  failure_count_threshold = 3
}

readiness_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/healthz"
  interval_seconds        = 10
  timeout                 = 5
  failure_count_threshold = 3
  success_count_threshold = 1
}

startup_probe {
  transport               = "HTTP"
  port                    = 5678
  path                    = "/healthz"
  interval_seconds        = 30
  timeout                 = 10
  failure_count_threshold = 10
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
- Uses `/healthz`, not the authenticated UI root
- No initial delay, because the startup probe handles startup protection

### Startup Probe
- **Purpose:** Allow extended startup time
- **`failureThreshold: 10`** × 30s interval = **5 minutes max** when using AVM
- Until startup probe succeeds, liveness/readiness are disabled
- Essential for first-time deployments with database migrations

## Why These Specific Values?

| Setting | Value | Reason |
|---------|-------|--------|
| Min replicas in CI | 1 | Avoid scale-to-zero/cold-start ambiguity during automated verification |
| Liveness `initialDelaySeconds` | 60 | n8n initialization time |
| Liveness `periodSeconds` | 30 | Reduce check frequency once running |
| Startup `failureThreshold` | 10 | AVM cap; paired with 30s period for 5 min startup window |
| Health check path | `/healthz` | n8n dedicated health endpoint, default from `N8N_ENDPOINT_HEALTH` |
| Port | 5678 | n8n default port |

## Verifying Health Probe Configuration

After deployment, check container status, logs, and the dedicated health endpoint:

```bash
APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)
N8N_URL=$(azd env get-value N8N_URL)

az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "{runningStatus:properties.runningStatus,provisioningState:properties.provisioningState,fqdn:properties.configuration.ingress.fqdn,minReplicas:properties.template.scale.minReplicas}"

az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query "[].{name:name,active:properties.active,replicas:properties.replicas,health:properties.healthState}" -o table

for i in {1..30}; do
  code=$(curl -k -sS -o /tmp/n8n-health.txt -w "%{http_code}" --max-time 20 "$N8N_URL/healthz" || true)
  if [ "$code" = "200" ]; then
    echo "n8n health check passed"
    break
  fi
  echo "Waiting for n8n /healthz, attempt $i/30, status=$code"
  az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --tail 20 || true
  sleep 10
done
```

## Common Health Probe Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| CrashLoopBackOff | `initialDelaySeconds` too low | Increase liveness delay to 60+ |
| Deployment hangs | Startup window too low | Use 10 failures × 30s period |
| Container keeps restarting | Wrong port or path | Verify port 5678 and `/healthz` |
| CI gets HTTP `000` after deploy | Scale-to-zero cold start or UI root probe | Use `minReplicas: 1`, `/healthz`, and a readiness polling loop |
| First deploy fails, retry works | Database migration time | Keep five-minute startup window |
