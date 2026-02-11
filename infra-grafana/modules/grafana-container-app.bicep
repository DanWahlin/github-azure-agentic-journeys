@description('Name of the Container App')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Container Apps Environment ID')
param containerAppEnvironmentId string

@description('Grafana container image')
param grafanaImage string = 'docker.io/grafana/grafana:latest'

@description('Grafana admin username')
param grafanaAdminUser string = 'admin'

@description('Grafana admin password')
@secure()
param grafanaAdminPassword string

resource containerApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
        allowInsecure: false
      }
      secrets: [
        { name: 'grafana-admin-password', value: grafanaAdminPassword }
      ]
    }
    template: {
      containers: [
        {
          name: 'grafana'
          image: grafanaImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'GF_SECURITY_ADMIN_USER', value: grafanaAdminUser }
            { name: 'GF_SECURITY_ADMIN_PASSWORD', secretRef: 'grafana-admin-password' }
            { name: 'GF_SERVER_HTTP_PORT', value: '3000' }
            { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'false' }
          ]
          probes: [
            {
              type: 'liveness'
              httpGet: {
                port: 3000
                path: '/api/health'
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'readiness'
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
              type: 'startup'
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

output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output url string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
