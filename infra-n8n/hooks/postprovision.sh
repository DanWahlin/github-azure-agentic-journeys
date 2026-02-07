#!/bin/bash
set -e

echo "Running post-deployment configuration..."

# Retrieve azd outputs
CONTAINER_APP_NAME=$(azd env get-value N8N_CONTAINER_APP_NAME)
RESOURCE_GROUP_NAME=$(azd env get-value RESOURCE_GROUP_NAME)

# Get Container App FQDN
echo "Retrieving Container App URL..."
APP_FQDN=$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

if [ -z "$APP_FQDN" ]; then
  echo "Error: Could not retrieve Container App FQDN"
  exit 1
fi

echo "App URL: https://$APP_FQDN"

# Update WEBHOOK_URL (circular dependency: needs FQDN which isn't known until after creation)
echo "Updating WEBHOOK_URL environment variable..."
az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --set-env-vars "WEBHOOK_URL=https://$APP_FQDN" \
  --output none

echo "Post-deployment configuration completed!"
echo ""
echo "n8n deployment complete!"
echo "Access your app at: https://$APP_FQDN"
echo "Login: admin / <your N8N_BASIC_AUTH_PASSWORD>"
echo ""
