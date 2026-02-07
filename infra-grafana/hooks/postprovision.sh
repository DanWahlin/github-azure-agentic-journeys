#!/bin/bash
set -e

echo "Running post-deployment configuration..."

# Retrieve azd outputs
CONTAINER_APP_NAME=$(azd env get-value GRAFANA_CONTAINER_APP_NAME)
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

# Update GF_SERVER_ROOT_URL (circular dependency: needs FQDN which isn't known until after creation)
echo "Updating GF_SERVER_ROOT_URL environment variable..."
az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --set-env-vars "GF_SERVER_ROOT_URL=https://$APP_FQDN" \
  --output none

echo "Post-deployment configuration completed!"
echo ""
echo "Grafana deployment complete!"
echo "Access your app at: https://$APP_FQDN"
echo "Login: admin / <your GRAFANA_ADMIN_PASSWORD>"
echo ""
