# Naming Conventions

Consistent resource naming for Azure deployments.

## Unique Suffix Generation

Generate a unique suffix to prevent naming conflicts:

```bicep
// Generate unique token from subscription + resource group + environment
var resourceToken = uniqueString(subscription().id, resourceGroup().id, environmentName)
var suffix = take(resourceToken, 6)
```

## Resource Name Patterns

Use abbreviated prefixes + suffix pattern:

```bicep
var containerAppName = 'app-${suffix}'
var containerEnvName = 'cae-${suffix}'
var logAnalyticsName = 'log-${suffix}'
var postgresServerName = 'pg-${suffix}'
var managedIdentityName = 'id-${suffix}'
var keyVaultName = 'kv-${suffix}'
var storageAccountName = 'st${suffix}'  // No hyphens allowed
```

## Standard Abbreviations

Based on Microsoft's Cloud Adoption Framework:

| Resource Type | Abbreviation | Example |
|---------------|--------------|---------|
| Resource Group | `rg` | `rg-myapp-dev` |
| Container App | `app` | `app-n8n-abc123` |
| Container Apps Environment | `cae` | `cae-abc123` |
| Log Analytics Workspace | `log` | `log-abc123` |
| PostgreSQL Server | `pg` or `psql` | `pg-abc123` |
| Managed Identity | `id` | `id-abc123` |
| Key Vault | `kv` | `kv-abc123` |
| Storage Account | `st` | `stabc123` |
| Virtual Network | `vnet` | `vnet-abc123` |

## Abbreviations JSON File

Store abbreviations in a JSON file for consistency:

```json
// infra/abbreviations.json
{
  "containerApp": "app",
  "containerAppsEnvironment": "cae",
  "logAnalyticsWorkspace": "log",
  "postgreSQLServer": "pg",
  "managedIdentity": "id",
  "keyVault": "kv",
  "storageAccount": "st",
  "resourceGroup": "rg"
}
```

Load in Bicep:

```bicep
var abbrs = loadJsonContent('abbreviations.json')
var containerAppName = '${abbrs.containerApp}-${suffix}'
```

## Naming Constraints

| Resource | Max Length | Allowed Characters |
|----------|------------|-------------------|
| Container App | 32 | `a-z`, `0-9`, `-` |
| PostgreSQL Server | 63 | `a-z`, `0-9`, `-` |
| Storage Account | 24 | `a-z`, `0-9` (no hyphens!) |
| Key Vault | 24 | `a-z`, `0-9`, `-` |
| Resource Group | 90 | `a-z`, `A-Z`, `0-9`, `-`, `_`, `.`, `()` |

## Environment-Based Naming

Include environment in resource group name:

```bicep
param environmentName string  // 'dev', 'staging', 'prod'

// Resource group name pattern
var rgName = 'rg-myapp-${environmentName}'

// Resources use suffix for uniqueness within RG
var appName = 'app-${suffix}'
```

## Output Naming Convention

Use SCREAMING_SNAKE_CASE for outputs (azd convention):

```bicep
output RESOURCE_GROUP_NAME string = resourceGroup().name
output CONTAINER_APP_NAME string = containerApp.name
output APP_URL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output POSTGRES_FQDN string = postgresServer.properties.fullyQualifiedDomainName
```

## Tags

Apply consistent tags for management:

```bicep
param tags object = {
  environment: environmentName
  application: 'myapp'
  'azd-env-name': environmentName  // Required for azd
}

resource containerApp '...' = {
  // ...
  tags: tags
}
```

## Complete Example

```bicep
@description('Environment name (e.g., dev, staging, prod)')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

// Load abbreviations
var abbrs = loadJsonContent('abbreviations.json')

// Generate unique suffix
var resourceToken = uniqueString(subscription().id, resourceGroup().id, environmentName)
var suffix = take(resourceToken, 6)

// Resource names
var containerAppName = '${abbrs.containerApp}-${suffix}'
var containerEnvName = '${abbrs.containerAppsEnvironment}-${suffix}'
var logAnalyticsName = '${abbrs.logAnalyticsWorkspace}-${suffix}'
var postgresServerName = '${abbrs.postgreSQLServer}-${suffix}'
var identityName = '${abbrs.managedIdentity}-${suffix}'

// Tags
var tags = {
  environment: environmentName
  'azd-env-name': environmentName
}
```
