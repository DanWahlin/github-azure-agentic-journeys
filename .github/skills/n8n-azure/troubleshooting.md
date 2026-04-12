# Troubleshooting n8n Azure Deployment

Common issues and solutions when deploying n8n to Azure.

## Quick Diagnosis Commands

```bash
# Get deployment values
APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)

# Check container logs
az containerapp logs show --name $APP_NAME --resource-group $RG --follow

# Check container status
az containerapp show --name $APP_NAME --resource-group $RG \
  --query "properties.runningStatus"

# List all azd environment values
azd env get-values
```

---

## Issue 1: Container CrashLoopBackOff

**Symptoms:**
- Container restarts repeatedly
- Logs show "Container killed due to health check failure"
- Deployment seems stuck

**Root Cause:** n8n requires 60+ seconds to start. Default health probes kill it first.

**Solution:** Configure health probes with extended timeouts. See `config/health-probes.md`.

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
    initialDelaySeconds: 60    // MUST be 60+
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  }
  {
    type: 'startup'
    httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30       // Allow 5 minutes
  }
]
```

---

## Issue 2: Database Connection Refused

**Symptoms:**
- n8n logs show "ECONNREFUSED" or "Connection refused"
- Container starts but crashes on database connection

**Root Cause:** Using internal hostname instead of FQDN, or missing SSL configuration.

**Solution:**

1. **Always use PostgreSQL FQDN:**
   ```bicep
   { name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
   ```

2. **Enable SSL (required for Azure PostgreSQL):**
   ```bicep
   { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
   { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
   ```

3. **Increase connection timeout:**
   ```bicep
   { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
   ```

---

## Issue 3: Resource Provider 409 Conflicts

**Symptoms:**
- `azd up` fails with 409 Conflict error
- Error mentions resource provider not registered

**Root Cause:** Azure resource providers not registered for subscription.

**Solution:** Register providers before deployment:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# Wait for registration (check status)
az provider show --namespace Microsoft.App --query "registrationState"
```

---

## Issue 4: newGuid() Error in Bicep

**Symptoms:**
- Bicep compilation error mentioning `newGuid()`
- Error: "Function 'newGuid' is not valid at this location"

**Root Cause:** `newGuid()` can only be used as a parameter default value.

**Wrong:**
```bicep
var encryptionKey = newGuid()  // ❌ ERROR!
```

**Correct:**
```bicep
@secure()
param n8nEncryptionKey string = newGuid()  // ✅ Works
```

---

## Issue 5: Post-Provision Hook Fails

**Symptoms:**
- `azd up` completes but hook fails
- Error: "Could not retrieve Container App FQDN"

**Root Cause:** Output names don't match what the hook expects, or script not executable.

**Solution:**

1. **Verify Bicep outputs match hook expectations:**
   ```bicep
   output N8N_CONTAINER_APP_NAME string = n8nApp.name
   output RESOURCE_GROUP_NAME string = resourceGroup().name
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x infra/hooks/postprovision.sh
   ```

---

## Issue 6: SSL Certificate Errors

**Symptoms:**
- n8n logs show SSL/TLS handshake errors
- "unable to verify the first certificate"

**Root Cause:** Azure PostgreSQL uses a certificate chain that n8n doesn't trust by default.

**Solution:**
```bicep
{ name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
```

This is safe for Azure PostgreSQL (Azure manages the certificates, connection is still encrypted).

---

## Issue 7: WEBHOOK_URL Not Set

**Symptoms:**
- Webhooks don't work
- n8n shows incorrect URLs for webhooks

**Root Cause:** WEBHOOK_URL wasn't configured after deployment.

**Solution:** Should be handled by post-provision hooks. Manual fix:

```bash
N8N_FQDN=$(az containerapp show --name $APP_NAME --resource-group $RG \
  --query "properties.configuration.ingress.fqdn" -o tsv)
az containerapp update --name $APP_NAME --resource-group $RG \
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN"
```

---

## Issue 8: Deployment Takes Too Long

**Symptoms:**
- `azd up` runs for 15+ minutes
- Seems stuck on Container App deployment

**Root Cause:** This is normal! Container Apps deployment includes image pull and health checks.

**Expected Timeline:**
| Stage | Time |
|-------|------|
| PostgreSQL provisioning | 3-5 min |
| Container Apps Environment | 2-3 min |
| n8n Container App (image + startup) | 5-8 min |
| Post-provision hooks | 1-2 min |
| **Total** | **~15-20 min** |

---

## Key Learnings Summary

1. **Health probes are critical** - n8n needs 60s initial delay and 5min startup allowance
2. **Always use PostgreSQL FQDN** - internal names don't work
3. **SSL is mandatory** - Azure PostgreSQL requires SSL with relaxed certificate validation
4. **`newGuid()` is position-sensitive** - only works as parameter default
5. **Register providers first** - prevents 409 conflicts
6. **Post-provision hooks automate WEBHOOK_URL** - eliminates manual steps
7. **15-20 minute deployment is normal** - don't panic
8. **Enable publicNetworkAccess explicitly** - AVM defaults to disabled
9. **Pin passwords in azd env** - `newGuid()` regenerates on redeploy, causing auth failures
10. **Burstable SKU doesn't support HA** - set `highAvailability: 'Disabled'`

---

## Issue 9: PostgreSQL Connection Timeout (publicNetworkAccess)

**Symptoms:**
- n8n logs show "Could not establish database connection within the configured timeout of 60,000 ms"
- Container exits with code 1
- PostgreSQL is provisioned but unreachable

**Root Cause:** The AVM PostgreSQL Flexible Server module defaults `publicNetworkAccess` to disabled. When disabled, **all firewall rules are silently ignored** — even `AllowAllAzureServices`.

**Solution:** Explicitly enable public network access in Bicep:

```bicep
module postgresServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2' = {
  params: {
    // ...
    publicNetworkAccess: 'Enabled'  // CRITICAL — default is disabled
    firewallRules: [
      { name: 'AllowAllAzureServices', startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
    ]
  }
}
```

**Manual fix for existing deployment:**
```bash
az postgres flexible-server update --resource-group $RG --name $PG_NAME --public-access Enabled
az postgres flexible-server firewall-rule create --resource-group $RG --name $PG_NAME \
  --rule-name AllowAzure --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
```

---

## Issue 10: Authentication Failed After Redeploy

**Symptoms:**
- n8n logs show "authentication failed for user"
- First deploy worked, redeploy fails
- PostgreSQL is reachable but rejects credentials

**Root Cause:** `newGuid()` generates a **new password on every deployment**. PostgreSQL was created with the first password but the second deploy sends a different one.

**Solution:** Pin passwords to azd environment variables:

```bash
# Set once — persists across deploys
azd env set POSTGRES_PASSWORD "$(openssl rand -hex 16)"
```

Reference in `main.parameters.json`:
```json
{ "postgresPassword": { "value": "${POSTGRES_PASSWORD}" } }
```

The Bicep param keeps `newGuid()` as a fallback default but the pinned value takes precedence:
```bicep
@secure()
param postgresPassword string = newGuid()  // Overridden by parameter file
```

---

## Issue 11: HA Not Supported for Burstable SKU

**Symptoms:**
- `azd up` fails with "HANotSupportedForBurstableSkuWithMoreInfo"

**Root Cause:** Burstable tier doesn't support high availability. The AVM module may default to enabling it.

**Solution:**
```bicep
highAvailability: 'Disabled'  // Required for Burstable tier
```

---

## Issue 12: Password Auth Disabled by Default (Entra-Only)

**Symptoms:**
- n8n logs show "authentication failed for user n8nadmin"
- Resetting password via `az postgres flexible-server update --admin-password` has no effect
- `az postgres flexible-server show` reveals `"passwordAuth": "Disabled"`

**Root Cause:** AVM PostgreSQL Flexible Server module (v0.15.2) defaults `passwordAuth` to `Disabled`, enabling only Microsoft Entra ID authentication. n8n uses password-based auth and cannot use Entra ID.

**Solution:** Explicitly enable password auth in Bicep:
```bicep
authConfig: {
  passwordAuth: 'Enabled'
  activeDirectoryAuth: 'Disabled'
}
```

**This is the #1 gotcha with the AVM PostgreSQL module.** Without it, every password-based application (n8n, Grafana with PostgreSQL, Superset) will fail to connect.
