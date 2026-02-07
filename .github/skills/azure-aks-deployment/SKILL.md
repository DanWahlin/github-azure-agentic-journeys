---
name: azure-aks-deployment
description: Deploy applications to Azure Kubernetes Service (AKS). Use when containerized apps need Kubernetes orchestration, custom networking, or complex scaling patterns.
---

# Azure AKS Deployment Skill

Deploy production-ready applications on Azure Kubernetes Service with integrated Azure services.

## When to Use AKS vs Container Apps

| Use AKS When | Use Container Apps When |
|--------------|------------------------|
| Need Kubernetes APIs/CRDs | Simple HTTP/background apps |
| Complex networking (CNI, network policies) | Quick deployment, less config |
| Custom ingress controllers | Built-in ingress is sufficient |
| Helm charts or GitOps workflows | azd-native deployment |
| Multi-container pods, sidecars | Single container per app |
| Need node-level control | Serverless is preferred |

## Architecture Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                     Azure Resource Group                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    AKS Cluster                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │   │
│  │  │   Ingress   │  │    App      │  │   Redis    │  │   │
│  │  │  Controller │  │  (Superset) │  │  (Cache)   │  │   │
│  │  └─────────────┘  └─────────────┘  └────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                              │
│  ┌───────────────────────────┼───────────────────────────┐ │
│  │              Private Endpoint / VNet Integration       │ │
│  └───────────────────────────┼───────────────────────────┘ │
│                              ▼                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           PostgreSQL Flexible Server                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Key Patterns

### 1. AKS Cluster Configuration (Bicep)

```bicep
resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    kubernetesVersion: '1.29'
    enableRBAC: true
    
    agentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: 'Standard_D2s_v3'
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
      }
    ]
    
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    
    // Enable HTTP Application Routing for simple ingress
    addonProfiles: {
      httpApplicationRouting: {
        enabled: true
      }
    }
  }
}
```

### 2. PostgreSQL Integration

PostgreSQL Flexible Server with firewall rule allowing Azure services:

```bicep
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: postgresName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: { storageSizeGB: 32 }
    // Allow Azure services
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}
```

### 3. Kubernetes Deployment Pattern

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myimage:latest
        ports:
        - containerPort: 8088
        envFrom:
        - secretRef:
            name: app-secrets
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
```

### 4. Ingress with NGINX

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

## Critical AKS Considerations

### 1. Deployment Script for Kubernetes Resources

Use deployment scripts to apply K8s manifests after cluster creation:

```bicep
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-k8s-manifests'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentity.id}': {} }
  }
  properties: {
    azCliVersion: '2.55.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      { name: 'AKS_NAME', value: aksCluster.name }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
    ]
    scriptContent: '''
      az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing
      kubectl apply -f /manifests/
    '''
  }
}
```

### 2. Service Account for Deployment Scripts

```bicep
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, aksCluster.id, 'AKS-Admin')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8' // Azure Kubernetes Service Cluster Admin
    )
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### 3. AKS Takes Time

- Cluster creation: 8-15 minutes
- Node pool scaling: 5-10 minutes
- Always set appropriate timeouts in deployment scripts

## azd Integration

For AKS with azd, use hooks to deploy Kubernetes resources:

```yaml
# azure.yaml
hooks:
  postprovision:
    posix:
      shell: sh
      run: |
        az aks get-credentials -g $AZURE_RESOURCE_GROUP -n $AKS_CLUSTER_NAME --overwrite-existing
        kubectl apply -f ./kubernetes/
```

## Best Practices

1. **Use System-Assigned Identity** for AKS cluster
2. **Enable RBAC** always
3. **Separate system and user node pools** for production
4. **Use Azure Linux (CBL-Mariner)** for better security
5. **Configure resource requests/limits** for all pods
6. **Use Kubernetes secrets** or Azure Key Vault for sensitive data
