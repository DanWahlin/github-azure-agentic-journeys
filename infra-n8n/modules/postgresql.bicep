@description('PostgreSQL server name')
param serverName string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

@description('Admin username')
param adminUser string

@secure()
@description('Admin password')
param adminPassword string

@description('Database name')
param databaseName string

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
    }
  }
}

// Firewall rule: Allow Azure services
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SSL configuration: Require SSL
resource sslConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'require_secure_transport'
  dependsOn: [firewallRule]
  properties: {
    value: 'ON'
    source: 'user-override'
  }
}

// Database
resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgresServer
  name: databaseName
  dependsOn: [sslConfig]
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output fqdn string = postgresServer.properties.fullyQualifiedDomainName
output serverName string = postgresServer.name
output databaseName string = database.name
