# n8n Configuration Reference

## Official Documentation

- n8n Docker Installation: https://docs.n8n.io/hosting/installation/docker/

## Environment Variables

### Database Configuration

| Variable | Value | Description |
|----------|-------|-------------|
| `DB_TYPE` | `postgresdb` | Database type (required) |
| `DB_POSTGRESDB_HOST` | FQDN | PostgreSQL server FQDN (NOT internal name) |
| `DB_POSTGRESDB_PORT` | `5432` | PostgreSQL port |
| `DB_POSTGRESDB_DATABASE` | `n8n` | Database name |
| `DB_POSTGRESDB_USER` | `n8n` | Database username |
| `DB_POSTGRESDB_PASSWORD` | secret | Database password |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` | Enable SSL (required for Azure) |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `false` | Azure certificate compatibility |
| `DB_POSTGRESDB_CONNECTION_TIMEOUT` | `60000` | 60 seconds for cold starts |

### SSL Requirements for Azure PostgreSQL

**CRITICAL**: Azure PostgreSQL requires SSL connections. You MUST set:

```env
DB_POSTGRESDB_SSL_ENABLED=true
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
```

The `SSL_REJECT_UNAUTHORIZED=false` setting is needed because Azure uses a certificate chain that n8n doesn't trust by default. This is safe for Azure PostgreSQL connections.

### Connection String Pattern

For Azure PostgreSQL, the host should always be the FQDN:

```
<server-name>.postgres.database.azure.com
```

Never use internal names or short hostnames.

### n8n Core Settings

| Variable | Value | Description |
|----------|-------|-------------|
| `N8N_PORT` | `5678` | HTTP port (default) |
| `N8N_PROTOCOL` | `https` | Protocol for generated URLs |
| `N8N_ENCRYPTION_KEY` | secret | Data encryption key (auto-generated) |

### Authentication Settings

| Variable | Value | Description |
|----------|-------|-------------|
| `N8N_BASIC_AUTH_ACTIVE` | `true` | Enable basic auth |
| `N8N_BASIC_AUTH_USER` | `admin` | Auth username |
| `N8N_BASIC_AUTH_PASSWORD` | secret | Auth password |

### Webhook Configuration

| Variable | Value | Description |
|----------|-------|-------------|
| `WEBHOOK_URL` | `https://<fqdn>` | Webhook base URL |

**Note**: WEBHOOK_URL cannot be set during initial deployment due to circular dependency (URL depends on Container App FQDN, which isn't known until after creation). The post-provision hook automatically configures this.

## Container Resources

Recommended settings for development:

| Resource | Value | Notes |
|----------|-------|-------|
| CPU | 1.0 cores | Minimum for responsive UI |
| Memory | 2Gi | n8n recommended minimum |
| Min Replicas | 0 | Scale-to-zero for cost savings |
| Max Replicas | 3 | Handle traffic spikes |

## Secrets Management

Store sensitive values as Container App secrets:

```bicep
secrets: [
  { name: 'postgres-password', value: postgresPassword }
  { name: 'n8n-encryption-key', value: n8nEncryptionKey }
  { name: 'n8n-auth-password', value: n8nBasicAuthPassword }
]
```

Reference in environment variables:

```bicep
{ name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
```

## Encryption Key

The `N8N_ENCRYPTION_KEY` is used to encrypt credentials and sensitive workflow data.

**Generation**: Use `newGuid()` as parameter default in Bicep:

```bicep
@secure()
param n8nEncryptionKey string = newGuid()
```

**Important**: This key is generated once and stored. If you redeploy with a new key, existing encrypted data becomes unreadable.

## Port Configuration

n8n default port is 5678. Configure ingress to match:

```bicep
ingress: {
  external: true
  targetPort: 5678
  transport: 'auto'
  allowInsecure: false
}
```

## Complete Environment Block

```bicep
env: [
  { name: 'DB_TYPE', value: 'postgresdb' }
  { name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
  { name: 'DB_POSTGRESDB_PORT', value: '5432' }
  { name: 'DB_POSTGRESDB_DATABASE', value: postgresDb }
  { name: 'DB_POSTGRESDB_USER', value: postgresUser }
  { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'postgres-password' }
  { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
  { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
  { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
  { name: 'N8N_ENCRYPTION_KEY', secretRef: 'n8n-encryption-key' }
  { name: 'N8N_BASIC_AUTH_ACTIVE', value: string(n8nBasicAuthActive) }
  { name: 'N8N_BASIC_AUTH_USER', value: n8nBasicAuthUser }
  { name: 'N8N_BASIC_AUTH_PASSWORD', secretRef: 'n8n-auth-password' }
  { name: 'N8N_PORT', value: '5678' }
  { name: 'N8N_PROTOCOL', value: 'https' }
]
```
