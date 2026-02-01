# Bicep Requirements for n8n Azure Deployment

## Parameters Definition

```bicep
@description('Environment name used for resource naming')
param environmentName string

@description('Azure region for deployment')
param location string = 'westus'

@description('PostgreSQL admin username')
param postgresUser string = 'n8n'

@secure()
@description('PostgreSQL admin password')
param postgresPassword string

@description('PostgreSQL database name')
param postgresDb string = 'n8n'

@description('Enable n8n basic authentication')
param n8nBasicAuthActive bool = true

@description('n8n basic auth username')
param n8nBasicAuthUser string = 'admin'

@secure()
@description('n8n basic auth password')
param n8nBasicAuthPassword string

@secure()
@description('n8n encryption key (auto-generated if not provided)')
param n8nEncryptionKey string = newGuid()

@description('n8n Docker image')
param n8nImage string = 'docker.io/n8nio/n8n:latest'
```

**CRITICAL**: `newGuid()` can ONLY be used as a parameter default value. Never in variables or expressions.

## Resource Naming

```bicep
var resourceToken = uniqueString(subscription().id, resourceGroup().id, environmentName)
var suffix = take(resourceToken, 6)
var containerAppName = 'n8n-${suffix}'
var containerEnvName = 'cae-${suffix}'
var logAnalyticsName = 'log-${suffix}'
var postgresServerName = 'pg-${suffix}'
var managedIdentityName = 'id-${suffix}'
```

## Log Analytics Workspace

```bicep
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}
```

## Container Apps Environment

```bicep
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: containerEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}
```

## Managed Identity

```bicep
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}
```

## PostgreSQL Flexible Server

```bicep
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: postgresServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: postgresUser
    administratorLoginPassword: postgresPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
    }
  }
}

resource postgresFirewallAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgresServer
  name: postgresDb
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}
```

## Health Probes Configuration (CRITICAL)

**These settings are MANDATORY for successful deployment. n8n requires extended startup time.**

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: {
      port: 5678
      path: '/'
      scheme: 'HTTP'
    }
    initialDelaySeconds: 60    // n8n needs 60s to fully start
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
    failureThreshold: 30       // Allows up to 5 minutes for startup
  }
]
```

**Why Critical**: Without proper health probe configuration, Azure Container Apps will kill the n8n container before it completes initialization, causing "CrashLoopBackOff" errors.

## n8n Container App

```bicep
resource n8nApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5678
        transport: 'auto'
        allowInsecure: false
      }
      secrets: [
        { name: 'postgres-password', value: postgresPassword }
        { name: 'n8n-encryption-key', value: n8nEncryptionKey }
        { name: 'n8n-auth-password', value: n8nBasicAuthPassword }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: n8nImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'DB_TYPE', value: 'postgresdb' }
            { name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
            { name: 'DB_POSTGRESDB_PORT', value: '5432' }
            { name: 'DB_POSTGRESDB_DATABASE', value: postgresDb }
            { name: 'DB_POSTGRESDB_USER', value: postgresUser }
            { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
            { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
            { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
            { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
            { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
            { name: 'N8N_BASIC_AUTH_ACTIVE', value: string(n8nBasicAuthActive) }
            { name: 'N8N_BASIC_AUTH_USER', value: n8nBasicAuthUser }
            { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
            { name: 'N8N_PORT', value: '5678' }
            { name: 'N8N_PROTOCOL', value: 'https' }
          ]
          probes: [
            {
              type: 'liveness'
              httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'readiness'
              httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'startup'
              httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
  dependsOn: [postgresDatabase]
}
```

## Required Outputs

These outputs are used by post-provision hooks:

```bicep
output AZURE_LOCATION string = location
output RESOURCE_GROUP_NAME string = resourceGroup().name
output N8N_CONTAINER_APP_NAME string = n8nApp.name
output N8N_URL string = 'https://${n8nApp.properties.configuration.ingress.fqdn}'
output N8N_FQDN string = n8nApp.properties.configuration.ingress.fqdn
output POSTGRES_SERVER_NAME string = postgresServer.name
output POSTGRES_FQDN string = postgresServer.properties.fullyQualifiedDomainName
output POSTGRES_DATABASE_NAME string = postgresDatabase.name
output MANAGED_IDENTITY_NAME string = managedIdentity.name
output N8N_BASIC_AUTH_USER string = n8nBasicAuthUser
```

**Note**: Output names must match what post-provision scripts expect via `azd env get-value`.
