@description('Name of the Container App')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Container Apps Environment ID')
param containerAppEnvironmentId string

@description('n8n container image')
param containerImage string = 'docker.io/n8nio/n8n:latest'

@description('PostgreSQL FQDN')
param postgresHost string

@description('PostgreSQL database name')
param postgresDatabase string

@description('PostgreSQL user')
param postgresUser string

@description('PostgreSQL password')
@secure()
param postgresPassword string

@description('n8n encryption key')
@secure()
param n8nEncryptionKey string

@description('Enable n8n basic auth')
param n8nBasicAuthActive bool = true

@description('n8n basic auth user')
param n8nBasicAuthUser string = 'admin'

@description('n8n basic auth password')
@secure()
param n8nBasicAuthPassword string

resource containerApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppEnvironmentId
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
            // n8n Core
            { name: 'N8N_PORT', value: '5678' }
            { name: 'N8N_PROTOCOL', value: 'https' }
            { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
            // Authentication
            { name: 'N8N_BASIC_AUTH_ACTIVE', value: string(n8nBasicAuthActive) }
            { name: 'N8N_BASIC_AUTH_USER', value: n8nBasicAuthUser }
            { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
          ]
          probes: [
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

output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output url string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
