# Grafana on Azure Container Apps

> ✨ **No external database, no complex probes, just Grafana on Container Apps.**

<p align="center">
  <img src="./images/grafana-observability.webp" alt="Grafana: Observability on Azure" width="800" />
</p>

In this agentic journey, you'll deploy [Grafana OSS](https://grafana.com/oss/grafana/), a popular open-source observability platform, to Azure Container Apps. Grafana uses an embedded SQLite database by default, so there's no external database to provision. That makes it one of the simplest deployments in the project. You'll also look at when to swap SQLite for PostgreSQL.

## Learning Objectives

- Deploy Grafana to Azure Container Apps using agentic AI
- Understand why Grafana deploys with minimal configuration (no external database, fast startup)
- Evaluate SQLite vs PostgreSQL for different environments
- Use `/api/health` for reliable health probes
- Handle scale-to-zero cold starts gracefully

> ⏱️ **Estimated Time**: ~15–20 minutes first run
>
> 💰 **Estimated Cost**: ~$10–20/month **if left running** (see [Cost Breakdown](#cost-breakdown)). **Tear down the same day with `azd down --force --purge`.**
>
> 📋 **Prerequisites**
>
> - Azure CLI, Azure Developer CLI 1.28.0+, and an agentic coding tool
> - Node.js 24 LTS or later for portable verification scripts
> - An Azure subscription with permission to create resource groups and Container Apps
>
> See the [cross-platform installation guide](../../docs/tool-installation.md) for Windows, macOS, and Linux setup and verification commands.

> [!NOTE]
> Use [GitHub Copilot CLI](https://github.com/features/copilot/cli), the [GitHub Copilot app](https://github.com/features/ai/github-app), or another agentic coding tool. For other tools, run: **"Copy or adapt this repository's `.github/skills` into your supported skills or instructions location, preserving their behavior and reporting anything unsupported."**

### Done when

- [ ] `$GRAFANA_URL/api/health` returns JSON with `"database":"ok"`
- [ ] Browser login works with admin credentials from the deployment
- [ ] `azd down --force --purge` completed

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

- **Azure Container Apps**: Serverless hosting with scale-to-zero
- **Azure Log Analytics**: Monitoring and diagnostics
- **SQLite** (default): Embedded database, no external dependency
- Optional: **Azure Database for PostgreSQL Flexible Server** for production persistence

> ⚠️ **Storage note:** Grafana uses SQLite by default, which lives inside the container. Dashboards and data sources are lost when the container restarts. See [Storage Considerations](#storage-sqlite-vs-postgresql) for production options.

**Infrastructure directory:** `infra-grafana/` (generated at the repo root when you run the deployment. It won't exist until then)

---

## Deploy with the Agent

You'll use `oss-to-azure-deployer` (a custom agent defined in this repo) with GitHub Copilot to generate and deploy the entire infrastructure through conversation.

> **💡 Tip: Track issues as you go.** When giving GitHub Copilot a prompt, add *"If you encounter any issues, log them to issues.md so they can be tracked and fixed."* This gives GitHub Copilot a place to record problems it finds or fixes during generation, making it easier to iterate and debug.

### Step 1: Setup

Make sure you're in the repo root first:

```bash
cd github-azure-agentic-journeys
```

Then start GitHub Copilot. Examples use the [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started); the app and VS Code agent chat work the same — type the prompts without the leading `>`:

```bash
copilot
```

If you haven't installed the Azure Skills plugin yet, do it now — it's a one-time setup that adds deployment tools, Bicep schema lookups, and infrastructure generation (details in the root [Quick Start](../../README.md#quick-start)):

```
> /plugin marketplace add microsoft/azure-skills
> /plugin install azure@azure-skills
```

Now select the deployment agent. Agents are specialized personas that know how to handle specific tasks:

```
> /agent
```

Select **`oss-to-azure-deployer`** from the list. You're now in an interactive session with the deployment agent.

### Step 2: Deploy

<p align="center">
  <img src="./images/azure-deployment.webp" alt="Deploy Grafana to Azure" width="800" />
</p>

Tell the agent what you want in a single prompt (OSS shared recipe: location + secrets + resolve issues):

```
> Deploy Grafana to Azure using Bicep and azd. Set the location to westus,
  generate a secure admin password, use /api/health for probes, resolve any
  issues that come up, and log problems to issues.md.
```

The agent handles the entire deployment:

1. Loads the `grafana-azure` skill (Grafana-specific health probes, ports, and environment variables) and the `container-apps-deployment` skill, then follows the Azure plugin pipeline: `azure-prepare` → `azure-validate` → `azure-deploy`
2. Generates a lean Bicep (Azure's infrastructure-as-code language) structure in `infra-grafana/` with no PostgreSQL module needed (SQLite is the default)
3. Updates `azure.yaml`, registers Azure providers, sets environment variables
4. Runs `azd up`

> ⏳ **While you wait:** This is the fastest deployment in the project — no database to provision. While it runs, consider: *why* is it so fast? Compare the [architecture diagram](#architecture) to the [n8n architecture](../n8n/README.md#architecture). What's missing? (Answer: no database server. SQLite is embedded in the container, which means zero database provisioning time, but that comes with a tradeoff you'll discover in the [Assignment](#assignment).) You can also check what's being created by running `az resource list --resource-group rg-<env-name> --output table` in a separate terminal.

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

For repeatable verification on Windows, macOS, and Linux, have the agent generate `scripts/verify-grafana.mjs`. It must read `GRAFANA_URL` through `azd`, require HTTP 200 from `/api/health`, and assert `database: "ok"`. Run it with `node scripts/verify-grafana.mjs`.

Open the value returned by `azd env get-value GRAFANA_URL` in your browser. Log in with the admin username and the password set during deployment. If you're not sure what password was generated, ask the agent to retrieve it from the deployment environment without printing it in shared logs.

If something goes wrong, just ask. You're still in the same session:

```
> Grafana is returning 502 errors
```

The agent will check if it's a cold start issue (scale-from-zero takes 30-60s) or a real problem.

---

<details>
<summary>Configuration Reference (handled by the agent automatically)</summary>

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
| Startup | n/a | 10s | 30 (5 min max) |
| Liveness | 15s | 30s | 3 |
| Readiness | n/a | 10s | 3 |

Health endpoint response:
```json
{"commit": "abc123", "database": "ok", "version": "10.x.x"}
```

### Storage: SQLite vs PostgreSQL

**SQLite (default):**
- Zero setup, embedded in the container
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

</details>

---

<details>
<summary>Troubleshooting</summary>

## Troubleshooting

### Container Won't Start

Ask the agent to diagnose:

```
> My Grafana container won't start. Check the logs and tell me what's wrong.
```

The agent uses `azure_deploy_app_logs` to pull logs and identify the issue, typically health probes that are too aggressive. The Bicep templates in `infra-grafana/` include proper timing.

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

</details>

---

## Cleanup

```bash
azd down --force --purge
```

Teardown takes 3-5 minutes (Container Apps environment deletion is slow).

---

## Key Learnings

- **No database doesn't mean no persistence problem.** SQLite is ephemeral in containers. Know this before deploying.
- **Scale-to-zero cold starts are normal.** 30-60s on first request isn't an error.
- **Same agent, different skills.** The agent loaded `grafana-azure` instead of `n8n-azure` and adapted automatically.
- **Simpler apps mean simpler infrastructure.** No database dependency means fewer moving parts to break.

---

## Assignment

1. Create a dashboard in Grafana, then restart the container app:

   Ask GitHub Copilot to generate `scripts/restart-grafana.mjs`. It must read the resource group through `azd`, locate the tagged Grafana Container App and its active revision through Azure CLI argument arrays, then restart only that revision. Run `node scripts/restart-grafana.mjs`.

   (If an `azd env get-value` lookup fails, just ask the agent: *"Restart my Grafana container app."*)

   Notice your dashboard is gone. Why? Ask the agent: *"Why did my Grafana dashboard disappear after a restart?"*
2. Try the fix: ask the agent *"How do I make Grafana dashboards persist across restarts?"* and implement what it suggests
3. Clean up with `azd down --force --purge`

---

## What's Next

Explore the other journeys:

- [n8n](../n8n/README.md) — Container Apps + PostgreSQL, health probes, post-provision hooks
- [Superset](../superset/README.md) — AKS, init containers (higher cost)
- [AIMarket](../aimarket/README.md) — full-stack build from a PLAN.md spec with Foundry

> 📚 **All journeys:** [Back to root README](../../README.md#agentic-journeys)

---

## Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
