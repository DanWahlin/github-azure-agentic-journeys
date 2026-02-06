@description('Name of the AKS cluster')
param name string

@description('Location for the resource')
param location string

@description('Kubernetes version')
param kubernetesVersion string = '1.29'

@description('VM size for nodes')
param nodeVmSize string = 'Standard_D2s_v3'

@description('Number of nodes')
param nodeCount int = 2

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Tags to apply')
param tags object = {}

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
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: false
      }
    ]
    
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      loadBalancerSku: 'standard'
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
output fqdn string = aksCluster.properties.fqdn
output principalId string = aksCluster.identity.principalId
