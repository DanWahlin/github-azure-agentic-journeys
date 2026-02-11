#!/bin/sh
set -e

echo "Running post-provision hook: configuring GF_SERVER_ROOT_URL..."

# Get resource names from azd outputs
APP_NAME=$(azd env get-value GRAFANA_CONTAINER_APP_NAME)
RG_NAME=$(azd env get-value RESOURCE_GROUP_NAME)

# Get the Container App FQDN
GRAFANA_FQDN=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG_NAME" \
  --query "properties.configuration.ingress.fqdn" -o tsv)

if [ -z "$GRAFANA_FQDN" ]; then
  echo "Error: Could not retrieve Container App FQDN"
  exit 1
fi

echo "Setting GF_SERVER_ROOT_URL to https://$GRAFANA_FQDN"

# Update the Container App with the root URL
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG_NAME" \
  --set-env-vars "GF_SERVER_ROOT_URL=https://$GRAFANA_FQDN" \
  --output none

echo "Post-provision configuration completed."
echo "Access Grafana at: https://$GRAFANA_FQDN"
