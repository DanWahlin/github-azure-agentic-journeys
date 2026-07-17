---
name: container-apps-deployment
description: |
  Container Apps deployment gotchas and SPA frontend patterns for Azure. Supplements the official azure-prepare plugin skill with additional patterns for zone redundancy, azure.yaml configuration, and SPA frontend deployment (VITE_API_URL).
  USE FOR: Container Apps zone redundancy errors, managed-identity ACR pulls, azure.yaml language fields, cross-platform hooks, SPA frontend VITE_API_URL, React deployment to Azure, and ARM64-to-AMD64 builds.
  DO NOT USE FOR: generating complete Bicep infrastructure from scratch (use azure-prepare plugin) or AKS deployments (use superset-azure).
---

# Container Apps Deployment Patterns

Supplements the official `azure-prepare` plugin skill with additional gotchas for Container Apps deployments — zone redundancy, azure.yaml, and SPA frontend patterns.

> **📖 ACR authentication:** Use a deterministic two-phase pattern. Provision Container Apps with a public placeholder image and system-assigned identity, grant `AcrPull`, then configure `configuration.registries` with the ACR login server and `identity: 'system'` before deploying private images. Some azd versions call `az containerapp registry set` automatically and some do not. Never assume that implicit step occurred; verify the registry configuration before the first private-image deployment.

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

### Cross-platform hooks

This repository requires `azd` 1.28.0 or later and Node.js 24 LTS or later. Use JavaScript or TypeScript hooks referenced directly from `azure.yaml`; `azd` detects the language from the extension. Do not generate Bash-only `.sh` or PowerShell-only `.ps1` lifecycle hooks.

```yaml
hooks:
  postprovision:
    run: infra/hooks/postprovision.js
  postdeploy:
    run: infra/hooks/postdeploy.js
```

Use `postprovision` for steps that need infrastructure outputs, such as setting `WEBHOOK_URL`. Use `postdeploy` for steps that need deployed services, such as rebuilding a frontend with its API URL. Hook code must invoke `az`, `azd`, and Docker through `execFileSync()` or `spawnSync()` argument arrays, never interpolated shell command strings.

## SPA Frontend Deployment (React/Vite)

### The VITE_API_URL Problem

When deploying a React/Vite frontend and API as **separate Container Apps**, the frontend needs the API's URL baked in at build time. But the API URL isn't known until after provisioning.

**Symptoms:**
- Frontend shows `Unexpected token '<', "<!doctype "... is not valid JSON`
- The React app calls `/api/products` on the web container (nginx), which returns `index.html`

**Root Cause:** `VITE_API_URL` defaults to `/api` (the Vite dev proxy). In production, nginx has no `/api` route — it serves the SPA for all paths.

### Solution: Cross-platform post-deploy hook

**Do not leave this as a manual learner step on first success.** Generate `infra/hooks/postdeploy.js` and reference it directly from `azure.yaml`:

```yaml
hooks:
  postdeploy:
    run: infra/hooks/postdeploy.js
```

The JavaScript hook must:

1. Resolve the application root with `import.meta.url` and `fileURLToPath()` rather than assuming the current working directory.
2. Read `API_URL`, `AZURE_CONTAINER_REGISTRY_ENDPOINT`, and `RESOURCE_GROUP_NAME` with `azd env get-value`.
3. Find the web Container App by its `azd-service-name=web` tag.
4. Log in to ACR through Azure CLI.
5. Build the frontend with `VITE_API_URL=<API_URL>/api` and target `linux/amd64`.
6. Push a unique image tag and update the web Container App.
7. Wait until the new revision is ready, then verify the storefront can load products.

Call external tools with `execFileSync()` or `spawnSync()` and argument arrays. Do not concatenate a shell command, use `chmod`, or depend on Bash, PowerShell, `cut`, `grep`, or `date`. Use JavaScript for path handling, timestamps, retries, and JSON parsing.

A filtered command such as `azd deploy web` can skip project-level hooks. After any filtered web deployment, run `node infra/hooks/postdeploy.js` explicitly and verify production product loading.

**After the first green deploy**, explain why the hook exists. Don't make the learner discover a blank product grid first.

### Frontend Dockerfile Requirements

```dockerfile
FROM --platform=$BUILDPLATFORM node:24-alpine AS build
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

**Keys:** `ARG` + `ENV` must appear **before** `RUN npm run build` so Vite picks up the URL. `$BUILDPLATFORM` keeps the static Vite/esbuild build native on ARM64 hosts; the final image is still built for the requested `linux/amd64` target.

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

## ARM64 Host Cross-Compilation

Azure Container Apps runs Linux AMD64. This applies to Apple Silicon, Windows ARM64, and Linux ARM64 hosts.

Prefer remote ACR builds targeting `linux/amd64`. If the journey builds locally, preflight must verify Docker Buildx and AMD64 emulation before deployment. Never install privileged QEMU/binfmt handlers automatically. On a managed Linux host, stop and ask for approval or use the remote build path.

Without an AMD64 target, the container crashes with `exec format error`. Building native tools such as esbuild entirely under emulation can also crash, which is why static frontend builder stages use `$BUILDPLATFORM`.

## Bicep `uniqueString()` Length Contracts

Azure's `uniqueString()` always returns 13 characters. When passing that value into a module, declare the module parameter with both `@minLength(13)` and `@maxLength(13)`. Otherwise Bicep can emit false `BCP334` warnings when the parameter is used in constrained resource names.

## Bicep Output Naming Convention

Outputs must use **SCREAMING_SNAKE_CASE** for azd to pick them up:

```bicep
output API_URL string = 'https://${apiApp.outputs.fqdn}'
output WEB_URL string = 'https://${webApp.outputs.fqdn}'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output RESOURCE_GROUP_NAME string = rg.name
```

Wrong naming → `azd env get-value` returns "key not found".
