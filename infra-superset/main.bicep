targetScope = 'subscription'

@description('Environment name (used for resource naming)')
param environmentName string

@description('Azure region for all resources')
param location string

@description('PostgreSQL administrator password')
@secure()
param postgresPassword string

@description('Superset Flask secret key (32+ chars)')
@secure()
param supersetSecretKey string

@description('Superset admin password')
@secure()
param supersetAdminPassword string

@description('Superset container image')
param supersetImage string = 'docker.io/apache/superset:latest'

// Load abbreviations for consistent naming
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, location)
var suffix = take(resourceToken, 6)
var tags = {
  'azd-env-name': environmentName
}

// PostgreSQL configuration
var postgresUser = 'superset'
var postgresDatabase = 'superset'

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

module aksCluster 'modules/aks-cluster.bicep' = {
  name: 'aks-cluster'
  scope: resourceGroup
  params: {
    name: '${abbrs.aksCluster}-${suffix}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd convention)
output RESOURCE_GROUP_NAME string = resourceGroup.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output POSTGRES_SERVER_NAME string = postgresql.outputs.serverName
output POSTGRES_FQDN string = postgresql.outputs.fqdn
output POSTGRES_DATABASE string = postgresql.outputs.databaseName
output POSTGRES_USER string = postgresUser
output AKS_CLUSTER_NAME string = aksCluster.outputs.name
output SUPERSET_IMAGE string = supersetImage
output SUPERSET_URL string = 'http://<pending-ingress-ip>'
