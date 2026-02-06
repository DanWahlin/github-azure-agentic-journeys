# Grafana Azure Troubleshooting

## Common Issues

### Container Won't Start

**Symptoms:** Container app shows "Failed" or keeps restarting

**Solutions:**
1. Check logs:
   ```bash
   az containerapp logs show \
     --name <container-app-name> \
     --resource-group <resource-group> \
     --follow
   ```
2. Verify health probes aren't too aggressive
3. Increase startup probe failure threshold

### 502 Bad Gateway

**Symptoms:** HTTPS URL returns 502

**Causes:**
- Container still starting (scale from zero)
- Health probe failures
- Resource limits hit

**Solutions:**
1. Wait 30-60 seconds for cold start
2. Check container logs for errors
3. Increase CPU/memory if needed

### Login Fails

**Symptoms:** Can't login with admin credentials

**Causes:**
- Password not set correctly
- Special characters in password

**Solutions:**
1. Verify password was passed correctly:
   ```bash
   az containerapp show --name <app> -g <rg> \
     --query "properties.template.containers[0].env"
   ```
2. Use alphanumeric password without special shell characters
3. Redeploy with new password

### Dashboards Lost After Restart

**Symptoms:** Dashboards disappear when container restarts

**Cause:** SQLite database stored in ephemeral container storage

**Solutions:**
1. Add Azure Files volume mount for `/var/lib/grafana`
2. Use PostgreSQL database backend
3. Export dashboards as JSON and use provisioning

### Slow Cold Start

**Symptoms:** First request after idle takes 30+ seconds

**Cause:** Scale to zero, container needs to start

**Solutions:**
1. Set `minReplicas: 1` to keep one instance running
2. Accept cold start for cost savings
3. Use warmup requests via Azure Front Door

## Health Check Failures

### Startup Probe Timeout

**Default config allows 5 minutes for startup (30 failures × 10s interval)**

If still failing:
1. Increase `failureThreshold` to 60
2. Check if image pull is slow
3. Verify network connectivity

### Readiness Probe Failing

Check `/api/health` response:
```bash
curl -v https://<fqdn>/api/health
```

Should return:
```json
{"database": "ok", "version": "x.x.x", "commit": "..."}
```

## Resource Limits

### Out of Memory

**Symptoms:** Container killed with OOMKilled

**Solution:** Increase memory allocation in Bicep:
```bicep
resources: {
  cpu: json('0.5')
  memory: '2Gi'  // Increase from 1Gi
}
```

## Networking

### Can't Connect to Data Sources

**Symptoms:** Grafana can't reach Prometheus/InfluxDB

**Solutions:**
1. Ensure data sources are in same VNet or publicly accessible
2. For Azure services, use private endpoints
3. Check NSG rules

## Azure CLI Commands

```bash
# List container apps
az containerapp list -g <resource-group> -o table

# Get logs
az containerapp logs show --name <app> -g <rg> --tail 100

# Check revisions
az containerapp revision list --name <app> -g <rg> -o table

# Force restart
az containerapp revision restart --name <app> -g <rg> --revision <revision>

# Check environment
az containerapp env show --name <env> -g <rg>
```

---

## Key Learnings Summary

1. **Grafana starts fast** - 15-30 seconds typical, unlike n8n's 60+ seconds
2. **Use /api/health for probes** - Returns JSON with database status
3. **SQLite is ephemeral** - Dashboards lost on restart without persistent storage
4. **Scale-to-zero cold start** - First request takes 30-60s, this is normal
5. **Avoid shell special characters in passwords** - Use alphanumeric for CLI deployments
6. **Azure CLI over azd for Grafana** - azd has `--no-prompt` bugs with secure params
7. **Resource group deletion is slow** - Container Apps environments take 3-5 minutes
8. **PostgreSQL is optional** - SQLite works for dev; use PostgreSQL for production
