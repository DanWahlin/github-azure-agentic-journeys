targetScope = 'subscription'

@description('Environment name used for resource naming')
param environmentName string

@description('Azure region for all resources')
param location string

@secure()
@description('PostgreSQL admin password')
param postgresPassword string

@secure()
@description('n8n basic auth password')
param n8nBasicAuthPassword string

@secure()
@description('n8n encryption key (auto-generated if not provided)')
param n8nEncryptionKey string = newGuid()

// Load abbreviations for consistent naming
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, location)

// Tags applied to all resources
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
}

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourceGroup}-n8n-${environmentName}'
  location: location
  tags: tags
}

// Log Analytics Workspace
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: rg
  params: {
    name: '${abbrs.logAnalyticsWorkspace}-${resourceToken}'
    location: location
    tags: tags
  }
}

// Managed Identity
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managed-identity'
  scope: rg
  params: {
    name: '${abbrs.managedIdentity}-${resourceToken}'
    location: location
    tags: tags
  }
}

// Container Apps Environment
module containerAppsEnv 'modules/container-apps-environment.bicep' = {
  name: 'container-apps-env'
  scope: rg
  params: {
    name: '${abbrs.containerAppsEnvironment}-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalytics.outputs.primarySharedKey
  }
}

// PostgreSQL Flexible Server
module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: rg
  params: {
    serverName: '${abbrs.postgreSQLServer}-${resourceToken}'
    location: location
    tags: tags
    adminUser: 'n8n'
    adminPassword: postgresPassword
    databaseName: 'n8n'
  }
}

// n8n Container App
module n8nApp 'modules/n8n-container-app.bicep' = {
  name: 'n8n-container-app'
  scope: rg
  params: {
    name: '${abbrs.containerApp}-n8n-${resourceToken}'
    location: location
    tags: tags
    containerAppsEnvironmentId: containerAppsEnv.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    postgresHost: postgresql.outputs.fqdn
    postgresUser: 'n8n'
    postgresPassword: postgresPassword
    postgresDatabase: 'n8n'
    n8nEncryptionKey: n8nEncryptionKey
    n8nBasicAuthPassword: n8nBasicAuthPassword
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd)
output RESOURCE_GROUP_NAME string = rg.name
output N8N_CONTAINER_APP_NAME string = n8nApp.outputs.name
output N8N_URL string = n8nApp.outputs.url
output N8N_FQDN string = n8nApp.outputs.fqdn
output POSTGRES_FQDN string = postgresql.outputs.fqdn
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
