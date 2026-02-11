![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg) ![Azure](https://img.shields.io/badge/Microsoft-Azure-0078D4?logo=microsoftazure&logoColor=white)

🎯 [What You'll Learn](#what-youll-learn) | 🤖 [How It Works](#how-it-works-agent--skills) | 📚 [Deployments](#deployments) | ✅ [Prerequisites](#prerequisites) | 🚀 [Quick Start](#quick-start) | 📁 [Project Structure](#project-structure)

# OSS to Azure

Deploy open-source applications to Azure using **GitHub Copilot CLI agents and skills** — powered by Infrastructure as Code (Bicep) and Azure Developer CLI (azd).

## What You'll Learn

This repo demonstrates how to use **GitHub Copilot CLI's agent and skill system** to deploy real-world open-source applications to Azure. Instead of reading docs and piecing together infrastructure manually, you use the **`@oss-to-azure-deployer` agent** — it knows the architecture, the gotchas, and the deployment patterns for each app.

Each deployment includes:

- **A Copilot agent** that orchestrates the entire deployment journey — from requirements to verification
- **App-specific skills** that teach Copilot the configuration quirks of each application
- **Generic infrastructure skills** for reusable Bicep and azd patterns
- **Bicep infrastructure** — Modular, production-ready Azure resource definitions
- **One-command deployment** with `azd up`
- **Troubleshooting guides** — Every issue we hit and how the agent resolves them

**The idea:** You tell the agent what you want to deploy. It picks the right skills, generates infrastructure, handles the edge cases, and walks you through verification. The skills are the reusable knowledge — the agent is the orchestrator.

## How It Works: Agent + Skills

This repo uses **GitHub Copilot CLI's agent and skill architecture** to encode deployment knowledge into reusable, AI-consumable components.

**Agents** define *who* does the work — personas with specific goals and workflows. **Skills** define *how* — reusable patterns the agent loads based on context.

The **`@oss-to-azure-deployer`** [agent](.github/agents/oss-to-azure-deployer.agent.md) orchestrates the full deployment lifecycle. It automatically loads the right skills based on which app you're deploying:

| Skill | Type | Purpose |
|-------|------|---------|
| [`n8n-azure`](.github/skills/n8n-azure/SKILL.md) | App-specific | n8n configuration, environment variables, health probes |
| [`grafana-azure`](.github/skills/grafana-azure/SKILL.md) | App-specific | Grafana configuration, SQLite/PostgreSQL options |
| [`superset-azure`](.github/skills/superset-azure/SKILL.md) | App-specific | Superset on AKS, psycopg2 setup, Kubernetes patterns |
| [`azure-bicep-generation`](.github/skills/azure-bicep-generation/SKILL.md) | Generic | Bicep patterns for Container Apps, PostgreSQL, naming |
| [`azure-aks-deployment`](.github/skills/azure-aks-deployment/SKILL.md) | Generic | AKS cluster provisioning, Kubernetes manifests |
| [`azd-deployment`](.github/skills/azd-deployment/SKILL.md) | Generic | azure.yaml templates, hooks, deployment workflows |

Try it: open GitHub Copilot CLI and ask `@oss-to-azure-deployer` — *"Deploy n8n to Azure"* or *"My Superset pod is in CrashLoopBackOff"*.

## Deployments

| # | App | What You'll Deploy | Deploy Time | Monthly Cost (Dev) |
|:-:|-----|-------------------|-------------|-------------------|
| 01 | 🔄 [n8n — Workflow Automation](./n8n/README.md) | Container Apps + PostgreSQL | ~7 min | ~$25-35 |
| 02 | 📊 [Grafana — Metrics & Visualization](./grafana/README.md) | Container Apps + SQLite | ~2 min | ~$10-20 |
| 03 | 📈 [Apache Superset — BI Platform](./superset/README.md) | AKS + PostgreSQL | ~15-20 min | ~$135-185 |

Each app has its own detailed README with architecture diagrams, step-by-step deployment, configuration reference, cost breakdown, and troubleshooting guide.

## Prerequisites

Before deploying any app, ensure you have:

✅ **Azure Subscription** — [Create one free](https://azure.microsoft.com/free/)<br>
✅ **Azure CLI** (`az`) — [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)<br>
✅ **Azure Developer CLI** (`azd`) — [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)<br>
✅ **GitHub Copilot CLI** — [Install](https://docs.github.com/copilot/how-tos/copilot-cli/cli-getting-started) for AI-assisted deployment with `@oss-to-azure-deployer`

```bash
# Verify installations
az --version
azd version

# Login to Azure
az login
```

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

# 3. Create an azd environment
azd env new my-app-env

# 4. Set required variables (see each app's README for specifics)
azd env set AZURE_LOCATION "westus"

# 5. Update azure.yaml to point to the right infra directory
#    infra.path: infra-n8n | infra-grafana | infra-superset

# 6. Deploy
azd up

# 7. Clean up when done
azd down --force --purge
```

See each app's README for specific variables and configuration.

## Project Structure

```
oss-to-azure/
├── README.md                              # This file
├── azure.yaml                             # azd configuration (point to desired infra dir)
│
├── n8n/
│   └── README.md                          # n8n deployment guide
├── grafana/
│   └── README.md                          # Grafana deployment guide
├── superset/
│   └── README.md                          # Superset deployment guide
│
├── infra-n8n/                             # n8n Bicep infrastructure
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── modules/
│   └── hooks/
├── infra-grafana/                         # Grafana Bicep infrastructure
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── modules/
│   └── hooks/
├── infra-superset/                        # Superset Bicep infrastructure
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── modules/
│   └── hooks/
│
└── .github/
    ├── agents/
    │   └── oss-to-azure-deployer.agent.md # Copilot agent definition
    ├── skills/
    │   ├── n8n-azure/                     # n8n-specific skill
    │   ├── grafana-azure/                 # Grafana-specific skill
    │   ├── superset-azure/                # Superset-specific skill
    │   ├── azure-bicep-generation/        # Generic Bicep patterns
    │   ├── azure-aks-deployment/          # Generic AKS patterns
    │   └── azd-deployment/                # Generic azd patterns
    └── copilot-instructions.md
```

## Adding New Applications

Want to deploy a different OSS app? The agent/skill pattern is designed to be extended:

1. **Create an app-specific skill** in `.github/skills/<app>-azure/` with SKILL.md, config, and troubleshooting
2. **Create an infra directory** (`infra-<app>/`) with Bicep modules
3. **The agent picks it up automatically** — no changes to the agent definition needed

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for the full guide on adding new applications.

## Getting Help

- 🤖 **Ask the Agent:** `@oss-to-azure-deployer` in GitHub Copilot CLI for deployment help and troubleshooting
- 📖 **App-specific issues:** Check the troubleshooting section in each app's README
- 🔗 **Azure docs:** [Container Apps](https://learn.microsoft.com/azure/container-apps/) · [AKS](https://learn.microsoft.com/azure/aks/) · [PostgreSQL](https://learn.microsoft.com/azure/postgresql/) · [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- 🐛 **Found a bug?** [Open an issue](https://github.com/DanWahlin/oss-to-azure/issues) on GitHub

## License

This project is licensed under the [MIT License](LICENSE).
