targetScope = 'subscription'

// ========================================
// PARAMETERS
// ========================================

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string = 'westus'

@description('n8n container image')
param n8nImage string = 'docker.io/n8nio/n8n:latest'

@description('PostgreSQL administrator username')
param postgresUser string = 'n8n'

@secure()
@description('PostgreSQL administrator password')
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

@description('Tags to apply to all resources')
param tags object = {
  environment: 'development'
  application: 'n8n'
  'azd-env-name': environmentName
}

// ========================================
// VARIABLES
// ========================================

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var resourceGroupName = '${abbrs.resourcesResourceGroups}${environmentName}'

// ========================================
// RESOURCE GROUP
// ========================================

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ========================================
// MODULES
// ========================================

// Log Analytics Workspace
module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

// Managed Identity
module managedIdentity './modules/managed-identity.bicep' = {
  name: 'managed-identity'
  scope: rg
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

// Container Apps Environment
module containerAppsEnv './modules/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  scope: rg
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    tags: tags
  }
}

// PostgreSQL Flexible Server
module postgres './modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: rg
  params: {
    serverName: '${abbrs.dBforPostgreSQLServers}${resourceToken}'
    databaseName: postgresDb
    location: location
    administratorLogin: postgresUser
    administratorPassword: postgresPassword
    tags: tags
  }
}

// n8n Container App
module n8nApp './modules/n8n-container-app.bicep' = {
  name: 'n8n-container-app'
  scope: rg
  params: {
    name: '${abbrs.appContainerApps}n8n-${resourceToken}'
    location: location
    containerAppsEnvironmentId: containerAppsEnv.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    n8nImage: n8nImage
    postgresHost: postgres.outputs.fqdn
    postgresDb: postgresDb
    postgresUser: postgresUser
    postgresPassword: postgresPassword
    n8nEncryptionKey: n8nEncryptionKey
    n8nBasicAuthActive: n8nBasicAuthActive
    n8nBasicAuthUser: n8nBasicAuthUser
    n8nBasicAuthPassword: n8nBasicAuthPassword
    tags: tags
  }
}

// ========================================
// OUTPUTS
// ========================================

output RESOURCE_GROUP_NAME string = rg.name
output N8N_CONTAINER_APP_NAME string = n8nApp.outputs.name
output N8N_URL string = n8nApp.outputs.url
output N8N_FQDN string = n8nApp.outputs.fqdn
output POSTGRES_SERVER_NAME string = postgres.outputs.serverName
output POSTGRES_CONTAINER_APP_NAME string = postgres.outputs.serverName // Alias for compatibility
output POSTGRES_FQDN string = postgres.outputs.fqdn
output POSTGRES_DATABASE_NAME string = postgres.outputs.databaseName
output MANAGED_IDENTITY_NAME string = managedIdentity.outputs.name
output N8N_BASIC_AUTH_USER string = n8nBasicAuthUser
