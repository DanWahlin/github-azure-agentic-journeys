$ErrorActionPreference = "Stop"

Write-Host "Running post-provision hook: configuring GF_SERVER_ROOT_URL..."

# Get resource names from azd outputs
$APP_NAME = azd env get-value GRAFANA_CONTAINER_APP_NAME
$RG_NAME = azd env get-value RESOURCE_GROUP_NAME

# Get the Container App FQDN
$GRAFANA_FQDN = az containerapp show `
  --name $APP_NAME `
  --resource-group $RG_NAME `
  --query "properties.configuration.ingress.fqdn" -o tsv

if ([string]::IsNullOrEmpty($GRAFANA_FQDN)) {
  Write-Host "Error: Could not retrieve Container App FQDN"
  exit 1
}

Write-Host "Setting GF_SERVER_ROOT_URL to https://$GRAFANA_FQDN"

# Update the Container App with the root URL
az containerapp update `
  --name $APP_NAME `
  --resource-group $RG_NAME `
  --set-env-vars "GF_SERVER_ROOT_URL=https://$GRAFANA_FQDN" `
  --output none

Write-Host "Post-provision configuration completed."
Write-Host "Access Grafana at: https://$GRAFANA_FQDN"
