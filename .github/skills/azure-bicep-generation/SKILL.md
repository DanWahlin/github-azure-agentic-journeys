---
name: azure-bicep-generation
description: Generate Azure Bicep infrastructure code. Use when creating Container Apps, PostgreSQL, Log Analytics, or other Azure resources.
---

# Azure Bicep Generation Skill

Generate production-ready Bicep code for Azure resources following Microsoft best practices.

## When to Use

- Creating new Azure infrastructure with Bicep
- Adding resources to existing Bicep deployments
- Understanding Bicep patterns and conventions

## Key Patterns

Load pattern files for implementation details:

| Task | Pattern File |
|------|--------------|
| Container Apps deployment | `patterns/container-apps.md` |
| PostgreSQL Flexible Server | `patterns/postgresql.md` |
| Log Analytics & monitoring | `patterns/log-analytics.md` |
| Resource naming conventions | `patterns/naming-conventions.md` |

## Critical Rules

### 1. `newGuid()` Placement (CRITICAL)

**Only valid as parameter default:**
```bicep
@secure()
param encryptionKey string = newGuid()  // ✅ Works
```

**Never in variables or expressions:**
```bicep
var key = newGuid()  // ❌ ERROR!
```

### 2. Always Use FQDN for Database Connections

```bicep
// ✅ Correct - use FQDN property
{ name: 'DB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }

// ❌ Wrong - don't construct manually
{ name: 'DB_HOST', value: '${postgresServer.name}.postgres.database.azure.com' }
```

### 3. Secrets Reference Pattern

```bicep
// Define secrets in configuration
secrets: [
  { name: 'db-password', value: postgresPassword }
]

// Reference via secretRef, not value
env: [
  { name: 'DB_PASSWORD', secretRef: 'db-password' }  // ✅
  { name: 'DB_PASSWORD', value: postgresPassword }   // ❌ Exposes in logs
]
```

### 4. Output Naming Convention

Use SCREAMING_SNAKE_CASE for outputs (azd convention):
```bicep
output RESOURCE_GROUP_NAME string = resourceGroup().name
output CONTAINER_APP_NAME string = app.name
output APP_URL string = 'https://${app.properties.configuration.ingress.fqdn}'
```

## Quick Reference

### Parameter Decorators
```bicep
@description('Description text')
@secure()                          // Sensitive values
@allowed(['dev', 'prod'])          // Restrict values
@minLength(3) @maxLength(24)       // Length constraints
param myParam string
```

### Resource Dependencies
```bicep
// Implicit (property reference)
resource app '...' = {
  properties: {
    databaseId: database.id  // Creates implicit dependency
  }
}

// Explicit
resource app '...' = {
  dependsOn: [database]  // Only when no property reference
}
```

### Conditional Resources
```bicep
param deployMonitoring bool = true

resource logs '...' = if (deployMonitoring) {
  name: 'my-logs'
  // ...
}
```

## Common API Versions

| Resource Type | API Version |
|---------------|-------------|
| Container Apps | `2023-11-02-preview` |
| Container Apps Env | `2023-11-02-preview` |
| PostgreSQL Flexible | `2023-12-01-preview` |
| Log Analytics | `2023-09-01` |
| Managed Identity | `2023-01-31` |
