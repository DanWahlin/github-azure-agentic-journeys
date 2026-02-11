targetScope = 'subscription'

@description('Environment name (used for resource naming)')
param environmentName string

@description('Azure region for all resources')
param location string

@description('Grafana container image')
param grafanaImage string = 'docker.io/grafana/grafana:latest'

@description('Grafana admin username')
param grafanaAdminUser string = 'admin'

@description('Grafana admin password')
@secure()
param grafanaAdminPassword string

// Load abbreviations for consistent naming
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, location)
var suffix = take(resourceToken, 6)
var tags = {
  'azd-env-name': environmentName
}

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

module grafanaContainerApp 'modules/grafana-container-app.bicep' = {
  name: 'grafana-container-app'
  scope: resourceGroup
  params: {
    name: '${abbrs.containerApp}-${suffix}'
    location: location
    tags: tags
    containerAppEnvironmentId: containerAppsEnvironment.outputs.id
    grafanaImage: grafanaImage
    grafanaAdminUser: grafanaAdminUser
    grafanaAdminPassword: grafanaAdminPassword
  }
}

// Outputs (SCREAMING_SNAKE_CASE for azd convention)
output RESOURCE_GROUP_NAME string = resourceGroup.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output GRAFANA_CONTAINER_APP_NAME string = grafanaContainerApp.outputs.name
output GRAFANA_URL string = grafanaContainerApp.outputs.url
output GRAFANA_FQDN string = grafanaContainerApp.outputs.fqdn
output GRAFANA_ADMIN_USER string = grafanaAdminUser
