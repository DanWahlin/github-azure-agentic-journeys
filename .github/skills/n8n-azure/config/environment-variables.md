# n8n Environment Variables for Azure

Complete reference for n8n environment variables when deployed to Azure.

## Database Configuration

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `DB_TYPE` | `postgresdb` | ✅ | Database type |
| `DB_POSTGRESDB_HOST` | `<server>.postgres.database.azure.com` | ✅ | PostgreSQL FQDN |
| `DB_POSTGRESDB_PORT` | `5432` | ✅ | PostgreSQL port |
| `DB_POSTGRESDB_DATABASE` | `n8n` | ✅ | Database name |
| `DB_POSTGRESDB_USER` | `n8n` | ✅ | Database user |
| `DB_POSTGRESDB_PASSWORD` | (secret) | ✅ | Database password |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` | ✅ | **Required for Azure** |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `false` | ✅ | Azure cert compatibility |
| `DB_POSTGRESDB_CONNECTION_TIMEOUT` | `60000` | ⚠️ | 60 seconds for cold starts |

### SSL Settings Explained

Azure PostgreSQL **requires** SSL connections. The configuration:

```env
DB_POSTGRESDB_SSL_ENABLED=true
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
```

**Why `SSL_REJECT_UNAUTHORIZED=false`?**
- Azure uses a certificate chain not trusted by default in n8n
- Connection is still encrypted and secure
- This is safe because Azure manages the certificates
- Without this, you'll see "unable to verify the first certificate" errors

### FQDN Requirement

**Always use the PostgreSQL FQDN:**
```bicep
{ name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
```

**Never use:**
- Internal hostnames
- Manually constructed domain names
- IP addresses

## n8n Core Settings

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `N8N_PORT` | `5678` | ✅ | HTTP port (default) |
| `N8N_PROTOCOL` | `https` | ✅ | Protocol for generated URLs |
| `N8N_ENCRYPTION_KEY` | (auto-generated) | ✅ | Data encryption key |

### Encryption Key

The encryption key protects stored credentials and sensitive workflow data.

**Generation in Bicep:**
```bicep
@secure()
@description('n8n encryption key (auto-generated if not provided)')
param n8nEncryptionKey string = newGuid()
```

**Important:** 
- Generated once during first deployment
- If you redeploy with a new key, existing encrypted data becomes unreadable
- Store this key securely after deployment

## Authentication Settings

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `N8N_BASIC_AUTH_ACTIVE` | `true` | ✅ | Enable basic auth |
| `N8N_BASIC_AUTH_USER` | `admin` | ✅ | Auth username |
| `N8N_BASIC_AUTH_PASSWORD` | (secret) | ✅ | Auth password |

## Webhook Configuration

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `WEBHOOK_URL` | `https://<fqdn>` | ⚠️ | Webhook base URL |

### WEBHOOK_URL Circular Dependency

WEBHOOK_URL cannot be set during initial deployment because:
1. It depends on the Container App FQDN
2. FQDN isn't known until after the Container App is created

**Solution:** Post-provision hook automatically configures this:
```bash
N8N_FQDN=$(az containerapp show --name $APP --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" -o tsv)
az containerapp update --name $APP --resource-group $RG \
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN"
```

## Secrets Management

Store sensitive values as Container App secrets:

```bicep
configuration: {
  secrets: [
    { name: 'postgres-password', value: postgresPassword }
    { name: 'n8n-encryption-key', value: n8nEncryptionKey }
    { name: 'n8n-auth-password', value: n8nBasicAuthPassword }
  ]
}
```

Reference via `secretRef`:
```bicep
env: [
  { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
  { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
  { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
]
```

## Complete Environment Block (Bicep)

```bicep
env: [
  // Database
  { name: 'DB_TYPE', value: 'postgresdb' }
  { name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
  { name: 'DB_POSTGRESDB_PORT', value: '5432' }
  { name: 'DB_POSTGRESDB_DATABASE', value: postgresDb }
  { name: 'DB_POSTGRESDB_USER', value: postgresUser }
  { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
  { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
  { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
  { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
  
  // n8n Core
  { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
  { name: 'N8N_PORT', value: '5678' }
  { name: 'N8N_PROTOCOL', value: 'https' }
  
  // Authentication
  { name: 'N8N_BASIC_AUTH_ACTIVE', value: string(n8nBasicAuthActive) }
  { name: 'N8N_BASIC_AUTH_USER', value: n8nBasicAuthUser }
  { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
]
```
