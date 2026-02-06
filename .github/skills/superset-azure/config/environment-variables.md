# Superset Environment Variables for Azure

Complete reference for Apache Superset environment variables when deployed to Azure.

## Critical Configuration

### 1. Database Connection (REQUIRED)

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `SQLALCHEMY_DATABASE_URI` | `postgresql://...` | ✅ | Full PostgreSQL connection string |
| `SUPERSET_SECRET_KEY` | (32+ char string) | ✅ | Flask secret key for session signing |
| `SUPERSET_CONFIG_PATH` | `/app/pythonpath/superset_config.py` | ✅ | Path to config file |
| `PYTHONPATH` | `/psycopg2-lib` | ✅ | Include psycopg2 installation location |

### Connection String Format

```
postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require
```

**Critical for Azure:** Always include `?sslmode=require`

### Example Values

```yaml
env:
  - name: SQLALCHEMY_DATABASE_URI
    valueFrom:
      secretKeyRef:
        name: superset-secrets
        key: database-uri
  - name: SUPERSET_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: superset-secrets
        key: secret-key
  - name: SUPERSET_CONFIG_PATH
    value: "/app/pythonpath/superset_config.py"
  - name: PYTHONPATH
    value: "/psycopg2-lib"
```

## Admin Configuration

| Variable | Value | Required | Description |
|----------|-------|----------|-------------|
| `ADMIN_USERNAME` | `admin` | ✅ | Admin username |
| `ADMIN_PASSWORD` | (secure password) | ✅ | Admin password |
| `ADMIN_EMAIL` | `admin@example.com` | ⚠️ | Admin email |
| `ADMIN_FIRSTNAME` | `Admin` | ⚠️ | Admin first name |
| `ADMIN_LASTNAME` | `User` | ⚠️ | Admin last name |

## Server Configuration

| Variable | Value | Description |
|----------|-------|-------------|
| `SUPERSET_WEBSERVER_PORT` | `8088` | Default Superset port |
| `SUPERSET_LOAD_EXAMPLES` | `false` | Load example dashboards |
| `GUNICORN_WORKERS` | `2` | Number of Gunicorn workers |
| `GUNICORN_TIMEOUT` | `120` | Request timeout in seconds |

## Feature Flags

Set via `superset_config.py`, not environment variables:

```python
FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "ALERT_REPORTS": False,  # Requires Redis
}
```

## Redis (Optional - for Caching/Celery)

| Variable | Value | Description |
|----------|-------|-------------|
| `REDIS_HOST` | Redis FQDN | Redis server hostname |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_PASSWORD` | (optional) | Redis auth password |

## SSL Configuration

For Azure PostgreSQL Flexible Server:

| Setting | Value | Reason |
|---------|-------|--------|
| `sslmode` | `require` | Azure PostgreSQL requires SSL |

Include in connection string:
```
postgresql://user:pass@host:5432/db?sslmode=require
```

## superset_config.py (REQUIRED)

⚠️ **Superset does NOT read environment variables directly for database configuration!**

You MUST create a config file that reads from environment:

```python
import os

# Database configuration (reads from environment)
SQLALCHEMY_DATABASE_URI = os.environ.get(
    'SQLALCHEMY_DATABASE_URI',
    'sqlite:////app/superset_home/superset.db'
)

# Secret key (required)
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'change-me-in-production')

# Security settings
WTF_CSRF_ENABLED = True
WTF_CSRF_EXEMPT_LIST = []
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

# Feature flags
FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}

# Webserver config
WEBSERVER_PORT = 8088
WEBSERVER_TIMEOUT = 120

# Disable example data by default
SUPERSET_LOAD_EXAMPLES = False
```

## Complete Kubernetes Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: superset-secrets
  namespace: superset
type: Opaque
stringData:
  database-uri: "postgresql://superset:YOUR_PASSWORD@your-server.postgres.database.azure.com:5432/superset?sslmode=require"
  secret-key: "your-32-character-or-longer-secret-key"
  admin-password: "your-secure-admin-password"
```

## Secrets Management Best Practices

1. **Never commit secrets to Git**
2. **Use Kubernetes Secrets** or Azure Key Vault
3. **Rotate secrets regularly**
4. **Generate secure random values:**
   ```bash
   # Generate secret key
   openssl rand -base64 32
   
   # Generate password
   openssl rand -base64 16
   ```

## Environment vs Config File

| Setting | Environment Variable | Config File |
|---------|---------------------|-------------|
| Database URI | ✅ (via config) | ✅ Required |
| Secret Key | ✅ (via config) | ✅ Required |
| Feature Flags | ❌ | ✅ Only |
| CSRF Settings | ❌ | ✅ Only |
| Redis Config | ✅ (via config) | ✅ Recommended |

**Key insight:** Superset's config file reads from `os.environ`, so you still set environment variables, but the config file is the bridge that makes them work.
