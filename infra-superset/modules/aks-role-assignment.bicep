@description('Name of the AKS cluster')
param aksClusterName string

@description('Principal ID of the managed identity')
param principalId string

// Reference existing AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' existing = {
  name: aksClusterName
}

// Azure Kubernetes Service Cluster Admin Role
var aksClusterAdminRoleId = '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, principalId, aksClusterAdminRoleId)
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', aksClusterAdminRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
