@description('Container Apps Environment name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Log Analytics customer ID')
param logAnalyticsCustomerId string

@secure()
@description('Log Analytics shared key')
param logAnalyticsSharedKey string

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

output id string = containerAppsEnv.id
output name string = containerAppsEnv.name
