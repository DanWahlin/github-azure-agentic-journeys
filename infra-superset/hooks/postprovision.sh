#!/bin/sh
set -e

echo "Running post-provision hook: deploying Superset to AKS..."

# Get resource names from azd outputs
AKS_NAME=$(azd env get-value AKS_CLUSTER_NAME)
RG_NAME=$(azd env get-value RESOURCE_GROUP_NAME)
PG_FQDN=$(azd env get-value POSTGRES_FQDN)
PG_USER=$(azd env get-value POSTGRES_USER)
PG_DB=$(azd env get-value POSTGRES_DATABASE)
SUPERSET_IMAGE=$(azd env get-value SUPERSET_IMAGE)

# Get secrets from azd env
PG_PASSWORD=$(azd env get-value POSTGRES_PASSWORD)
SECRET_KEY=$(azd env get-value SUPERSET_SECRET_KEY)
ADMIN_PASSWORD=$(azd env get-value SUPERSET_ADMIN_PASSWORD)

# Build the database URI with sslmode=require for Azure PostgreSQL
DATABASE_URI="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_FQDN}:5432/${PG_DB}?sslmode=require"

echo "Connecting to AKS cluster: $AKS_NAME"
az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing

# Apply namespace
echo "Creating superset namespace..."
kubectl apply -f ./infra-superset/kubernetes/namespace.yaml

# Create Kubernetes secret
echo "Creating Kubernetes secrets..."
kubectl create secret generic superset-secrets \
  --namespace superset \
  --from-literal=database-uri="$DATABASE_URI" \
  --from-literal=secret-key="$SECRET_KEY" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply ConfigMap
echo "Applying ConfigMap..."
kubectl apply -f ./infra-superset/kubernetes/configmap.yaml

# Replace image placeholder and apply deployment
echo "Deploying Superset (image: $SUPERSET_IMAGE)..."
sed "s|SUPERSET_IMAGE_PLACEHOLDER|${SUPERSET_IMAGE}|g" \
  ./infra-superset/kubernetes/deployment.yaml | kubectl apply -f -

# Apply service and ingress
echo "Applying service and ingress..."
kubectl apply -f ./infra-superset/kubernetes/service.yaml

# Install NGINX ingress controller if not present
if ! kubectl get namespace ingress-nginx > /dev/null 2>&1; then
  echo "Installing NGINX ingress controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/cloud/deploy.yaml
  echo "Waiting for ingress controller to be ready..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
fi

kubectl apply -f ./infra-superset/kubernetes/ingress.yaml

# Wait for pod to be ready
echo "Waiting for Superset pod to start (this may take several minutes)..."
kubectl wait --namespace superset \
  --for=condition=ready pod \
  --selector=app=superset \
  --timeout=600s || echo "Warning: Pod not ready within timeout. Check logs with: kubectl logs -n superset -l app=superset -c superset-init"

# Get external IP
echo ""
echo "Getting external IP..."
EXTERNAL_IP=""
RETRIES=0
while [ -z "$EXTERNAL_IP" ] && [ $RETRIES -lt 30 ]; do
  EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -z "$EXTERNAL_IP" ]; then
    sleep 10
    RETRIES=$((RETRIES + 1))
  fi
done

echo "========================================="
echo "Superset deployment completed!"
echo "========================================="
if [ -n "$EXTERNAL_IP" ]; then
  echo "Access Superset at: http://$EXTERNAL_IP"
  echo "Login: admin / <your SUPERSET_ADMIN_PASSWORD>"
else
  echo "External IP not yet assigned. Check with:"
  echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
fi
echo "========================================="
