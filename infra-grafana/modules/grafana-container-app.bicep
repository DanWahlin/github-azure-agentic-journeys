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

@description('Grafana container image')
param containerImage string = 'docker.io/grafana/grafana:latest'

@description('Grafana admin username')
param grafanaAdminUser string = 'admin'

@secure()
@description('Grafana admin password')
param grafanaAdminPassword string

@description('Grafana plugins to install (comma-separated)')
param grafanaInstallPlugins string = ''

resource grafanaApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
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
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'GF_SECURITY_ADMIN_USER', value: grafanaAdminUser }
            { name: 'GF_SECURITY_ADMIN_PASSWORD', secretRef: 'grafana-admin-password' }
            { name: 'GF_SERVER_HTTP_PORT', value: '3000' }
            { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'false' }
            { name: 'GF_INSTALL_PLUGINS', value: grafanaInstallPlugins }
          ]
          probes: [
            {
              type: 'startup'
              httpGet: {
                port: 3000
                path: '/api/health'
                scheme: 'HTTP'
              }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 10
            }
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

output name string = grafanaApp.name
output fqdn string = grafanaApp.properties.configuration.ingress.fqdn
output url string = 'https://${grafanaApp.properties.configuration.ingress.fqdn}'
