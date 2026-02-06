# n8n Azure Deployment Report

## ✅ Deployment Status: SUCCESS

**Deployed on:** February 1, 2026

## 📍 Deployment Details

| Resource | Value |
|----------|-------|
| **n8n URL** | https://ca-n8n-zjq2oyqhuhljo.blackmushroom-1bd94a29.westus.azurecontainerapps.io |
| **Resource Group** | rg-n8n-dev |
| **Container App** | ca-n8n-zjq2oyqhuhljo |
| **PostgreSQL Server** | psql-zjq2oyqhuhljo |
| **Region** | West US |
| **Login Username** | admin |

## 📁 Generated Infrastructure Files

```
infra/
├── main.bicep                           # Main infrastructure template
├── main.parameters.json                 # Deployment parameters (with passwords)
├── main.parameters.json.example         # Example parameters file
├── abbreviations.json                   # Azure resource naming conventions
├── hooks/
│   ├── postprovision.sh                 # Post-deployment hook (Linux/macOS)
│   └── postprovision.ps1                # Post-deployment hook (Windows)
└── modules/
    ├── container-apps-environment.bicep
    ├── log-analytics.bicep
    ├── managed-identity.bicep
    ├── n8n-container-app.bicep
    └── postgresql.bicep
```

## 🔧 Issues Encountered & Resolutions

### 1. GHCP CLI Agent File Format
**Issue:** The `--agent` flag in GHCP CLI doesn't accept file paths directly.  
**Resolution:** Used the agent file content as part of the `-p` prompt flag instead.

### 2. azd Parameter Prompting
**Issue:** `azd up --no-prompt` still prompted for `environmentName` parameter.  
**Resolution:** Added `environmentName` to `main.parameters.json` and set it via `azd env set`.

### 3. Post-Provision Hook Timing
**Issue:** Post-provision hook failed with "ContainerAppOperationInProgress" error because the container app was still provisioning.  
**Resolution:** Waited 30 seconds and re-ran the hook manually. Consider adding retry logic or sleep to the hook.

## 🚀 How to Use GHCP CLI for Agent-Based Deployments

### CORRECT: Agent Invocation via `--agent` Flag

GHCP CLI agents use markdown files with YAML front matter. Key requirements:

1. **Agent Location**: `~/.claude/agents/` or `.github/agents/` in project
2. **Tools Format**: Must be a YAML array, NOT comma-separated string
3. **Agent Name**: Matches the `name` field in front matter

**Agent File Format** (`~/.claude/agents/n8n-deployment.md`):
```yaml
---
name: n8n-deployment
description: Deploy n8n to Azure using Bicep and azd
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---
# Agent instructions here...
```

**Invoke the Agent**:
```bash
cd ~/projects/oss-to-azure
gh copilot -- --agent n8n-deployment --allow-all -p "Deploy n8n to Azure"
```

**For Project Agents** in `.github/agents/`:
- Remove unsupported fields (`model`, `color`, `examples`) from front matter
- Ensure `tools` is a YAML array
- Use the `name` field value for `--agent` flag

## 💡 Lessons Learned

1. **GHCP Agent Files are Prompts:** The `.agent.md` files are essentially detailed prompts with tool specifications. They need to be read by GHCP rather than passed as a file reference.

2. **Parameter Management:** azd requires all non-secret parameters to be either in the environment config or `main.parameters.json`.

3. **Post-Provision Timing:** Azure Container Apps provisioning can take time; hooks should include retry logic.

4. **Health Probes Critical:** The 60-second liveness probe initial delay and 30-failure startup probe threshold are essential for n8n's slow cold-start.

---

## 🏆 Top 3 OSS Projects for Next Deployment Agents

Based on research into popular self-hosted projects and Azure compatibility:

### 1. **Appwrite** ⭐ 50,000+ GitHub stars
**What:** Backend-as-a-Service (BaaS) platform providing auth, databases, storage, functions, messaging

**Why:**
- Massive developer community and growing adoption
- Already has Azure integration documentation
- Docker-based architecture fits perfectly with Container Apps
- Direct competitor to Firebase/Supabase with self-hosting focus
- Production-ready with enterprise features

**Complexity:** Medium (requires multiple containers)

### 2. **Uptime Kuma** ⭐ 55,000+ GitHub stars
**What:** Self-hosted monitoring tool with beautiful UI for uptime checks

**Why:**
- Extremely popular in self-hosted community
- Single container, simple deployment
- Perfect Azure beginner project
- Real production value for any team
- SQLite by default, can use PostgreSQL
- WebSocket-based real-time updates

**Complexity:** Low (single container, minimal config)

### 3. **Dify** ⭐ 80,000+ GitHub stars
**What:** AI application development platform for building LLM-powered apps and agents

**Why:**
- Fastest-growing AI platform on GitHub
- Complements n8n (n8n for automation, Dify for AI apps)
- Visual workflow builder for AI agents
- Supports multiple LLM providers including Azure OpenAI
- Enterprise features with self-hosting option
- Docker Compose architecture adaptable to Container Apps

**Complexity:** High (multi-container, requires vector DB, Redis)

### Honorable Mentions
- **Paperless-ngx** - Document management with OCR
- **Vaultwarden** - Bitwarden-compatible password manager
- **Grafana + Prometheus** - Monitoring stack

---

## 📊 Cost Estimate (Monthly)

| Resource | Estimated Cost |
|----------|----------------|
| Container Apps (scale-to-zero) | ~$10-30 |
| PostgreSQL Flexible (B1ms) | ~$15-25 |
| Log Analytics | ~$5-10 |
| **Total** | **~$30-65/month** |

---

## 🗑️ Cleanup

To delete all resources:
```bash
cd ~/projects/oss-to-azure
azd down --purge
```
