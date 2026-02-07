$ErrorActionPreference = "Stop"

Write-Host "Running post-deployment configuration..." -ForegroundColor Cyan

# Retrieve azd outputs
$CONTAINER_APP_NAME = azd env get-value GRAFANA_CONTAINER_APP_NAME
$RESOURCE_GROUP_NAME = azd env get-value RESOURCE_GROUP_NAME

# Get Container App FQDN
Write-Host "Retrieving Container App URL..." -ForegroundColor Cyan
$APP_FQDN = az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP_NAME `
  --query "properties.configuration.ingress.fqdn" `
  -o tsv

if ([string]::IsNullOrEmpty($APP_FQDN)) {
  Write-Host "Error: Could not retrieve Container App FQDN" -ForegroundColor Red
  exit 1
}

Write-Host "App URL: https://$APP_FQDN" -ForegroundColor Green

# Update GF_SERVER_ROOT_URL
Write-Host "Updating GF_SERVER_ROOT_URL environment variable..." -ForegroundColor Cyan
az containerapp update `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP_NAME `
  --set-env-vars "GF_SERVER_ROOT_URL=https://$APP_FQDN" `
  --output none

Write-Host "Post-deployment configuration completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Grafana deployment complete!" -ForegroundColor Green
Write-Host "Access your app at: https://$APP_FQDN" -ForegroundColor Cyan
Write-Host "Login: admin / <your GRAFANA_ADMIN_PASSWORD>" -ForegroundColor Cyan
Write-Host ""
