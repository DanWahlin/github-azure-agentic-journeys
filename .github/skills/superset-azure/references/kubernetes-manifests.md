# Kubernetes Manifest Patterns for Superset

## Complete Kubernetes Manifest Pattern

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
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
            pip install psycopg2-binary --target=/psycopg2-lib
            PYTHONPATH=/psycopg2-lib superset db upgrade
            PYTHONPATH=/psycopg2-lib superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password "$ADMIN_PASSWORD" || true
            PYTHONPATH=/psycopg2-lib superset init
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
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
        env:
        - name: SUPERSET_CONFIG_PATH
          value: /app/pythonpath/superset_config.py
        - name: PYTHONPATH
          value: "/psycopg2-lib"
        volumeMounts:
        - name: psycopg2-install
          mountPath: /psycopg2-lib
        - name: superset-config
          mountPath: /app/pythonpath
```

## superset_config.py (ConfigMap)

Superset does NOT read SQLALCHEMY_DATABASE_URI from environment directly. You MUST create a config file:

```python
import os

SQLALCHEMY_DATABASE_URI = os.environ.get('SQLALCHEMY_DATABASE_URI', 'sqlite:////app/superset_home/superset.db')
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'change-me')

WTF_CSRF_ENABLED = True
WTF_CSRF_EXEMPT_LIST = []
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}
```

Mount this at `/app/pythonpath/superset_config.py` and set:
```yaml
env:
- name: SUPERSET_CONFIG_PATH
  value: /app/pythonpath/superset_config.py
```

## Ingress with NGINX

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: superset-ingress
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
```
