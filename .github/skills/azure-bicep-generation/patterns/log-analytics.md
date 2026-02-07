# Log Analytics Pattern

Azure Log Analytics Workspace for monitoring and diagnostics.

## Resource Definition

```bicep
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'             // Pay-per-GB pricing
    }
    retentionInDays: 30             // 30 days minimum, up to 730
  }
}
```

## Connecting to Container Apps Environment

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

## SKU Options

| SKU | Description | Use Case |
|-----|-------------|----------|
| `PerGB2018` | Pay per GB ingested | Most scenarios |
| `CapacityReservation` | Reserved capacity discount | High volume (>100 GB/day) |
| `Free` | Limited free tier | Testing only (500 MB/day limit) |

## Retention Settings

| Setting | Range | Default | Notes |
|---------|-------|---------|-------|
| `retentionInDays` | 30-730 | 30 | Longer = more storage cost |

### Cost-Optimized Settings

```bicep
properties: {
  sku: { name: 'PerGB2018' }
  retentionInDays: 30               // Minimum for cost savings
  features: {
    enableDataExport: false         // Disable unless needed
    disableLocalAuth: false
  }
}
```

### Production Settings

```bicep
properties: {
  sku: { name: 'PerGB2018' }
  retentionInDays: 90               // 3 months for compliance
  features: {
    enableDataExport: true          // For long-term storage
  }
}
```

## Outputs

```bicep
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.id
output LOG_ANALYTICS_CUSTOMER_ID string = logAnalytics.properties.customerId
// Note: Don't output sharedKey - it's sensitive
```

## Querying Logs

After deployment, query Container App logs in Azure Portal:

```kusto
// Container App logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "my-app"
| order by TimeGenerated desc
| take 100

// System events
ContainerAppSystemLogs_CL
| where Type_s == "Error"
| order by TimeGenerated desc
```

## Cost Estimation

| Data Volume | Approximate Monthly Cost |
|-------------|-------------------------|
| 1 GB/day | ~$3 |
| 5 GB/day | ~$15 |
| 10 GB/day | ~$30 |

Tips to reduce log volume:
- Filter verbose logs at application level
- Use sampling for high-frequency events
- Set appropriate log levels (INFO vs DEBUG)
