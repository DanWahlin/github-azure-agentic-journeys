![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg) ![Azure](https://img.shields.io/badge/Microsoft-Azure-0078D4?logo=microsoftazure&logoColor=white)

🎯 [What You'll Learn](#what-youll-learn) | 🤖 [How It Works](#how-it-works-agent--skills--azure-mcp) | 📚 [Deployments](#deployments) | ✅ [Prerequisites](#prerequisites) | 🚀 [Quick Start](#quick-start) | 📁 [Project Structure](#project-structure)

# OSS to Azure

Deploy open-source applications to Azure using **GitHub Copilot CLI agents, skills, and Azure MCP tools**, powered by Infrastructure as Code (Bicep) and Azure Developer CLI (azd).

## What You'll Learn

This repo demonstrates how to use **GitHub Copilot CLI's agent and skill system**, enhanced by the **Azure MCP Server plugin**, to deploy real-world open-source applications to Azure. Instead of reading docs and piecing together infrastructure manually, you use the **`@oss-to-azure-deployer` agent**. It knows the architecture, the gotchas, and the deployment patterns for each app.

Each deployment includes:

- **A Copilot agent** that orchestrates the entire deployment journey, from requirements to verification
- **App-specific skills** that teach Copilot the configuration quirks of each application
- **Generic infrastructure skills** for reusable Bicep and azd patterns
- **Azure MCP tools** for real-time schema lookups, deployment planning, IaC best practices, and log analysis
- **Bicep infrastructure**: Modular, production-ready Azure resource definitions
- **One-command deployment** with `azd up`
- **Troubleshooting guides**: Every issue we hit and how the agent resolves them

**The idea:** You tell the agent what you want to deploy. It picks the right skills, uses Azure MCP tools to look up schemas and best practices, generates infrastructure, handles the edge cases, and walks you through verification. The skills are the reusable knowledge. The agent is the orchestrator. The MCP tools are the real-time intelligence.

## How It Works: Agent + Skills + Azure MCP

This repo uses **GitHub Copilot CLI's agent and skill architecture**, combined with the **Azure MCP Server plugin**, to encode deployment knowledge into reusable, AI-consumable components.

- **Agents** define *who* does the work: personas with specific goals and workflows
- **Skills** define *how*: reusable patterns the agent loads based on context
- **Azure MCP tools** provide *real-time intelligence*: schema lookups, deployment plans, IaC guidance, and log analysis

The **`@oss-to-azure-deployer`** [agent](.github/agents/oss-to-azure-deployer.agent.md) orchestrates the full deployment lifecycle. It automatically loads the right skills and uses Azure MCP tools based on which app you're deploying:

### Skills

| Skill | Type | Purpose |
|-------|------|---------|
| [`n8n-azure`](.github/skills/n8n-azure/SKILL.md) | App-specific | n8n configuration, environment variables, health probes |
| [`grafana-azure`](.github/skills/grafana-azure/SKILL.md) | App-specific | Grafana configuration, SQLite/PostgreSQL options |
| [`superset-azure`](.github/skills/superset-azure/SKILL.md) | App-specific | Superset on AKS, psycopg2 setup, Kubernetes patterns |
| [`azure-bicep-generation`](.github/skills/azure-bicep-generation/SKILL.md) | Generic | Bicep patterns for Container Apps, PostgreSQL, naming |
| [`azure-container-apps`](.github/skills/azure-container-apps/SKILL.md) | Generic | Container Apps patterns for serverless deployments |
| [`azure-aks-deployment`](.github/skills/azure-aks-deployment/SKILL.md) | Generic | AKS cluster provisioning, Kubernetes manifests |
| [`azd-deployment`](.github/skills/azd-deployment/SKILL.md) | Generic | azure.yaml templates, hooks, deployment workflows |

### Azure MCP Tools

The agent uses these tools from the [Azure MCP Server plugin](https://github.com/microsoft/github-copilot-for-azure) for real-time Azure intelligence:

| Tool | What It Does |
|------|-------------|
| `azure_bicep_schema` | Look up latest API versions and property definitions for any Azure resource type |
| `azure_deploy_iac_guidance` | Get Bicep/Terraform best practices with azd compatibility |
| `azure_deploy_plan` | Generate deployment plans. Validates resources, dependencies, and configuration |
| `azure_deploy_app_logs` | Fetch Log Analytics logs for post-deployment troubleshooting |
| `azure_deploy_architecture` | Generate Mermaid architecture diagrams for deployments |
| `azure_deploy_pipeline` | Get CI/CD pipeline guidance for GitHub Actions with azd |

Try it: start `copilot`, run `/agent`, select `oss-to-azure-deployer`, and ask *"Deploy n8n to Azure using Bicep and azd"*.

## Deployments

| Chapter | App | What You'll Deploy | Deploy Time | Monthly Cost (Dev) |
|:-------:|-----|-------------------|-------------|-------------------|
| 01 | 🔄 [n8n — Workflow Automation](./n8n/README.md) | Container Apps + PostgreSQL | ~7 min | ~$25-35 |
| 02 | 📊 [Grafana — Metrics & Visualization](./grafana/README.md) | Container Apps + SQLite | ~2 min | ~$10-20 |
| 03 | 📈 [Apache Superset — BI Platform](./superset/README.md) | AKS + PostgreSQL | ~15-20 min | ~$135-185 |

Each chapter has two paths: **generate infrastructure with the agent** (primary) or **deploy pre-built Bicep** (quick start). Both include architecture diagrams, configuration reference, cost breakdowns, and troubleshooting guides.

> **Note:** Deploy times listed are for Path 2 (pre-built Bicep). Path 1 (agent-guided generation) adds ~10-15 minutes for the interactive infrastructure generation step.

## Prerequisites

Before deploying any app, ensure you have:

✅ **Azure Subscription** — [Create one free](https://azure.microsoft.com/free/)<br>
✅ **Azure CLI** (`az`) — [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)<br>
✅ **Azure Developer CLI** (`azd`) — [Install](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)<br>
✅ **kubectl** — [Install](https://kubernetes.io/docs/tasks/tools/) (required for Chapter 03: Superset on AKS)<br>
✅ **GitHub Copilot CLI** — [Install](https://docs.github.com/copilot/how-tos/copilot-cli/cli-getting-started) for AI-assisted deployment with `@oss-to-azure-deployer`<br>
✅ **Azure MCP Server Plugin** — Install in Copilot CLI for real-time Azure intelligence:

```bash
# Verify installations
az --version
azd version

# Login to Azure
az login
```

The Azure MCP Server plugin is installed from inside Copilot CLI (see [Quick Start](#quick-start) below):

```
> /plugin install microsoft/github-copilot-for-azure:plugin
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
#    Edit the `infra.path` value: infra-n8n | infra-grafana | infra-superset
#    See each chapter's README for the full azure.yaml configuration

# 6. Deploy
azd up

# 7. Clean up when done
azd down --force --purge
```

Or use the agent for an interactive, guided experience:

```bash
# Make sure you're in the repo root
cd oss-to-azure

# Start Copilot CLI
copilot

# Install the Azure MCP plugin (first time only)
> /plugin install microsoft/github-copilot-for-azure:plugin

# Select the deployment agent
> /agent
# Choose: oss-to-azure-deployer

# Ask it to generate infrastructure and deploy
> Deploy n8n to Azure using Bicep and azd

# Once infrastructure is generated, deploy it
> Run azd up for the n8n infrastructure. Set location to westus and generate secure passwords. If there are any issues, resolve them.
```

See each chapter's README for detailed walkthroughs.

## Project Structure

```
oss-to-azure/
├── README.md                              # This file
├── azure.yaml                             # azd configuration (point to desired infra dir)
│
├── n8n/
│   └── README.md                          # Chapter 01: n8n deployment guide
├── grafana/
│   └── README.md                          # Chapter 02: Grafana deployment guide
├── superset/
│   └── README.md                          # Chapter 03: Superset deployment guide
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
    │   ├── azure-container-apps/          # Generic Container Apps patterns
    │   ├── azure-aks-deployment/          # Generic AKS patterns
    │   └── azd-deployment/                # Generic azd patterns
    └── copilot-instructions.md
```

## Adding New Applications

Want to deploy a different OSS app? The agent/skill pattern is designed to be extended:

1. **Create an app-specific skill** in `.github/skills/<app>-azure/` with SKILL.md, config, and troubleshooting
2. **Create an infra directory** (`infra-<app>/`) with Bicep modules
3. **The agent picks it up automatically**. No changes to the agent definition needed

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for the full guide on adding new applications.

## Getting Help

- 🤖 **Ask the Agent:** `@oss-to-azure-deployer` in GitHub Copilot CLI for deployment help and troubleshooting
- 📖 **App-specific issues:** Check the troubleshooting section in each chapter's README
- 🔗 **Azure docs:** [Container Apps](https://learn.microsoft.com/azure/container-apps/) · [AKS](https://learn.microsoft.com/azure/aks/) · [PostgreSQL](https://learn.microsoft.com/azure/postgresql/) · [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- 🐛 **Found a bug?** [Open an issue](https://github.com/DanWahlin/oss-to-azure/issues) on GitHub

## License

This project is licensed under the [MIT License](LICENSE).
