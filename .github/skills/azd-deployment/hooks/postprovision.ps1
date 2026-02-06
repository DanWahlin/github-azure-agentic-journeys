# Post-Provision Hook Template (Windows PowerShell)
# Copy and customize for your application
#
# Usage: Copy-Item postprovision.ps1 /path/to/infra/hooks/

$ErrorActionPreference = "Stop"

Write-Host "🔧 Running post-deployment configuration..." -ForegroundColor Cyan

# =============================================================================
# Retrieve azd outputs
# =============================================================================
# Replace with your actual output names from main.bicep

$CONTAINER_APP_NAME = azd env get-value CONTAINER_APP_NAME
$RESOURCE_GROUP_NAME = azd env get-value RESOURCE_GROUP_NAME

# =============================================================================
# Get Container App FQDN
# =============================================================================

Write-Host "📡 Retrieving Container App URL..." -ForegroundColor Cyan
$APP_FQDN = az containerapp show `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP_NAME `
  --query "properties.configuration.ingress.fqdn" `
  -o tsv

if ([string]::IsNullOrEmpty($APP_FQDN)) {
  Write-Host "❌ Error: Could not retrieve Container App FQDN" -ForegroundColor Red
  exit 1
}

Write-Host "✅ App URL: https://$APP_FQDN" -ForegroundColor Green

# =============================================================================
# Update environment variables (customize as needed)
# =============================================================================
# Common use case: Configure WEBHOOK_URL for applications that need their
# public URL but can't know it during initial deployment

Write-Host "🔄 Updating environment variables..." -ForegroundColor Cyan
az containerapp update `
  --name $CONTAINER_APP_NAME `
  --resource-group $RESOURCE_GROUP_NAME `
  --set-env-vars "WEBHOOK_URL=https://$APP_FQDN" `
  --output none

# =============================================================================
# Success message
# =============================================================================

Write-Host "✅ Post-deployment configuration completed!" -ForegroundColor Green
Write-Host ""
Write-Host "🎉 Deployment complete!" -ForegroundColor Green
Write-Host "🌐 Access your app at: https://$APP_FQDN" -ForegroundColor Cyan
Write-Host ""

# Optional: Display additional info
# $AUTH_USER = azd env get-value AUTH_USER
# Write-Host "🔑 Additional info:" -ForegroundColor Yellow
# Write-Host "   Username: $AUTH_USER" -ForegroundColor White
