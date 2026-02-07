# Grafana Environment Variables

## Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_SERVER_HTTP_PORT` | HTTP listen port | 3000 |
| `GF_SERVER_DOMAIN` | Server domain | auto |
| `GF_SERVER_ROOT_URL` | Full public URL | auto |
| `GF_SERVER_SERVE_FROM_SUB_PATH` | Serve from subpath | false |

## Security

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_SECURITY_ADMIN_USER` | Admin username | admin |
| `GF_SECURITY_ADMIN_PASSWORD` | Admin password | admin |
| `GF_SECURITY_SECRET_KEY` | Secret key for signing | - |
| `GF_SECURITY_DISABLE_GRAVATAR` | Disable Gravatar | false |

## Authentication

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_AUTH_ANONYMOUS_ENABLED` | Enable anonymous access | false |
| `GF_AUTH_ANONYMOUS_ORG_NAME` | Anonymous org | Main Org. |
| `GF_AUTH_ANONYMOUS_ORG_ROLE` | Anonymous role | Viewer |
| `GF_AUTH_DISABLE_LOGIN_FORM` | Disable login form | false |

## Database

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_DATABASE_TYPE` | Database type | sqlite3 |
| `GF_DATABASE_HOST` | Database host | - |
| `GF_DATABASE_NAME` | Database name | grafana |
| `GF_DATABASE_USER` | Database user | - |
| `GF_DATABASE_PASSWORD` | Database password | - |
| `GF_DATABASE_SSL_MODE` | SSL mode | disable |

## Logging

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_LOG_MODE` | Log mode | console |
| `GF_LOG_LEVEL` | Log level | info |

## Provisioning

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_PATHS_PROVISIONING` | Provisioning path | /etc/grafana/provisioning |
| `GF_PATHS_DATA` | Data path | /var/lib/grafana |
| `GF_PATHS_LOGS` | Logs path | /var/log/grafana |
| `GF_PATHS_PLUGINS` | Plugins path | /var/lib/grafana/plugins |

## Azure-Specific Recommendations

For Azure Container Apps deployment:

```yaml
env:
  - name: GF_SECURITY_ADMIN_USER
    value: "admin"
  - name: GF_SECURITY_ADMIN_PASSWORD
    secretRef: grafana-admin-password
  - name: GF_SERVER_HTTP_PORT
    value: "3000"
  - name: GF_AUTH_ANONYMOUS_ENABLED
    value: "false"
```

## PostgreSQL Backend (Optional)

For production with persistent storage:

```yaml
env:
  - name: GF_DATABASE_TYPE
    value: "postgres"
  - name: GF_DATABASE_HOST
    value: "your-postgres-server.postgres.database.azure.com"
  - name: GF_DATABASE_NAME
    value: "grafana"
  - name: GF_DATABASE_USER
    value: "grafana"
  - name: GF_DATABASE_PASSWORD
    secretRef: postgres-password
  - name: GF_DATABASE_SSL_MODE
    value: "require"
```
