![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg) ![Azure](https://img.shields.io/badge/Microsoft-Azure-0078D4?logo=microsoftazure&logoColor=white)

🎯 [What You'll Learn](#what-youll-learn) | 🤖 [How It Works](#how-it-works-agent--skills--azure-plugin) | 📚 [Deployments](#deployments) | ✅ [Prerequisites](#prerequisites) | 🚀 [Quick Start](#quick-start) | 📁 [Project Structure](#project-structure)

# GitHub + Azure Agentic Use Cases

Deploy open-source applications to Azure using **GitHub Copilot CLI agents, skills, and the official Azure plugin**, powered by Infrastructure as Code (Bicep) and Azure Developer CLI (azd).

## What You'll Learn

This repo demonstrates how to use **GitHub Copilot CLI's agent and skill system**, enhanced by the **official [Azure plugin](https://github.com/microsoft/GitHub-Copilot-for-Azure)**, to deploy real-world open-source applications to Azure. Instead of reading docs and piecing together infrastructure manually, you use the **`@oss-to-azure-deployer` agent**. It knows the architecture, the gotchas, and the deployment patterns for each app.

Each deployment includes:

- **A Copilot agent** that orchestrates the entire deployment journey, from requirements to verification
- **App-specific skills** that teach Copilot the configuration quirks of each application
- **The official Azure plugin** (21 skills) for infrastructure generation, validation, deployment, and real-time Azure intelligence
- **One-command deployment** with `azd up`
- **Troubleshooting guides**: Every issue we hit and how the agent resolves them

**The idea:** You tell the agent what you want to deploy. It loads the app-specific skill for configuration knowledge, then uses the Azure plugin's skill pipeline (`azure-prepare` -> `azure-validate` -> `azure-deploy`) to generate infrastructure from scratch, validate it, and deploy. The app skills are the domain knowledge. The Azure plugin is the infrastructure engine. The agent is the orchestrator that ties them together.

## How It Works: Agent + Skills + Azure Plugin

This repo uses **GitHub Copilot CLI's agent and skill architecture**, combined with the **official Azure plugin**, to encode deployment knowledge into reusable, AI-consumable components.

- **Agent** defines *who* does the work: a persona with a specific goal and workflow
- **App-specific skills** define *what* to configure: environment variables, health probes, ports, database requirements
- **Azure plugin skills** define *how* to build and deploy: infrastructure generation, validation, and deployment

The **`@oss-to-azure-deployer`** [agent](.github/agents/oss-to-azure-deployer.agent.md) orchestrates the full deployment lifecycle using a 6-step pipeline:

1. **Load app skill** (n8n-azure, grafana-azure, or superset-azure)
2. **azure-prepare** — Generate Bicep infrastructure from scratch
3. **Set environment** — Configure azd with subscription, location, secrets
4. **azure-validate** — Validate Bicep templates and azd configuration
5. **azure-deploy** — Run `azd up` to provision and deploy
6. **Verify** — Output the deployed URL and run health checks

### App-Specific Skills

| Skill | Purpose |
|-------|---------|
| [`n8n-azure`](.github/skills/n8n-azure/SKILL.md) | n8n configuration: port 5678, PostgreSQL, 60s+ startup probe, WEBHOOK_URL hook |
| [`grafana-azure`](.github/skills/grafana-azure/SKILL.md) | Grafana configuration: port 3000, SQLite default, GF_* env vars, /api/health probe |
| [`superset-azure`](.github/skills/superset-azure/SKILL.md) | Superset configuration: AKS, PostgreSQL, psycopg2 Docker image, K8s manifests |

### Azure Plugin Skills (Used by the Agent)

The official [Azure plugin](https://github.com/microsoft/GitHub-Copilot-for-Azure) provides 21 skills. The deployer agent primarily uses:

| Skill | What It Does |
|-------|-------------|
| `azure-prepare` | Generates azure.yaml, Bicep templates, parameters, and hooks from scratch |
| `azure-validate` | Validates Bicep templates, checks provider registration, runs preflight checks |
| `azure-deploy` | Runs `azd up`, handles errors, fetches deployment logs |
| `azure-get_azure_bestpractices` | Returns best practices for Azure resource configuration |
| `azure-azd` | Direct azd CLI operations (env management, provisioning) |

Try it: start `copilot`, run `/agent`, select `oss-to-azure-deployer`, and ask *"Deploy n8n to Azure"*.

## Deployments

| Chapter | App | What You'll Deploy | Deploy Time | Monthly Cost (Dev) |
|:-------:|-----|-------------------|-------------|-------------------|
| 01 | 🔄 [n8n — Workflow Automation](./n8n/README.md) | Container Apps + PostgreSQL | ~7 min | ~$25-35 |
| 02 | 📊 [Grafana — Metrics & Visualization](./grafana/README.md) | Container Apps + SQLite | ~2 min | ~$10-20 |
| 03 | 📈 [Apache Superset — BI Platform](./superset/README.md) | AKS + PostgreSQL | ~15-20 min | ~$135-185 |

Infrastructure is generated fresh each deployment by the Azure plugin's `azure-prepare` skill. No pre-built Bicep is committed to the repo.

## Prerequisites

Before deploying any app, ensure you have:

✅ **Azure Subscription** — [Create one free](https://azure.microsoft.com/free/)<br>
✅ **Azure CLI** (`az`) — [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)<br>
✅ **Azure Developer CLI** (`azd`) — [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)<br>
✅ **kubectl** — [Install](https://kubernetes.io/docs/tasks/tools/) (required for Chapter 03: Superset on AKS)<br>
✅ **GitHub Copilot CLI** — [Install](https://docs.github.com/copilot/how-tos/copilot-cli/cli-getting-started)<br>

```bash
# Verify installations
az --version
azd version

# Login to Azure
az login
```

## Installing the Azure Plugin

The Azure plugin provides the infrastructure skills and Azure MCP Server tools used by the deployer agent. Install it from inside **Copilot CLI, Claude Code, or any tool that supports the plugin system**:

```bash
# Add the marketplace (first time only)
/plugin marketplace add microsoft/github-copilot-for-azure

# Install the plugin
/plugin install azure@github-copilot-for-azure

# Update the plugin (when new versions are available)
/plugin update azure@github-copilot-for-azure
```

This installs 21 Azure skills including `azure-prepare`, `azure-validate`, and `azure-deploy`, plus the Azure MCP Server tools (`azure_bicep_schema`, `azure_deploy_app_logs`, etc.) used by the app-specific skills. No separate MCP server installation is needed.

## Quick Start

Every app follows the same workflow:

```bash
# 1. Clone the repo
git clone https://github.com/DanWahlin/oss-to-azure.git
cd oss-to-azure

# 2. Register required Azure resource providers (one-time)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 3. Start Copilot CLI
copilot

# 4. Install the Azure plugin (first time only)
> /plugin marketplace add microsoft/github-copilot-for-azure
> /plugin install azure@github-copilot-for-azure

# 5. Select the deployment agent
> /agent
# Choose: oss-to-azure-deployer

# 6. Ask it to deploy
> Deploy n8n to Azure in westus

# 7. Clean up when done
> Run azd down --force --purge
```

The agent will:
1. Read the n8n-azure skill for app-specific requirements
2. Use `azure-prepare` to generate Bicep infrastructure from scratch
3. Set up the azd environment with secure passwords
4. Validate the infrastructure with `azure-validate`
5. Deploy with `azd up`
6. Output the deployed URL

See each chapter's README for detailed walkthroughs.

## Project Structure

```
oss-to-azure/
├── README.md                              # This file
│
├── n8n/
│   └── README.md                          # Chapter 01: n8n deployment guide
├── grafana/
│   └── README.md                          # Chapter 02: Grafana deployment guide
├── superset/
│   └── README.md                          # Chapter 03: Superset deployment guide
│
└── .github/
    ├── agents/
    │   └── oss-to-azure-deployer.agent.md # Copilot agent that orchestrates deployments
    ├── skills/
    │   ├── n8n-azure/                     # n8n app-specific skill
    │   │   ├── SKILL.md
    │   │   ├── config/
    │   │   └── troubleshooting.md
    │   ├── grafana-azure/                 # Grafana app-specific skill
    │   │   ├── SKILL.md
    │   │   ├── config/
    │   │   └── troubleshooting.md
    │   └── superset-azure/                # Superset app-specific skill
    │       ├── SKILL.md
    │       ├── config/
    │       ├── references/
    │       └── troubleshooting.md
    └── copilot-instructions.md
```

**Note:** Infrastructure code is not committed to the repo. The Azure plugin's `azure-prepare` skill generates all Bicep templates, azure.yaml, parameters, and hooks fresh for each deployment.

## Adding New Applications

Want to deploy a different OSS app? The agent/skill pattern is designed to be extended:

1. **Create an app-specific skill** in `.github/skills/<app>-azure/` with:
   - `SKILL.md` — Overview, quick start, architecture, requirements
   - `config/environment-variables.md` — All env vars the app needs
   - `config/health-probes.md` — Probe paths, ports, timing
   - `troubleshooting.md` — Common issues and solutions
2. **The agent picks it up automatically** — The deployer agent reads the skill and uses the Azure plugin to generate matching infrastructure. No changes to the agent definition needed.

## Getting Help

- 🤖 **Ask the Agent:** `@oss-to-azure-deployer` in GitHub Copilot CLI for deployment help and troubleshooting
- 📖 **App-specific issues:** Check the troubleshooting section in each app skill
- 🔗 **Azure docs:** [Container Apps](https://learn.microsoft.com/azure/container-apps/) · [AKS](https://learn.microsoft.com/azure/aks/) · [PostgreSQL](https://learn.microsoft.com/azure/postgresql/) · [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- 🐛 **Found a bug?** [Open an issue](https://github.com/DanWahlin/oss-to-azure/issues) on GitHub

## License

This project is licensed under the [MIT License](LICENSE).
