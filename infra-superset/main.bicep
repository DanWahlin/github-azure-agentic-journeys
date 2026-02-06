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
param location string = 'eastus'

@description('Superset container image')
param supersetImage string = 'apache/superset:latest'

@description('PostgreSQL administrator username')
param postgresUser string = 'superset'

@secure()
@description('PostgreSQL administrator password')
param postgresPassword string

@description('PostgreSQL database name')
param postgresDb string = 'superset'

@secure()
@description('Superset secret key for Flask (32+ characters)')
param supersetSecretKey string

@description('Superset admin username')
param supersetAdminUser string = 'admin'

@secure()
@description('Superset admin password')
param supersetAdminPassword string

@description('Kubernetes version')
param kubernetesVersion string = '1.33'

@description('AKS node VM size')
param aksNodeVmSize string = 'Standard_D2s_v3'

@description('Number of AKS nodes')
param aksNodeCount int = 2

@description('Tags to apply to all resources')
param tags object = {
  environment: 'development'
  application: 'superset'
  'azd-env-name': environmentName
}

// ========================================
// VARIABLES
// ========================================

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var resourceGroupName = '${abbrs.resourcesResourceGroups}${environmentName}'
var aksClusterName = '${abbrs.containerServiceManagedClusters}${resourceToken}'

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

// Managed Identity for deployment scripts
module managedIdentity './modules/managed-identity.bicep' = {
  name: 'managed-identity'
  scope: rg
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

// PostgreSQL Flexible Server
module postgres './modules/postgresql.bicep' = {
  name: 'postgresql'
  scope: rg
  params: {
    serverName: '${abbrs.dBforPostgreSQLServers}${resourceToken}'
    databaseName: postgresDb
    location: location
    administratorLogin: postgresUser
    administratorPassword: postgresPassword
    tags: tags
  }
}

// AKS Cluster
module aks './modules/aks.bicep' = {
  name: 'aks-cluster'
  scope: rg
  params: {
    name: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeVmSize: aksNodeVmSize
    nodeCount: aksNodeCount
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    tags: tags
  }
}

// Role assignment for deployment script
module aksRoleAssignment './modules/aks-role-assignment.bicep' = {
  name: 'aks-role-assignment'
  scope: rg
  params: {
    aksClusterName: aks.outputs.name
    principalId: managedIdentity.outputs.principalId
  }
}

// Deploy Kubernetes resources
module k8sDeployment './modules/k8s-deployment.bicep' = {
  name: 'k8s-deployment'
  scope: rg
  params: {
    location: location
    aksClusterName: aks.outputs.name
    managedIdentityId: managedIdentity.outputs.id
    supersetImage: supersetImage
    postgresHost: postgres.outputs.fqdn
    postgresDb: postgresDb
    postgresUser: postgresUser
    postgresPassword: postgresPassword
    supersetSecretKey: supersetSecretKey
    supersetAdminUser: supersetAdminUser
    supersetAdminPassword: supersetAdminPassword
    tags: tags
  }
  dependsOn: [aksRoleAssignment]
}

// ========================================
// OUTPUTS
// ========================================

output RESOURCE_GROUP_NAME string = rg.name
output AKS_CLUSTER_NAME string = aks.outputs.name
output AKS_FQDN string = aks.outputs.fqdn
output POSTGRES_SERVER_NAME string = postgres.outputs.serverName
output POSTGRES_FQDN string = postgres.outputs.fqdn
output POSTGRES_DATABASE_NAME string = postgres.outputs.databaseName
output SUPERSET_ADMIN_USER string = supersetAdminUser
output MANAGED_IDENTITY_NAME string = managedIdentity.outputs.name
