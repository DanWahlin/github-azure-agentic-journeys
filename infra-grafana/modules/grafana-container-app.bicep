// ========================================
// Grafana Container App
// ========================================

@description('Name of the Container App')
param name string

@description('Location for the resource')
param location string

@description('Container Apps environment resource ID')
param containerAppsEnvironmentId string

@description('Grafana container image')
param grafanaImage string

@description('Grafana admin username')
param grafanaAdminUser string

@secure()
@description('Grafana admin password')
param grafanaAdminPassword string

@description('Tags to apply to the resource')
param tags object = {}

resource grafanaContainerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
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
          name: 'grafana-admin-password'
          value: grafanaAdminPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'grafana'
          image: grafanaImage
          env: [
            {
              name: 'GF_SECURITY_ADMIN_USER'
              value: grafanaAdminUser
            }
            {
              name: 'GF_SECURITY_ADMIN_PASSWORD'
              secretRef: 'grafana-admin-password'
            }
            {
              name: 'GF_SERVER_HTTP_PORT'
              value: '3000'
            }
            {
              name: 'GF_SERVER_ROOT_URL'
              value: '%(protocol)s://%(domain)s/'
            }
            {
              name: 'GF_AUTH_ANONYMOUS_ENABLED'
              value: 'false'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                port: 3000
                path: '/api/health'
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                port: 3000
                path: '/api/health'
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
                port: 3000
                path: '/api/health'
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

output id string = grafanaContainerApp.id
output name string = grafanaContainerApp.name
output fqdn string = grafanaContainerApp.properties.configuration.ingress.fqdn
output url string = 'https://${grafanaContainerApp.properties.configuration.ingress.fqdn}'
