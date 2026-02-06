# Post-Provision Hook for n8n on Azure (Windows)
# This script automatically configures the WEBHOOK_URL environment variable

$ErrorActionPreference = "Stop"

Write-Host "🔧 Configuring n8n post-deployment setup..." -ForegroundColor Cyan

# Retrieve deployment outputs using azd
$N8N_APP_NAME = azd env get-value N8N_CONTAINER_APP_NAME
$RG_NAME = azd env get-value RESOURCE_GROUP_NAME

# Get the Container App FQDN
Write-Host "📡 Retrieving n8n Container App URL..." -ForegroundColor Cyan
$N8N_FQDN = az containerapp show `
  --name $N8N_APP_NAME `
  --resource-group $RG_NAME `
  --query "properties.configuration.ingress.fqdn" `
  -o tsv

if ([string]::IsNullOrEmpty($N8N_FQDN)) {
  Write-Host "❌ Error: Could not retrieve Container App FQDN" -ForegroundColor Red
  exit 1
}

Write-Host "✅ n8n URL: https://$N8N_FQDN" -ForegroundColor Green

# Update the Container App with WEBHOOK_URL environment variable
Write-Host "🔄 Updating WEBHOOK_URL environment variable..." -ForegroundColor Cyan
az containerapp update `
  --name $N8N_APP_NAME `
  --resource-group $RG_NAME `
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN" `
  --output none

Write-Host "✅ Post-deployment configuration completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "🎉 n8n deployment complete!" -ForegroundColor Green
Write-Host "🌐 Access n8n at: https://$N8N_FQDN" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔑 Login credentials:" -ForegroundColor Yellow
$N8N_USER = azd env get-value N8N_BASIC_AUTH_USER
Write-Host "   Username: $N8N_USER" -ForegroundColor White
Write-Host "   Password: (from your main.parameters.json)" -ForegroundColor White
Write-Host ""
