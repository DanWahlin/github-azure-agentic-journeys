targetScope = 'subscription'

@description('Environment name used for resource naming')
param environmentName string

@description('Azure region for all resources')
param location string

@secure()
@description('PostgreSQL admin password')
param postgresPassword string

@secure()
@description('Superset Flask secret key')
param supersetSecretKey string

@secure()
@description('Superset admin password')
param supersetAdminPassword string

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
  name: '${abbrs.resourceGroup}-superset-${environmentName}'
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

// PostgreSQL Flexible Server
module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: rg
  params: {
    serverName: '${abbrs.postgreSQLServer}-${resourceToken}'
    location: location
    tags: tags
    adminUser: 'superset'
    adminPassword: postgresPassword
    databaseName: 'superset'
  }
}

// AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aks-cluster'
  scope: rg
  params: {
    name: '${abbrs.aksCluster}-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd)
output RESOURCE_GROUP_NAME string = rg.name
output AKS_CLUSTER_NAME string = aks.outputs.name
output POSTGRES_FQDN string = postgresql.outputs.fqdn
output POSTGRES_DATABASE_NAME string = postgresql.outputs.databaseName
output POSTGRES_ADMIN_USER string = 'superset'
output POSTGRES_PASSWORD string = postgresPassword
output SUPERSET_SECRET_KEY string = supersetSecretKey
output SUPERSET_ADMIN_PASSWORD string = supersetAdminPassword
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
