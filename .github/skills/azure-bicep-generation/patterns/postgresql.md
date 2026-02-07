# PostgreSQL Pattern

Azure Database for PostgreSQL Flexible Server configuration.

## Resource Definition

```bicep
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'           // Burstable, cost-optimized
    tier: 'Burstable'
  }
  properties: {
    version: '16'                   // PostgreSQL version
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32             // Minimum recommended
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'              // Enable for production
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'       // Required for most OSS apps
    }
  }
}
```

## Firewall Rules

Allow Azure services to connect:

```bicep
resource postgresFirewallAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'       // Azure services magic IP
    endIpAddress: '0.0.0.0'
  }
}
```

## Database Creation

```bicep
resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgresServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}
```

## SKU Options

| SKU | vCores | Memory | Use Case | Monthly Cost |
|-----|--------|--------|----------|--------------|
| B_Standard_B1ms | 1 | 2 GB | Dev/Test | ~$15 |
| B_Standard_B2s | 2 | 4 GB | Small workloads | ~$30 |
| GP_Standard_D2ds_v4 | 2 | 8 GB | Production | ~$100 |
| GP_Standard_D4ds_v4 | 4 | 16 GB | High traffic | ~$200 |

## SSL Configuration (CRITICAL)

Azure PostgreSQL **requires** SSL. Applications must be configured accordingly.

### Required Environment Variables

```bicep
env: [
  { name: 'DB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
  { name: 'DB_SSL_ENABLED', value: 'true' }
  { name: 'DB_SSL_REJECT_UNAUTHORIZED', value: 'false' }  // Azure certs
  { name: 'DB_CONNECTION_TIMEOUT', value: '60000' }       // 60 seconds
]
```

### Why `SSL_REJECT_UNAUTHORIZED=false`?

Azure PostgreSQL uses a certificate chain that many applications don't trust by default. This setting is safe for Azure PostgreSQL because:
- Connection is still encrypted
- Azure manages the certificates
- Only applies to Azure's trusted infrastructure

## Connection String Pattern

Always use the FQDN from server properties:

```bicep
// ✅ Correct
{ name: 'DB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }

// ❌ Wrong - don't hardcode pattern
{ name: 'DB_HOST', value: '${serverName}.postgres.database.azure.com' }
```

The FQDN format is: `<server-name>.postgres.database.azure.com`

## High Availability (Production)

```bicep
properties: {
  highAvailability: {
    mode: 'ZoneRedundant'           // or 'SameZone'
    standbyAvailabilityZone: '2'
  }
}
```

## Outputs

```bicep
output POSTGRES_SERVER_NAME string = postgresServer.name
output POSTGRES_FQDN string = postgresServer.properties.fullyQualifiedDomainName
output POSTGRES_DATABASE_NAME string = postgresDatabase.name
```

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection refused | Using internal name | Use FQDN from properties |
| SSL handshake failed | SSL not enabled in app | Set SSL_ENABLED=true |
| Certificate error | App rejects Azure cert | Set SSL_REJECT_UNAUTHORIZED=false |
| Connection timeout | Cold start, slow network | Increase CONNECTION_TIMEOUT to 60000ms |
| Access denied | Missing firewall rule | Add AllowAzureServices rule |
