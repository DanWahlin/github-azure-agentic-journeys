@description('Location for resources')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Managed identity resource ID')
param managedIdentityId string

@description('Superset container image')
param supersetImage string

@description('PostgreSQL host FQDN')
param postgresHost string

@description('PostgreSQL database name')
param postgresDb string

@description('PostgreSQL username')
param postgresUser string

@secure()
@description('PostgreSQL password')
param postgresPassword string

@secure()
@description('Superset secret key')
param supersetSecretKey string

@description('Superset admin username')
param supersetAdminUser string

@secure()
@description('Superset admin password')
param supersetAdminPassword string

@description('Tags to apply')
param tags object = {}

var databaseUrl = 'postgresql://${postgresUser}:${postgresPassword}@${postgresHost}:5432/${postgresDb}?sslmode=require'

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-superset-k8s'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.55.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      { name: 'AKS_CLUSTER_NAME', value: aksClusterName }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'SUPERSET_IMAGE', value: supersetImage }
      { name: 'DATABASE_URL', secureValue: databaseUrl }
      { name: 'SUPERSET_SECRET_KEY', secureValue: supersetSecretKey }
      { name: 'SUPERSET_ADMIN_USER', value: supersetAdminUser }
      { name: 'SUPERSET_ADMIN_PASSWORD', secureValue: supersetAdminPassword }
    ]
    scriptContent: '''
#!/bin/bash
set -e

echo "Installing kubectl..."
az aks install-cli

echo "Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing --admin

echo "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml

echo "Waiting for NGINX Ingress to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s || true

echo "Creating superset namespace..."
kubectl create namespace superset --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Kubernetes secret..."
kubectl create secret generic superset-secrets \
  --namespace superset \
  --from-literal=SQLALCHEMY_DATABASE_URI="$DATABASE_URL" \
  --from-literal=SUPERSET_SECRET_KEY="$SUPERSET_SECRET_KEY" \
  --from-literal=ADMIN_PASSWORD="$SUPERSET_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Superset ConfigMap..."
cat <<'CONFIGMAP_EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: superset-config
  namespace: superset
data:
  superset_config.py: |
    import os
    
    # Database configuration - reads from environment variable
    SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////app/superset_home/superset.db')
    
    # Secret key for Flask sessions
    SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'thisISaSECRET_1234')
    
    # CSRF configuration
    WTF_CSRF_ENABLED = True
    WTF_CSRF_EXEMPT_LIST = []
    WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365
    
    # Feature flags
    FEATURE_FLAGS = {
        "DASHBOARD_NATIVE_FILTERS": True,
        "DASHBOARD_CROSS_FILTERS": True,
        "ENABLE_TEMPLATE_PROCESSING": True,
    }
CONFIGMAP_EOF

echo "Deploying Superset..."
cat <<EOF | kubectl apply -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: superset
  namespace: superset
  labels:
    app: superset
spec:
  replicas: 1
  selector:
    matchLabels:
      app: superset
  template:
    metadata:
      labels:
        app: superset
    spec:
      volumes:
      - name: psycopg2-install
        emptyDir: {}
      - name: superset-config
        configMap:
          name: superset-config
      initContainers:
      - name: superset-init
        image: $SUPERSET_IMAGE
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Installing PostgreSQL driver..."
            pip install psycopg2-binary --target=/psycopg2-lib
            echo "Verifying psycopg2..."
            PYTHONPATH=/psycopg2-lib python -c "import psycopg2; print('psycopg2 OK')"
            echo "Running database migrations..."
            PYTHONPATH=/psycopg2-lib superset db upgrade
            echo "Creating admin user..."
            PYTHONPATH=/psycopg2-lib superset fab create-admin \
              --username $SUPERSET_ADMIN_USER \
              --firstname Admin \
              --lastname User \
              --email admin@example.com \
              --password "\$ADMIN_PASSWORD" || echo "Admin user may already exist"
            echo "Initializing Superset..."
            PYTHONPATH=/psycopg2-lib superset init
            echo "Init complete!"
        env:
        - name: SQLALCHEMY_DATABASE_URI
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: SQLALCHEMY_DATABASE_URI
        - name: SUPERSET_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: SUPERSET_SECRET_KEY
        - name: ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: ADMIN_PASSWORD
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      containers:
      - name: superset
        image: $SUPERSET_IMAGE
        command: ["/bin/sh", "-c"]
        args:
          - |
            export PYTHONPATH=/psycopg2-lib:\$PYTHONPATH
            exec gunicorn --bind 0.0.0.0:8088 --workers 2 --timeout 120 "superset.app:create_app()"
        ports:
        - containerPort: 8088
          name: http
        env:
        - name: SQLALCHEMY_DATABASE_URI
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: SQLALCHEMY_DATABASE_URI
        - name: SUPERSET_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: SUPERSET_SECRET_KEY
        - name: SUPERSET_LOAD_EXAMPLES
          value: "no"
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        - name: PYTHONPATH
          value: "/psycopg2-lib"
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8088
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 10
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8088
          initialDelaySeconds: 45
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 5
---
apiVersion: v1
kind: Service
metadata:
  name: superset
  namespace: superset
spec:
  selector:
    app: superset
  ports:
  - port: 80
    targetPort: 8088
    protocol: TCP
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: superset-ingress
  namespace: superset
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: superset
            port:
              number: 80
EOF

echo "Waiting for Superset pod to be ready..."
kubectl wait --namespace superset \
  --for=condition=ready pod \
  --selector=app=superset \
  --timeout=600s || echo "Pod may still be initializing"

echo "Getting external IP..."
for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$EXTERNAL_IP" ]; then
    echo "Superset is available at: http://$EXTERNAL_IP"
    echo "{\"supersetUrl\": \"http://$EXTERNAL_IP\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    exit 0
  fi
  echo "Waiting for external IP... ($i/30)"
  sleep 10
done

echo "Warning: Could not get external IP within timeout"
echo "{\"supersetUrl\": \"pending\"}" > $AZ_SCRIPTS_OUTPUT_PATH
'''
  }
}

output supersetUrl string = deploymentScript.properties.outputs.supersetUrl
