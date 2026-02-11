---
name: azd-deployment
description: Azure Developer CLI (azd) deployment patterns. Use when configuring azure.yaml, post-provision hooks, or azd workflows.
---

# Azure Developer CLI (azd) Deployment Skill

Configure Azure Developer CLI for infrastructure deployment workflows.

## When to Use

- Setting up azure.yaml configuration
- Creating post-provision hooks
- Managing azd environments
- Understanding azd deployment lifecycle

## Quick Reference

### Essential Commands

```bash
# Initialize environment
azd init -e <env-name>

# Deploy everything (provision + deploy)
azd up

# Provision infrastructure only
azd provision

# Preview changes without deploying
azd provision --preview

# Get environment values
azd env get-value <OUTPUT_NAME>
azd env get-values  # All values

# Tear down
azd down --force --purge

# Environment management
azd env list
azd env select <env-name>
azd env new <env-name>
```

## Project Structure

### Bicep Project
```
project/
├── azure.yaml              # azd configuration
├── infra/
│   ├── main.bicep          # Main template
│   ├── main.parameters.json
│   ├── abbreviations.json  # Optional naming
│   ├── modules/            # Optional modular bicep
│   └── hooks/
│       ├── postprovision.sh
│       └── postprovision.ps1
├── .gitignore
└── README.md
```

### Terraform Project
```
project/
├── azure.yaml              # azd configuration
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── main.tfvars.json    # Variables (gitignored)
│   └── hooks/
│       ├── postprovision.sh
│       └── postprovision.ps1
├── .gitignore
└── README.md
```

## azure.yaml Configuration

### Bicep Template

See `templates/azure.yaml.bicep`:

```yaml
name: my-app

infra:
  provider: bicep
  path: infra

hooks:
  postprovision:
    posix:
      shell: sh
      run: ./infra/hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./infra/hooks/postprovision.ps1
```

### Terraform Template

```yaml
name: my-app

infra:
  provider: terraform
  path: infra

hooks:
  postprovision:
    posix:
      shell: sh
      run: ./infra/hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./infra/hooks/postprovision.ps1
```

### Key Points

- **No `services:` section** when using pre-built Docker images
- Container image is specified in Bicep/Terraform, not azure.yaml
- Hooks run automatically after `azd up` or `azd provision`

## Post-Provision Hooks

Use hooks to configure settings that have circular dependencies (e.g., WEBHOOK_URL depends on FQDN which isn't known until after creation).

### Pattern Files

- `hooks/postprovision.sh` - Linux/macOS
- `hooks/postprovision.ps1` - Windows

### Common Hook Tasks

1. Configure WEBHOOK_URL using Container App FQDN
2. Set up DNS records
3. Configure external integrations
4. Run database migrations

## Deployment Lifecycle

```
azd up
  ├── 1. Provision (infra)
  │     ├── Bicep/Terraform deployment
  │     └── Store outputs in azd env
  ├── 2. Deploy (services, if defined)
  │     └── Build and push containers
  └── 3. Post-provision hooks
        ├── posix: postprovision.sh
        └── windows: postprovision.ps1
```

## Environment Variables

azd makes Bicep/Terraform outputs available as environment variables:

| Bicep Output | azd Access |
|--------------|------------|
| `output CONTAINER_APP_NAME string = app.name` | `azd env get-value CONTAINER_APP_NAME` |
| `output APP_URL string = 'https://...'` | `azd env get-value APP_URL` |

**Naming convention:** Outputs should be SCREAMING_SNAKE_CASE.

## .gitignore Template

```gitignore
# azd
.azure/

# Bicep
*.parameters.json
!*.parameters.json.example

# Terraform
*.tfstate
*.tfstate.backup
.terraform/
*.tfvars.json
!*.tfvars.json.example

# Secrets
*.env
.env.*
```

## Pre-Deployment Checklist

Before running `azd up`:

```bash
# 1. Register required providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 2. Verify registration
az provider show --namespace Microsoft.App --query "registrationState"

# 3. Initialize azd environment
azd init -e <env-name>

# 4. Set required parameters (if not using parameter files)
azd env set POSTGRES_PASSWORD "your-secure-password"
```

## Parameter Mapping

azd maps environment variables to Bicep parameters using `${VAR_NAME}` syntax in `main.parameters.json`:

```json
{
  "parameters": {
    "environmentName": { "value": "${AZURE_ENV_NAME}" },
    "postgresPassword": { "value": "${POSTGRES_PASSWORD}" },
    "n8nBasicAuthPassword": { "value": "${N8N_BASIC_AUTH_PASSWORD}" }
  }
}
```

**Required env vars for n8n deployment:**
```bash
azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set AZURE_LOCATION "westus"
azd env set POSTGRES_PASSWORD "$(openssl rand -base64 16)"
azd env set N8N_BASIC_AUTH_PASSWORD "$(openssl rand -base64 16)"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Hook not running | Check executable permission: `chmod +x *.sh` |
| Output not found | Verify output names match in Bicep/Terraform |
| 409 Conflict | Register providers first |
| Wrong tfvars file | azd uses `main.tfvars.json`, not `terraform.tfvars` |
| `--no-prompt` panics with @secure params | Known azd bug - run interactively or use parameter file |
| Parameter prompting despite env vars | Use `${VAR_NAME}` syntax in main.parameters.json |
| Wrong infra deployed | Check `azure.yaml` points to correct `infra.path` |
| `az login` errors | Run `az login` or check token expiry with `az account show` |
| Subscription not found | Set subscription: `az account set --subscription <id>` |
| "No module named azure" | Install Azure CLI: `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` |
| azd not found | Install: `curl -fsSL https://aka.ms/install-azd.sh \| bash` |
| Permission denied on hooks | Run `chmod +x infra/hooks/*.sh` |

## Quick Diagnostic Commands

```bash
# Check Azure CLI login status
az account show

# List subscriptions
az account list -o table

# Check registered providers
az provider show --namespace Microsoft.App --query "registrationState"

# Check azd environment
azd env list
azd env get-values

# View deployment history
az deployment sub list -o table

# Check resource group resources
az resource list -g <resource-group> -o table
```

## Azure MCP Tools

Use these Azure MCP Server tools to enhance azd workflows:

| Tool | When to Use |
|------|-------------|
| `azure_deploy_plan` | Generate a deployment plan before `azd up` — validates resource configuration and dependencies |
| `azure_deploy_app_logs` | Fetch Log Analytics logs post-deployment for troubleshooting failed deployments |
| `azure_deploy_pipeline` | Get CI/CD pipeline guidance for GitHub Actions integration with azd |
| `azure_deploy_iac_guidance` | Best practices for Bicep/Terraform with azd compatibility |

## Common azd Workflows

### Fresh Deployment
```bash
# 1. Login (if needed)
az login

# 2. Register providers (once per subscription)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# 3. Create and configure environment
azd init -e myenv
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id -o tsv)"
azd env set AZURE_LOCATION "westus"

# 4. Deploy
azd up
```

### Redeploy After Changes
```bash
# Just provision (skip deploy if no services)
azd provision

# Or full deploy
azd up
```

### Clean Teardown
```bash
# Remove all resources
azd down --force --purge

# Verify deletion
az group list --query "[?starts_with(name, 'rg-')]" -o table
```
