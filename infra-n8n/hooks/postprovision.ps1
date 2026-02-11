Write-Host "Running post-provision hook: configuring WEBHOOK_URL..."

# Get resource names from azd outputs
$APP_NAME = azd env get-value N8N_CONTAINER_APP_NAME
$RG_NAME = azd env get-value RESOURCE_GROUP_NAME

# Get the Container App FQDN
$N8N_FQDN = az containerapp show `
  --name $APP_NAME `
  --resource-group $RG_NAME `
  --query "properties.configuration.ingress.fqdn" -o tsv

Write-Host "Setting WEBHOOK_URL to https://$N8N_FQDN"

# Update the Container App with the WEBHOOK_URL
az containerapp update `
  --name $APP_NAME `
  --resource-group $RG_NAME `
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN"

Write-Host "WEBHOOK_URL configured successfully."
