# Agentic Journey 02: Grafana on Azure Container Apps

> ✨ **No external database, no complex probes, just Grafana on Container Apps.**

<p align="center">
  <img src="./images/grafana-observability.jpg" alt="Grafana: Observability on Azure" width="800" />
</p>

In this agentic journey, you'll deploy [Grafana OSS](https://grafana.com/oss/grafana/), the industry-standard observability platform, to Azure Container Apps. Grafana uses an embedded SQLite database by default, so there's no external database to provision. That makes it one of the simplest deployments in the project. You'll also look at when to swap SQLite for PostgreSQL.

## Learning Objectives

- Deploy Grafana to Azure Container Apps using agentic AI
- Understand why Grafana deploys with minimal configuration (no external database, fast startup)
- Evaluate SQLite vs PostgreSQL for different environments
- Use `/api/health` for reliable health probes
- Handle scale-to-zero cold starts gracefully

> ⏱️ **Estimated Time**: ~15 minutes
>
> 💰 **Estimated Cost**: ~$10-20/month (see [Cost Breakdown](#cost-breakdown)). Remember to clean up with `azd down` when done!
>
> 📋 **Prerequisites**: Azure CLI, Azure Developer CLI, and GitHub Copilot CLI. See [prerequisites](../../README.md#prerequisites) for installation links.

---

## Architecture

```mermaid
graph TB
    subgraph RG["Azure Resource Group"]
        LA["Log Analytics Workspace"]
        subgraph CAE["Container Apps Environment"]
            GF["Grafana Container App<br/>Port 3000 · SQLite (default)<br/>Scale 0-3 replicas"]
        end
    end

    LA -->|logs & metrics| CAE

    style RG fill:#e8f4fd,stroke:#0078D4
    style CAE fill:#f0f9ff,stroke:#50e6ff
    style GF fill:#fff,stroke:#0078D4
    style LA fill:#fff,stroke:#50e6ff
```

**Azure resources created:**

- **Azure Container Apps** — Serverless hosting with scale-to-zero
- **Azure Log Analytics** — Monitoring and diagnostics
- **SQLite** (default) — Embedded database, no external dependency
- Optional: **Azure Database for PostgreSQL Flexible Server** for production persistence

**Infrastructure directory:** [`infra-grafana/`](../../infra-grafana/) (generated at repo root during deployment)

---

## Deploy with the Agent

You'll use `@oss-to-azure-deployer` in GitHub Copilot CLI to generate and deploy the entire infrastructure through conversation.

### Step 1: Setup

Make sure you're in the repo root first:

```bash
cd github-azure-agentic-journeys
```

Then start Copilot CLI:

```bash
copilot
```

Once inside the interactive session, add the marketplace (first time only):

```
> /plugin marketplace add microsoft/azure-skills
```

Then install the plugin:

```
> /plugin install azure@azure-skills
```

> **Already installed?** The plugin persists across sessions. If you've done a previous journey, skip the install commands.
> For more details, see the [azure-skills repository](https://github.com/microsoft/azure-skills).

Now select the deployment agent:

```
> /agent
```

Select **`oss-to-azure-deployer`** from the list. You're now in an interactive session with the deployment agent.

### Step 2: Deploy

<p align="center">
  <img src="./images/azure-deployment.jpg" alt="Deploy Grafana to Azure" width="800" />
</p>

Tell the agent what you want in a single prompt:

```
> Deploy Grafana to Azure using Bicep and azd. Set the location to westus, generate a secure admin password, and resolve any issues that come up.
```

The agent handles the entire deployment:

1. Loads the right skills (`grafana-azure`, `azure-container-apps`, `azure-bicep-generation`, `azd-deployment`)
2. Generates a lean Bicep structure in `infra-grafana/` — no PostgreSQL module needed (SQLite is the default)
3. Updates `azure.yaml`, registers Azure providers, sets environment variables
4. Runs `azd up` (~2 minutes)

You can ask follow-up questions anytime:

```
> Should I use PostgreSQL instead of SQLite for Grafana?
```

The agent explains: SQLite is fine for dev/testing but dashboards are lost on container restart. For production, either mount Azure Files to `/var/lib/grafana` or switch to PostgreSQL.

### Step 3: Verify

Ask the agent to confirm everything is working:

```
> Verify the Grafana deployment is working. Check the health endpoint.
```

You can also verify manually (open a new terminal or exit Copilot CLI with `Ctrl+C` first):

```bash
GRAFANA_URL=$(azd env get-value GRAFANA_URL)
curl -s "$GRAFANA_URL/api/health"
# Expected: {"commit":"...","database":"ok","version":"10.x.x"}
```

If something goes wrong, just ask. You're still in the same session:

```
> Grafana is returning 502 errors
```

The agent will check if it's a cold start issue (scale-from-zero takes 30-60s) or a real problem.

---

## Configuration Reference

### Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `GF_SECURITY_ADMIN_USER` | `admin` | Admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | (secret) | Admin password |
| `GF_SERVER_HTTP_PORT` | `3000` | HTTP port |
| `GF_SERVER_ROOT_URL` | Auto-configured | Public URL |
| `GF_AUTH_ANONYMOUS_ENABLED` | `false` | Disable anonymous access |
| `GF_DATABASE_TYPE` | `sqlite3` | Default database |
| `GF_LOG_MODE` | `console` | Log output mode |
| `GF_LOG_LEVEL` | `info` | Log verbosity |

### Container Resources

| Setting | Value |
|---------|-------|
| Image | `docker.io/grafana/grafana:latest` |
| CPU | 0.5 cores |
| Memory | 1 GiB |
| Min Replicas | 0 (scale-to-zero) |
| Max Replicas | 3 |
| Scale Rule | HTTP requests (10 concurrent per replica) |

### Health Probes

Grafana starts fast (~15-30 seconds) and provides a dedicated health endpoint at `/api/health`.

| Probe | Initial Delay | Period | Failure Threshold |
|-------|---------------|--------|-------------------|
| Startup | — | 10s | 30 (5 min max) |
| Liveness | 15s | 30s | 3 |
| Readiness | — | 10s | 3 |

Health endpoint response:
```json
{"commit": "abc123", "database": "ok", "version": "10.x.x"}
```

### Storage: SQLite vs PostgreSQL

**SQLite (default):**
- Zero setup — embedded in the container
- ⚠️ Dashboards lost on container restart (ephemeral storage)
- Good for dev/testing

**PostgreSQL (production):**
Add these environment variables for persistent storage:

```yaml
GF_DATABASE_TYPE: postgres
GF_DATABASE_HOST: your-server.postgres.database.azure.com
GF_DATABASE_NAME: grafana
GF_DATABASE_USER: grafana
GF_DATABASE_PASSWORD: <secret>
GF_DATABASE_SSL_MODE: require
```

**Alternative:** Mount Azure Files to `/var/lib/grafana` for persistent SQLite.

---

## Cost Breakdown

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Container Apps (scale-to-zero) | Consumption (0.5 vCPU, 1GB) | ~$5-10 |
| Log Analytics | Pay-per-GB | ~$2-5 |
| **Total (SQLite)** | | **~$10-20/month** |
| + PostgreSQL (optional) | B_Standard_B1ms | +~$15/month |

---

## Troubleshooting

### Container Won't Start

Ask the agent to diagnose:

```
> My Grafana container won't start. Check the logs and tell me what's wrong.
```

The agent uses `azure_deploy_app_logs` to pull logs and identify the issue — typically health probes that are too aggressive. The Bicep templates in `infra-grafana/` include proper timing.

### 502 Bad Gateway

**Cause:** This typically happens on the first request after the container scales from zero. Cold start takes 30-60s. This is a one-time delay, not a persistent issue.

**Fix:** Wait 30-60 seconds and retry. For production, set `minReplicas: 1` to keep one instance warm.

### Login Fails

**Cause:** Password not set correctly, or special characters causing shell escaping issues.

**Fix:**

Ask the agent:

```
> My Grafana login isn't working. Check if the admin password environment variable is set correctly.
```

If the agent finds shell escaping issues, use alphanumeric passwords and redeploy.

### Dashboards Lost After Restart

**Cause:** SQLite stores data in ephemeral container storage.

**Fix:**
1. Add Azure Files volume mount for `/var/lib/grafana`
2. Switch to PostgreSQL backend (recommended for production)
3. Export dashboards as JSON and use Grafana provisioning

---

> **Post-Deployment Issues:** The following issues relate to *using* Grafana after deployment, not the deployment itself.

### Can't Connect to Data Sources

**Fix:**
1. Ensure data sources are in the same VNet or publicly accessible
2. For Azure services, use private endpoints
3. Check NSG rules if using VNet integration

### Out of Memory (OOMKilled)

**Fix:** Increase memory in Bicep:
```bicep
resources: {
  cpu: json('0.5')
  memory: '2Gi'  // Increase from 1Gi
}
```

---

## Verification Checklist

Ask the agent to run a full verification:

```
> Verify my Grafana deployment: check the health endpoint, test admin login, and confirm the container is running.
```

Or verify manually (open a new terminal or exit Copilot CLI with `Ctrl+C` first):

```bash
GRAFANA_URL=$(azd env get-value GRAFANA_URL)

# Health check (expect HTTP 200 with JSON)
curl "$GRAFANA_URL/api/health"
```

---

## Cleanup

```bash
azd down --force --purge
```

Teardown takes 3-5 minutes (Container Apps environment deletion is slow).

---

## Key Learnings

- **No database ≠ no persistence problem** — SQLite is ephemeral in containers; know this before deploying
- **Scale-to-zero cold starts are normal** — 30-60s on first request isn't an error
- **Same agent, different skills** — the agent loaded `grafana-azure` instead of `n8n-azure` and adapted automatically
- **Simpler apps = simpler infrastructure** — no database dependency means fewer moving parts to break

---

## Assignment

1. Create a dashboard in Grafana, then restart the container app with `az containerapp revision restart` — notice your dashboard is gone. Why? Ask the agent: *"Why did my Grafana dashboard disappear after a restart?"*
2. Try the fix: ask the agent *"How do I make Grafana dashboards persist across restarts?"* and implement what it suggests
3. Clean up with `azd down --force --purge`

---

## What's Next

In [Agentic Journey 03: Apache Superset](../superset/README.md), you'll tackle the most complex deployment, a full BI platform on Azure Kubernetes Service. You'll learn why some applications need Kubernetes instead of Container Apps, and how the agent handles init containers, shared volumes, and psycopg2 installation.

> 📚 **See all agentic journeys:** [Back to overview](../../README.md#agentic-journeys)

---

## Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
