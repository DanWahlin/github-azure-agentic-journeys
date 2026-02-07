@description('Container App name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Container Apps Environment resource ID')
param containerAppsEnvironmentId string

@description('Managed Identity resource ID')
param managedIdentityId string

@description('PostgreSQL server FQDN')
param postgresHost string

@description('PostgreSQL admin user')
param postgresUser string

@secure()
@description('PostgreSQL admin password')
param postgresPassword string

@description('PostgreSQL database name')
param postgresDatabase string

@secure()
@description('n8n encryption key')
param n8nEncryptionKey string

@secure()
@description('n8n basic auth password')
param n8nBasicAuthPassword string

@description('n8n container image')
param containerImage string = 'docker.io/n8nio/n8n:latest'

@description('n8n basic auth username')
param n8nBasicAuthUser string = 'admin'

resource n8nApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 5678
        transport: 'auto'
        allowInsecure: false
      }
      secrets: [
        { name: 'postgres-password', value: postgresPassword }
        { name: 'n8n-encryption-key', value: n8nEncryptionKey }
        { name: 'n8n-auth-password', value: n8nBasicAuthPassword }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: containerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            // Database
            { name: 'DB_TYPE', value: 'postgresdb' }
            { name: 'DB_POSTGRESDB_HOST', value: postgresHost }
            { name: 'DB_POSTGRESDB_PORT', value: '5432' }
            { name: 'DB_POSTGRESDB_DATABASE', value: postgresDatabase }
            { name: 'DB_POSTGRESDB_USER', value: postgresUser }
            { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
            { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
            { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
            { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
            // n8n core
            { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
            { name: 'N8N_PORT', value: '5678' }
            { name: 'N8N_PROTOCOL', value: 'https' }
            // Authentication
            { name: 'N8N_BASIC_AUTH_ACTIVE', value: 'true' }
            { name: 'N8N_BASIC_AUTH_USER', value: n8nBasicAuthUser }
            { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
            // Node.js SSL
            { name: 'NODE_TLS_REJECT_UNAUTHORIZED', value: '0' }
          ]
          probes: [
            {
              type: 'startup'
              httpGet: {
                port: 5678
                path: '/'
                scheme: 'HTTP'
              }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 30
              initialDelaySeconds: 30
            }
            {
              type: 'liveness'
              httpGet: {
                port: 5678
                path: '/'
                scheme: 'HTTP'
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'readiness'
              httpGet: {
                port: 5678
                path: '/'
                scheme: 'HTTP'
              }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

output name string = n8nApp.name
output fqdn string = n8nApp.properties.configuration.ingress.fqdn
output url string = 'https://${n8nApp.properties.configuration.ingress.fqdn}'
