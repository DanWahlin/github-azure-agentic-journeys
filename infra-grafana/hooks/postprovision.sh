#!/bin/bash
# Post-Provision Hook for Grafana on Azure

set -e

echo "🔧 Grafana post-deployment setup..."

GRAFANA_URL=$(azd env get-value GRAFANA_URL 2>/dev/null || echo "")

if [ -z "$GRAFANA_URL" ]; then
  echo "📡 Retrieving Grafana URL from deployment outputs..."
  RG_NAME=$(azd env get-value AZURE_ENV_NAME)
  RG_NAME="rg-$RG_NAME"
  
  GRAFANA_APP=$(az containerapp list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null || echo "")
  
  if [ -n "$GRAFANA_APP" ]; then
    GRAFANA_FQDN=$(az containerapp show --name "$GRAFANA_APP" --resource-group "$RG_NAME" --query "properties.configuration.ingress.fqdn" -o tsv)
    GRAFANA_URL="https://$GRAFANA_FQDN"
    azd env set GRAFANA_URL "$GRAFANA_URL"
  fi
fi

echo "✅ Post-deployment configuration completed!"
echo ""
echo "🎉 Grafana deployment complete!"
echo "🌐 Access Grafana at: $GRAFANA_URL"
echo ""
echo "🔑 Login credentials:"
echo "   Username: admin"
echo "   Password: (from GRAFANA_ADMIN_PASSWORD env var)"
echo ""
