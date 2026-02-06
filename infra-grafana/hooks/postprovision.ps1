# Post-Provision Hook for Grafana on Azure (Windows)

Write-Host "Grafana post-deployment setup..."

$GRAFANA_URL = azd env get-value GRAFANA_URL 2>$null

if ([string]::IsNullOrEmpty($GRAFANA_URL)) {
    Write-Host "Retrieving Grafana URL from deployment outputs..."
    $RG_NAME = "rg-$(azd env get-value AZURE_ENV_NAME)"
    
    $GRAFANA_APP = az containerapp list --resource-group $RG_NAME --query "[0].name" -o tsv 2>$null
    
    if ($GRAFANA_APP) {
        $GRAFANA_FQDN = az containerapp show --name $GRAFANA_APP --resource-group $RG_NAME --query "properties.configuration.ingress.fqdn" -o tsv
        $GRAFANA_URL = "https://$GRAFANA_FQDN"
        azd env set GRAFANA_URL $GRAFANA_URL
    }
}

Write-Host "Post-deployment configuration completed!"
Write-Host ""
Write-Host "Grafana deployment complete!"
Write-Host "Access Grafana at: $GRAFANA_URL"
Write-Host ""
Write-Host "Login credentials:"
Write-Host "   Username: admin"
Write-Host "   Password: (from GRAFANA_ADMIN_PASSWORD env var)"
Write-Host ""
