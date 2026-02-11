$ErrorActionPreference = "Stop"

Write-Host "Running post-provision hook: deploying Superset to AKS..."

# Get resource names from azd outputs
$AKS_NAME = azd env get-value AKS_CLUSTER_NAME
$RG_NAME = azd env get-value RESOURCE_GROUP_NAME
$PG_FQDN = azd env get-value POSTGRES_FQDN
$PG_USER = azd env get-value POSTGRES_USER
$PG_DB = azd env get-value POSTGRES_DATABASE
$SUPERSET_IMAGE = azd env get-value SUPERSET_IMAGE

# Get secrets from azd env
$PG_PASSWORD = azd env get-value POSTGRES_PASSWORD
$SECRET_KEY = azd env get-value SUPERSET_SECRET_KEY
$ADMIN_PASSWORD = azd env get-value SUPERSET_ADMIN_PASSWORD

# Build the database URI with sslmode=require for Azure PostgreSQL
$DATABASE_URI = "postgresql://${PG_USER}:${PG_PASSWORD}@${PG_FQDN}:5432/${PG_DB}?sslmode=require"

Write-Host "Connecting to AKS cluster: $AKS_NAME"
az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME --overwrite-existing

# Apply namespace
Write-Host "Creating superset namespace..."
kubectl apply -f ./infra-superset/kubernetes/namespace.yaml

# Create Kubernetes secret
Write-Host "Creating Kubernetes secrets..."
kubectl create secret generic superset-secrets `
  --namespace superset `
  --from-literal=database-uri="$DATABASE_URI" `
  --from-literal=secret-key="$SECRET_KEY" `
  --from-literal=admin-password="$ADMIN_PASSWORD" `
  --dry-run=client -o yaml | kubectl apply -f -

# Apply ConfigMap
Write-Host "Applying ConfigMap..."
kubectl apply -f ./infra-superset/kubernetes/configmap.yaml

# Replace image placeholder and apply deployment
Write-Host "Deploying Superset (image: $SUPERSET_IMAGE)..."
(Get-Content ./infra-superset/kubernetes/deployment.yaml) -replace 'SUPERSET_IMAGE_PLACEHOLDER', $SUPERSET_IMAGE | kubectl apply -f -

# Apply service and ingress
Write-Host "Applying service and ingress..."
kubectl apply -f ./infra-superset/kubernetes/service.yaml

# Install NGINX ingress controller if not present
$ingressNs = kubectl get namespace ingress-nginx 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "Installing NGINX ingress controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.6/deploy/static/provider/cloud/deploy.yaml
  Write-Host "Waiting for ingress controller to be ready..."
  kubectl wait --namespace ingress-nginx `
    --for=condition=ready pod `
    --selector=app.kubernetes.io/component=controller `
    --timeout=300s
}

kubectl apply -f ./infra-superset/kubernetes/ingress.yaml

# Wait for pod to be ready
Write-Host "Waiting for Superset pod to start (this may take several minutes)..."
kubectl wait --namespace superset `
  --for=condition=ready pod `
  --selector=app=superset `
  --timeout=600s

# Get external IP
Write-Host ""
Write-Host "Getting external IP..."
$EXTERNAL_IP = ""
$retries = 0
while ([string]::IsNullOrEmpty($EXTERNAL_IP) -and $retries -lt 30) {
  $EXTERNAL_IP = kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
  if ([string]::IsNullOrEmpty($EXTERNAL_IP)) {
    Start-Sleep -Seconds 10
    $retries++
  }
}

Write-Host "========================================="
Write-Host "Superset deployment completed!"
Write-Host "========================================="
if (-not [string]::IsNullOrEmpty($EXTERNAL_IP)) {
  Write-Host "Access Superset at: http://$EXTERNAL_IP"
  Write-Host "Login: admin / <your SUPERSET_ADMIN_PASSWORD>"
} else {
  Write-Host "External IP not yet assigned. Check with:"
  Write-Host "  kubectl get svc -n ingress-nginx ingress-nginx-controller"
}
Write-Host "========================================="
