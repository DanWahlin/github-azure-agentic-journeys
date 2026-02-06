// ========================================
// Log Analytics Workspace
// ========================================

@description('Name of the Log Analytics workspace')
param name string

@description('Location for the resource')
param location string

@description('Tags to apply to the resource')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output id string = logAnalyticsWorkspace.id
output name string = logAnalyticsWorkspace.name
