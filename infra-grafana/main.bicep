targetScope = 'subscription'

@description('Environment name used for resource naming')
param environmentName string

@description('Azure region for all resources')
param location string

@secure()
@description('Grafana admin password')
param grafanaAdminPassword string

@description('Grafana container image')
param grafanaImage string = 'docker.io/grafana/grafana:latest'

@description('Grafana admin username')
param grafanaAdminUser string = 'admin'

@description('Grafana plugins to install (comma-separated)')
param grafanaInstallPlugins string = ''

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
  name: '${abbrs.resourceGroup}-grafana-${environmentName}'
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

// Grafana Container App
module grafanaApp 'modules/grafana-container-app.bicep' = {
  name: 'grafana-container-app'
  scope: rg
  params: {
    name: '${abbrs.containerApp}-grafana-${resourceToken}'
    location: location
    tags: tags
    containerAppsEnvironmentId: containerAppsEnv.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    containerImage: grafanaImage
    grafanaAdminUser: grafanaAdminUser
    grafanaAdminPassword: grafanaAdminPassword
    grafanaInstallPlugins: grafanaInstallPlugins
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd)
output RESOURCE_GROUP_NAME string = rg.name
output GRAFANA_CONTAINER_APP_NAME string = grafanaApp.outputs.name
output GRAFANA_URL string = grafanaApp.outputs.url
output GRAFANA_FQDN string = grafanaApp.outputs.fqdn
output GRAFANA_ADMIN_USER string = grafanaAdminUser
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
