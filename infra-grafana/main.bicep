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

@description('Grafana container image')
param grafanaImage string = 'docker.io/grafana/grafana:latest'

@secure()
@description('Grafana admin password')
param grafanaAdminPassword string

@description('Grafana admin username')
param grafanaAdminUser string = 'admin'

@description('Tags to apply to all resources')
param tags object = {
  environment: 'development'
  application: 'grafana'
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

// Grafana Container App
module grafanaApp './modules/grafana-container-app.bicep' = {
  name: 'grafana-container-app'
  scope: rg
  params: {
    name: '${abbrs.appContainerApps}grafana-${resourceToken}'
    location: location
    containerAppsEnvironmentId: containerAppsEnv.outputs.id
    grafanaImage: grafanaImage
    grafanaAdminUser: grafanaAdminUser
    grafanaAdminPassword: grafanaAdminPassword
    tags: tags
  }
}

// ========================================
// OUTPUTS
// ========================================

output RESOURCE_GROUP_NAME string = rg.name
output GRAFANA_CONTAINER_APP_NAME string = grafanaApp.outputs.name
output GRAFANA_URL string = grafanaApp.outputs.url
output GRAFANA_FQDN string = grafanaApp.outputs.fqdn
output GRAFANA_ADMIN_USER string = grafanaAdminUser
