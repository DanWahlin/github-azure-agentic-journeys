---
name: container-apps-deployment
description: |
  Container Apps deployment gotchas and SPA frontend patterns for Azure. Supplements the official azure-prepare plugin skill with additional patterns for zone redundancy, azure.yaml configuration, and SPA frontend deployment (VITE_API_URL).
  USE FOR: Container Apps zone redundancy errors, azure.yaml language field, SPA frontend VITE_API_URL, React deployment to Azure, multi-service Container Apps frontend+API.
  DO NOT USE FOR: generating Bicep infrastructure from scratch (use azure-prepare plugin), ACR authentication setup (use azure-prepare bicep.md two-phase pattern), AKS deployments (use superset-azure).
---

# Container Apps Deployment Patterns

Supplements the official `azure-prepare` plugin skill with additional gotchas for Container Apps deployments — zone redundancy, azure.yaml, and SPA frontend patterns.

> **📖 ACR Authentication:** Follow the **two-phase pattern** in `azure-prepare` plugin's `references/services/container-apps/bicep.md`. Do NOT add a `registries` block in Bicep — `azd deploy` calls `az containerapp registry set --identity system` for you.

## Region-Specific Gotchas

### Container Apps Environment `zoneRedundant`

The AVM module `br/public:avm/res/app/managed-environment` may default `zoneRedundant` to true. Several regions (including `westus`) don't support it.

```bicep
module cae 'br/public:avm/res/app/managed-environment:0.8.1' = {
  params: {
    // ...
    zoneRedundant: false  // Required for westus and other regions without zone support
  }
}
```

**Without this:** `azd up` fails with "Zone redundancy is not currently supported in this region".

## azure.yaml Configuration

### Docker services require `language` field

azd requires either `language` or `image` on each service, even when `docker.path` is specified:

```yaml
services:
  api:
    host: containerapp
    language: ts                  # REQUIRED — azd won't infer from Dockerfile
    docker:
      path: api/Dockerfile
      context: api
  web:
    host: containerapp
    language: ts
    docker:
      path: client/Dockerfile
      context: client
```

**Without `language`:** `azd up` fails with "must specify language or image".

### Hooks for post-deploy steps

```yaml
hooks:
  postprovision:
    shell: sh
    run: infra/hooks/postprovision.sh   # Runs after azd provision
  postdeploy:
    shell: sh
    run: infra/hooks/postdeploy.sh      # Runs after azd deploy
```

Use `postprovision` for steps that need the infrastructure (e.g., setting WEBHOOK_URL from FQDN).
Use `postdeploy` for steps that need deployed services (e.g., rebuilding frontend with API URL).

## SPA Frontend Deployment (React/Vite)

### The VITE_API_URL Problem

When deploying a React/Vite frontend and API as **separate Container Apps**, the frontend needs the API's URL baked in at build time. But the API URL isn't known until after provisioning.

**Symptoms:**
- Frontend shows `Unexpected token '<', "<!doctype "... is not valid JSON`
- The React app calls `/api/products` on the web container (nginx), which returns `index.html`

**Root Cause:** `VITE_API_URL` defaults to `/api` (the Vite dev proxy). In production, nginx has no `/api` route — it serves the SPA for all paths.

### Solution: Post-deploy Hook

Add a `postdeploy` hook that rebuilds the frontend with the real API URL:

```bash
#!/bin/sh
set -e
echo "=== Post-deploy: Rebuilding frontend with API URL ==="

API_URL=$(azd env get-value API_URL)
ACR_SERVER=$(azd env get-value AZURE_CONTAINER_REGISTRY_ENDPOINT)
ACR_NAME=$(echo "$ACR_SERVER" | cut -d. -f1)
RG=$(azd env get-value RESOURCE_GROUP_NAME)

az acr login --name "$ACR_NAME"

# Rebuild with the real API URL baked in
docker build --platform linux/amd64 \
  --build-arg VITE_API_URL="${API_URL}/api" \
  -t "${ACR_SERVER}/myapp/web:fixed" client/

docker push "${ACR_SERVER}/myapp/web:fixed"

# Update the container app to use the new image
WEB_APP=$(az containerapp list --resource-group "$RG" \
  --query "[?tags.\"azd-service-name\"=='web'].name" -o tsv)
az containerapp update --name "$WEB_APP" --resource-group "$RG" \
  --image "${ACR_SERVER}/myapp/web:fixed"
```

### Frontend Dockerfile Requirements

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

**Key:** `ARG` + `ENV` must appear **before** `RUN npm run build` so Vite picks it up.

### nginx.conf — SPA Only

```nginx
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }
}
```

**Do NOT add an `/api/` proxy block.** The frontend calls the API directly via `VITE_API_URL`. Adding a proxy to an internal hostname will fail because Container Apps don't resolve each other by name without VNet.

### Frontend API Client Pattern

```typescript
const API_BASE = import.meta.env.VITE_API_URL || '/api';

export async function getProducts() {
  const res = await fetch(`${API_BASE}/products`);
  return res.json();
}
```

In dev: `VITE_API_URL` is unset → falls back to `/api` → Vite proxy handles it.
In prod: `VITE_API_URL` is `https://ca-api-xxx.azurecontainerapps.io/api` → calls API directly.

## Apple Silicon (M1/M2/M3) Cross-Compilation

Azure Container Apps runs Linux AMD64. When building on Apple Silicon:

```bash
docker build --platform linux/amd64 -t myimage .
```

Without `--platform linux/amd64`, the image builds for ARM64 and the container crashes with `exec format error`.

## Bicep Output Naming Convention

Outputs must use **SCREAMING_SNAKE_CASE** for azd to pick them up:

```bicep
output API_URL string = 'https://${apiApp.outputs.fqdn}'
output WEB_URL string = 'https://${webApp.outputs.fqdn}'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output RESOURCE_GROUP_NAME string = rg.name
```

Wrong naming → `azd env get-value` returns "key not found".
