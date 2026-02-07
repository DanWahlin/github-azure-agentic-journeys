@description('AKS cluster name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: name
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'system'
        count: 1
        minCount: 1
        maxCount: 3
        vmSize: 'Standard_B2ms'
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: true
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
  }
}

output name string = aksCluster.name
output id string = aksCluster.id
