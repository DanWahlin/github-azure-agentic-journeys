# Container Apps Pattern

Azure Container Apps for hosting containerized applications with automatic scaling.

## Resource Definition

```bicep
resource containerApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5678              // App-specific port
        transport: 'auto'
        allowInsecure: false          // Enforce HTTPS
      }
      secrets: [
        { name: 'db-password', value: dbPassword }
        { name: 'encryption-key', value: encryptionKey }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          image: containerImage
          resources: {
            cpu: json('1.0')          // Use json() for decimal
            memory: '2Gi'
          }
          env: [
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'PORT', value: '5678' }
          ]
          probes: [/* See health probes section */]
        }
      ]
      scale: {
        minReplicas: 0                // Scale-to-zero for cost savings
        maxReplicas: 3
      }
    }
  }
}
```

## Health Probes (CRITICAL)

Many applications need 60+ seconds to start. **Default probes will kill containers prematurely.**

### Standard Health Probe Configuration

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: {
      port: 5678
      path: '/'
      scheme: 'HTTP'
    }
    initialDelaySeconds: 60         // CRITICAL: Wait before first check
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
    failureThreshold: 30            // Allows 5 minutes total startup
  }
]
```

### Health Probe Timing Guide

| App Startup Time | `initialDelaySeconds` | `failureThreshold` (startup) |
|------------------|----------------------|------------------------------|
| Fast (<30s) | 10 | 6 |
| Medium (30-60s) | 30 | 12 |
| Slow (60-120s) | 60 | 24 |
| Very slow (>120s) | 90 | 30 |

## Container Apps Environment

Required environment for Container Apps:

```bicep
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}
```

## Managed Identity

Use managed identity for secure Azure service access:

```bicep
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}
```

## Ingress Configuration

| Setting | Development | Production |
|---------|-------------|------------|
| `external` | `true` | `true` or `false` (with APIM) |
| `allowInsecure` | `false` | `false` |
| `transport` | `auto` | `auto` or `http2` |

## Scale Rules

### HTTP Scaling
```bicep
scale: {
  minReplicas: 0
  maxReplicas: 10
  rules: [
    {
      name: 'http-scaling'
      http: {
        metadata: {
          concurrentRequests: '50'
        }
      }
    }
  ]
}
```

### KEDA Scaling (Queue-based)
```bicep
scale: {
  rules: [
    {
      name: 'queue-scaling'
      custom: {
        type: 'azure-queue'
        metadata: {
          queueName: 'myqueue'
          queueLength: '10'
        }
        auth: [
          {
            secretRef: 'storage-connection'
            triggerParameter: 'connection'
          }
        ]
      }
    }
  ]
}
```

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| CrashLoopBackOff | Health probe kills container | Increase `initialDelaySeconds` and `failureThreshold` |
| 502 Bad Gateway | Wrong `targetPort` | Match container's listening port |
| Cold start timeout | Scale-to-zero + slow startup | Use startup probe with high `failureThreshold` |
