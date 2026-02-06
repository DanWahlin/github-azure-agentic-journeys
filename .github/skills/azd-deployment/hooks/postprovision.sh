#!/bin/bash
# Post-Provision Hook Template (macOS/Linux)
# Copy and customize for your application
#
# Usage: cp postprovision.sh /path/to/infra/hooks/
#        chmod +x /path/to/infra/hooks/postprovision.sh

set -e

echo "🔧 Running post-deployment configuration..."

# =============================================================================
# Retrieve azd outputs
# =============================================================================
# Replace with your actual output names from main.bicep

CONTAINER_APP_NAME=$(azd env get-value CONTAINER_APP_NAME)
RESOURCE_GROUP_NAME=$(azd env get-value RESOURCE_GROUP_NAME)

# =============================================================================
# Get Container App FQDN
# =============================================================================

echo "📡 Retrieving Container App URL..."
APP_FQDN=$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query "properties.configuration.ingress.fqdn" \
  -o tsv)

if [ -z "$APP_FQDN" ]; then
  echo "❌ Error: Could not retrieve Container App FQDN"
  exit 1
fi

echo "✅ App URL: https://$APP_FQDN"

# =============================================================================
# Update environment variables (customize as needed)
# =============================================================================
# Common use case: Configure WEBHOOK_URL for applications that need their
# public URL but can't know it during initial deployment

echo "🔄 Updating environment variables..."
az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --set-env-vars "WEBHOOK_URL=https://$APP_FQDN" \
  --output none

# =============================================================================
# Success message
# =============================================================================

echo "✅ Post-deployment configuration completed!"
echo ""
echo "🎉 Deployment complete!"
echo "🌐 Access your app at: https://$APP_FQDN"
echo ""

# Optional: Display additional info
# echo "🔑 Additional info:"
# echo "   Username: $(azd env get-value AUTH_USER)"
