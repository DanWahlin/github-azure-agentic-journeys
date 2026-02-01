# Troubleshooting n8n Azure Deployment

## Common Issues and Solutions

### 1. Container CrashLoopBackOff / Health Check Failures

**Symptoms:**
- Container restarts repeatedly
- Logs show "Container killed due to health check failure"
- Deployment seems to hang or fail

**Root Cause:** n8n requires 60+ seconds to start. Default health probes kill the container before it's ready.

**Solution:** Configure health probes with proper timeouts:

```bicep
probes: [
  {
    type: 'liveness'
    httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
    initialDelaySeconds: 60    // CRITICAL: Wait 60s before first check
    periodSeconds: 30
    timeoutSeconds: 10
    failureThreshold: 3
  }
  {
    type: 'startup'
    httpGet: { port: 5678, path: '/', scheme: 'HTTP' }
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30       // CRITICAL: Allow 5 minutes total startup
  }
]
```

---

### 2. Database Connection Refused

**Symptoms:**
- n8n logs show "ECONNREFUSED" or "Connection refused"
- Container starts but crashes on database connection

**Root Cause:** Using internal hostname instead of FQDN, or missing SSL configuration.

**Solution:**

1. Always use PostgreSQL FQDN:
   ```bicep
   { name: 'DB_POSTGRESDB_HOST', value: postgresServer.properties.fullyQualifiedDomainName }
   ```

2. Enable SSL (required for Azure PostgreSQL):
   ```bicep
   { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
   { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
   ```

3. Increase connection timeout:
   ```bicep
   { name: 'DB_POSTGRESDB_CONNECTION_TIMEOUT', value: '60000' }
   ```

---

### 3. Resource Provider 409 Conflicts

**Symptoms:**
- `azd up` fails with 409 Conflict error
- Error mentions resource provider not registered

**Root Cause:** Azure resource providers not registered for subscription.

**Solution:** Register providers before deployment:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.OperationalInsights

# Verify registration (wait until "Registered")
az provider show --namespace Microsoft.App --query "registrationState"
```

---

### 4. newGuid() Error in Bicep

**Symptoms:**
- Bicep compilation error mentioning `newGuid()`
- Error: "Function 'newGuid' is not valid at this location"

**Root Cause:** `newGuid()` can only be used as a parameter default value.

**Wrong:**
```bicep
var encryptionKey = newGuid()  // ERROR!
```

**Correct:**
```bicep
@secure()
param n8nEncryptionKey string = newGuid()  // This works
```

---

### 5. Post-Provision Hook Fails

**Symptoms:**
- `azd up` completes but hook fails
- Error: "Could not retrieve Container App FQDN"

**Root Cause:** Output names don't match what the hook expects.

**Solution:** Ensure Bicep outputs match hook variable names:

```bicep
output N8N_CONTAINER_APP_NAME string = n8nApp.name
output RESOURCE_GROUP_NAME string = resourceGroup().name
```

Also ensure scripts are executable:
```bash
chmod +x infra/hooks/postprovision.sh
```

---

### 6. SSL Certificate Errors

**Symptoms:**
- n8n logs show SSL/TLS handshake errors
- "unable to verify the first certificate"

**Root Cause:** Azure PostgreSQL uses a certificate chain that n8n doesn't trust by default.

**Solution:** Set SSL to not reject unauthorized certificates:
```bicep
{ name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
```

This is safe for Azure PostgreSQL connections (Azure manages the certificates).

---

### 7. WEBHOOK_URL Not Set

**Symptoms:**
- Webhooks don't work
- n8n shows incorrect URLs for webhooks

**Root Cause:** WEBHOOK_URL wasn't configured after deployment.

**Solution:** This should be handled by post-provision hooks. If not:

```bash
# Get the Container App FQDN
N8N_FQDN=$(az containerapp show --name <app-name> --resource-group <rg> --query "properties.configuration.ingress.fqdn" -o tsv)

# Update the environment variable
az containerapp update --name <app-name> --resource-group <rg> --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN"
```

---

### 8. Deployment Takes Too Long

**Symptoms:**
- `azd up` runs for 15+ minutes
- Seems stuck on Container App deployment

**Root Cause:** Container Apps deployment includes pulling the Docker image and running health checks.

**Expected Timeline:**
- PostgreSQL: 3-5 minutes
- Container Apps Environment: 2-3 minutes
- n8n Container App: 5-8 minutes (image pull + startup probes)
- Post-provision hooks: 1-2 minutes

**Total: ~15-20 minutes** is normal for first deployment.

---

## Debugging Commands

### Check Container Logs
```bash
az containerapp logs show --name <app-name> --resource-group <rg> --follow
```

### Check Container Status
```bash
az containerapp show --name <app-name> --resource-group <rg> --query "properties.runningStatus"
```

### Check PostgreSQL Connectivity
```bash
az postgres flexible-server show --name <server-name> --resource-group <rg>
```

### Verify azd Environment Values
```bash
azd env get-values
```

### Manual WEBHOOK_URL Update
```bash
N8N_APP=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)
FQDN=$(az containerapp show --name $N8N_APP --resource-group $RG --query "properties.configuration.ingress.fqdn" -o tsv)
az containerapp update --name $N8N_APP --resource-group $RG --set-env-vars "WEBHOOK_URL=https://$FQDN"
```

---

## Key Learnings Summary

1. **Health probes are critical** - n8n needs 60s initial delay and 5min startup allowance
2. **Always use PostgreSQL FQDN** - internal names don't work
3. **SSL is mandatory** - Azure PostgreSQL requires SSL with relaxed certificate validation
4. **newGuid() is position-sensitive** - only works as parameter default
5. **Register providers first** - prevents 409 conflicts
6. **Post-provision hooks automate WEBHOOK_URL** - eliminates manual steps
7. **15-20 minute deployment is normal** - don't panic
