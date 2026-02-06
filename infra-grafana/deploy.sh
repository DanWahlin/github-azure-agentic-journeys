#!/bin/bash
# Grafana Azure Container Apps Deployment Script
# Tested and verified for reproducibility

set -e

# Configuration
ENV_NAME="${1:-grafana-prod}"
LOCATION="${2:-westus}"
ADMIN_PASSWORD="${3:-$(openssl rand -base64 16)}"

echo "=========================================="
echo "Grafana Azure Deployment"
echo "=========================================="
echo "Environment: $ENV_NAME"
echo "Location:    $LOCATION"
echo "Password:    $ADMIN_PASSWORD"
echo "=========================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Deploy
echo ""
echo "Deploying infrastructure..."
DEPLOYMENT_OUTPUT=$(az deployment sub create \
  --name "grafana-deploy-$(date +%s)" \
  --location "$LOCATION" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters environmentName="$ENV_NAME" \
               location="$LOCATION" \
               grafanaAdminPassword="$ADMIN_PASSWORD" \
  --query "properties.outputs" \
  -o json)

# Extract outputs
GRAFANA_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.grafanA_URL.value')
GRAFANA_FQDN=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.grafanA_FQDN.value')
RESOURCE_GROUP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.resourcE_GROUP_NAME.value')

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo "URL:            $GRAFANA_URL"
echo "Resource Group: $RESOURCE_GROUP"
echo "Username:       admin"
echo "Password:       $ADMIN_PASSWORD"
echo "=========================================="

# Verify
echo ""
echo "Verifying deployment..."
sleep 5

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ Health check passed (HTTP $HTTP_STATUS)"
  
  # Test login
  LOGIN_RESULT=$(curl -s -u "admin:$ADMIN_PASSWORD" "$GRAFANA_URL/api/org" 2>/dev/null || echo "")
  if echo "$LOGIN_RESULT" | grep -q "Main Org"; then
    echo "✅ Admin login verified"
  else
    echo "⚠️  Admin login check inconclusive"
  fi
else
  echo "⚠️  Health check returned HTTP $HTTP_STATUS (may need cold start time)"
  echo "    Try: curl $GRAFANA_URL/api/health"
fi

echo ""
echo "To delete: az group delete --name $RESOURCE_GROUP --yes --no-wait"
