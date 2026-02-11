@description('Name of the AKS cluster')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Kubernetes version')
param kubernetesVersion string = '1.33'

@description('VM size for system node pool')
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('Number of nodes in system pool')
param systemNodeCount int = 1

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: name
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
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
