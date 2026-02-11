targetScope = 'subscription'

@description('Environment name (used for resource naming)')
param environmentName string

@description('Azure region for all resources')
param location string

@description('PostgreSQL administrator password')
@secure()
param postgresPassword string

@description('n8n basic auth password')
@secure()
param n8nBasicAuthPassword string

@description('n8n encryption key (auto-generated if not provided)')
@secure()
param n8nEncryptionKey string = newGuid()

// Load abbreviations for consistent naming
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, location)
var suffix = take(resourceToken, 6)
var tags = {
  'azd-env-name': environmentName
}

// PostgreSQL configuration
var postgresUser = 'n8n'
var postgresDatabase = 'n8n'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: resourceGroup
  params: {
    name: '${abbrs.logAnalyticsWorkspace}-${suffix}'
    location: location
    tags: tags
  }
}

module containerAppsEnvironment 'modules/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  scope: resourceGroup
  params: {
    name: '${abbrs.containerAppsEnvironment}-${suffix}'
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalytics.outputs.sharedKey
  }
}

module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: resourceGroup
  params: {
    name: '${abbrs.postgreSQLServer}-${suffix}'
    location: location
    tags: tags
    administratorLogin: postgresUser
    administratorLoginPassword: postgresPassword
    databaseName: postgresDatabase
  }
}

module n8nContainerApp 'modules/n8n-container-app.bicep' = {
  name: 'n8n-container-app'
  scope: resourceGroup
  params: {
    name: '${abbrs.containerApp}-${suffix}'
    location: location
    tags: tags
    containerAppEnvironmentId: containerAppsEnvironment.outputs.id
    postgresHost: postgresql.outputs.fqdn
    postgresDatabase: postgresql.outputs.databaseName
    postgresUser: postgresUser
    postgresPassword: postgresPassword
    n8nEncryptionKey: n8nEncryptionKey
    n8nBasicAuthPassword: n8nBasicAuthPassword
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd convention)
output RESOURCE_GROUP_NAME string = resourceGroup.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output POSTGRES_SERVER_NAME string = postgresql.outputs.serverName
output POSTGRES_FQDN string = postgresql.outputs.fqdn
output N8N_CONTAINER_APP_NAME string = n8nContainerApp.outputs.name
output N8N_URL string = n8nContainerApp.outputs.url
output N8N_FQDN string = n8nContainerApp.outputs.fqdn
