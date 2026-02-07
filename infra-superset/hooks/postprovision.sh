#!/bin/sh
set -e

echo "=== Superset Post-Provision Hook ==="

# Get values from azd environment
RESOURCE_GROUP=$(azd env get-value RESOURCE_GROUP_NAME)
AKS_CLUSTER=$(azd env get-value AKS_CLUSTER_NAME)
POSTGRES_FQDN=$(azd env get-value POSTGRES_FQDN)
POSTGRES_DB=$(azd env get-value POSTGRES_DATABASE_NAME)
POSTGRES_USER=$(azd env get-value POSTGRES_ADMIN_USER)
POSTGRES_PASSWORD=$(azd env get-value POSTGRES_PASSWORD)
SUPERSET_SECRET_KEY=$(azd env get-value SUPERSET_SECRET_KEY)
SUPERSET_ADMIN_PASSWORD=$(azd env get-value SUPERSET_ADMIN_PASSWORD)

# Build database URI
DATABASE_URI="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_FQDN}:5432/${POSTGRES_DB}?sslmode=require"

echo "1. Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing

echo "2. Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

echo "3. Waiting for NGINX Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s 2>/dev/null || echo "Waiting for ingress controller pods..."

# Wait for external IP
echo "4. Waiting for external IP assignment..."
EXTERNAL_IP=""
for i in $(seq 1 60); do
  EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$EXTERNAL_IP" ]; then
    echo "   External IP: $EXTERNAL_IP"
    break
  fi
  echo "   Attempt $i/60: Waiting for IP..."
  sleep 10
done

if [ -z "$EXTERNAL_IP" ]; then
  echo "ERROR: Failed to get external IP after 10 minutes"
  exit 1
fi

echo "5. Creating superset namespace..."
kubectl create namespace superset --dry-run=client -o yaml | kubectl apply -f -

echo "6. Creating ConfigMap for superset_config.py..."
kubectl apply -f - <<'CONFIGMAP_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: superset-config
  namespace: superset
data:
  superset_config.py: |
    import os

    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'SQLALCHEMY_DATABASE_URI',
        'sqlite:////app/superset_home/superset.db'
    )

    SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'change-me-in-production')

    WTF_CSRF_ENABLED = True
    WTF_CSRF_EXEMPT_LIST = []
    WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

    FEATURE_FLAGS = {
        "DASHBOARD_NATIVE_FILTERS": True,
        "DASHBOARD_CROSS_FILTERS": True,
        "ENABLE_TEMPLATE_PROCESSING": True,
    }

    WEBSERVER_PORT = 8088
    WEBSERVER_TIMEOUT = 120
    SUPERSET_LOAD_EXAMPLES = False
CONFIGMAP_EOF

echo "7. Creating Kubernetes Secret..."
kubectl create secret generic superset-secrets \
  --namespace superset \
  --from-literal=database-uri="$DATABASE_URI" \
  --from-literal=secret-key="$SUPERSET_SECRET_KEY" \
  --from-literal=admin-password="$SUPERSET_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "8. Deploying Superset Deployment + Service + Ingress..."
kubectl apply -f - <<'MANIFEST_EOF'
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
        image: apache/superset:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -e
            echo "Installing psycopg2-binary..."
            pip install psycopg2-binary --target=/psycopg2-lib
            echo "Running database migrations..."
            PYTHONPATH=/psycopg2-lib superset db upgrade
            echo "Creating admin user..."
            PYTHONPATH=/psycopg2-lib superset fab create-admin \
              --username admin \
              --firstname Admin \
              --lastname User \
              --email admin@example.com \
              --password "$ADMIN_PASSWORD" || true
            echo "Initializing Superset..."
            PYTHONPATH=/psycopg2-lib superset init
            echo "Init complete."
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        - name: SQLALCHEMY_DATABASE_URI
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: database-uri
        - name: SUPERSET_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: secret-key
        - name: ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: admin-password
        - name: PYTHONPATH
          value: "/psycopg2-lib"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
      containers:
      - name: superset
        image: apache/superset:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            export PYTHONPATH=/psycopg2-lib:$PYTHONPATH
            exec gunicorn --bind 0.0.0.0:8088 --workers 2 --timeout 120 "superset.app:create_app()"
        ports:
        - containerPort: 8088
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        - name: SQLALCHEMY_DATABASE_URI
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: database-uri
        - name: SUPERSET_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: superset-secrets
              key: secret-key
        - name: PYTHONPATH
          value: "/psycopg2-lib"
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 2Gi
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
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
        startupProbe:
          httpGet:
            path: /health
            port: 8088
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 60
---
apiVersion: v1
kind: Service
metadata:
  name: superset-service
  namespace: superset
  labels:
    app: superset
spec:
  type: ClusterIP
  selector:
    app: superset
  ports:
  - port: 80
    targetPort: 8088
    protocol: TCP
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
            name: superset-service
            port:
              number: 80
MANIFEST_EOF

echo "9. Waiting for Superset pod to be ready (this may take 3-5 minutes)..."
kubectl wait --namespace superset \
  --for=condition=ready pod \
  --selector=app=superset \
  --timeout=600s 2>/dev/null || echo "Pod may still be starting..."

echo "10. Checking pod status..."
kubectl get pods -n superset

# Set SUPERSET_URL in azd environment
SUPERSET_URL="http://$EXTERNAL_IP"
azd env set SUPERSET_URL "$SUPERSET_URL"

echo ""
echo "=== Superset Deployment Complete ==="
echo "URL: $SUPERSET_URL"
echo "Login: admin / <your SUPERSET_ADMIN_PASSWORD>"
