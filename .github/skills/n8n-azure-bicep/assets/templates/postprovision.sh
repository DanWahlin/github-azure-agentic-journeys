#!/bin/bash
# Post-Provision Hook for n8n on Azure (macOS/Linux)
# This script automatically configures the WEBHOOK_URL environment variable
#
# Copy to: infra/hooks/postprovision.sh
# Make executable: chmod +x infra/hooks/postprovision.sh

set -e

echo "🔧 Configuring n8n post-deployment setup..."

# Retrieve deployment outputs using azd
N8N_APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RG_NAME=$(azd env get-value RESOURCE_GROUP_NAME)

echo "📡 Retrieving n8n Container App URL..."
N8N_FQDN=$(az containerapp show \
  --name "$N8N_APP_NAME" \
  --resource-group "$RG_NAME" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

if [ -z "$N8N_FQDN" ]; then
  echo "❌ Error: Could not retrieve Container App FQDN"
  exit 1
fi

echo "✅ n8n URL: https://$N8N_FQDN"

echo "🔄 Updating WEBHOOK_URL environment variable..."
az containerapp update \
  --name "$N8N_APP_NAME" \
  --resource-group "$RG_NAME" \
  --set-env-vars "WEBHOOK_URL=https://$N8N_FQDN" \
  --output none

echo "✅ Post-deployment configuration completed successfully!"
echo ""
echo "🎉 n8n deployment complete!"
echo "🌐 Access n8n at: https://$N8N_FQDN"
echo ""
echo "🔑 Login credentials:"
echo "   Username: $(azd env get-value N8N_BASIC_AUTH_USER)"
echo "   Password: (from your main.parameters.json)"
echo ""
