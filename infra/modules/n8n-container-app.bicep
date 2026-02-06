// ========================================
// n8n Container App
// ========================================

@description('Name of the Container App')
param name string

@description('Location for the resource')
param location string

@description('Container Apps environment resource ID')
param containerAppsEnvironmentId string

@description('Managed identity resource ID')
param managedIdentityId string

@description('n8n container image')
param n8nImage string

@description('PostgreSQL server FQDN')
param postgresHost string

@description('PostgreSQL database name')
param postgresDb string

@description('PostgreSQL username')
param postgresUser string

@secure()
@description('PostgreSQL password')
param postgresPassword string

@secure()
@description('n8n encryption key')
param n8nEncryptionKey string

@description('Enable n8n basic authentication')
param n8nBasicAuthActive bool

@description('n8n basic auth username')
param n8nBasicAuthUser string

@secure()
@description('n8n basic auth password')
param n8nBasicAuthPassword string

@description('Tags to apply to the resource')
param tags object = {}

resource n8nContainerApp 'Microsoft.App/containerApps@2024-03-01' = {
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
    environmentId: containerAppsEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 5678
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'postgres-password'
          value: postgresPassword
        }
        {
          name: 'n8n-encryption-key'
          value: n8nEncryptionKey
        }
        {
          name: 'n8n-basic-auth-password'
          value: n8nBasicAuthPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: n8nImage
          env: [
            {
              name: 'DB_TYPE'
              value: 'postgresdb'
            }
            {
              name: 'DB_POSTGRESDB_HOST'
              value: postgresHost
            }
            {
              name: 'DB_POSTGRESDB_SSL_ENABLED'
              value: 'true'
            }
            {
              name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED'
              value: 'false'
            }
            {
              name: 'DB_POSTGRESDB_PORT'
              value: '5432'
            }
            {
              name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT'
              value: '60000'
            }
            {
              name: 'DB_POSTGRESDB_DATABASE'
              value: postgresDb
            }
            {
              name: 'DB_POSTGRESDB_USER'
              value: postgresUser
            }
            {
              name: 'DB_POSTGRESDB_PASSWORD'
              secretRef: 'postgres-password'
            }
            {
              name: 'N8N_ENCRYPTION_KEY'
              secretRef: 'n8n-encryption-key'
            }
            {
              name: 'N8N_BASIC_AUTH_ACTIVE'
              value: n8nBasicAuthActive ? 'true' : 'false'
            }
            {
              name: 'N8N_BASIC_AUTH_USER'
              value: n8nBasicAuthUser
            }
            {
              name: 'N8N_BASIC_AUTH_PASSWORD'
              secretRef: 'n8n-basic-auth-password'
            }
            {
              name: 'N8N_PORT'
              value: '5678'
            }
            {
              name: 'N8N_PROTOCOL'
              value: 'https'
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          probes: [
            {
              type: 'Liveness'
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
              type: 'Readiness'
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
              type: 'Startup'
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
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output id string = n8nContainerApp.id
output name string = n8nContainerApp.name
output fqdn string = n8nContainerApp.properties.configuration.ingress.fqdn
output url string = 'https://${n8nContainerApp.properties.configuration.ingress.fqdn}'
