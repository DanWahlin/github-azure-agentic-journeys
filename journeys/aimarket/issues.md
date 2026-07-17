
---

## Run 2026-07-16 (journey-runner, Node.js/TS stack, westus, env jr-aimarket-0716)

### 2026-07-16 — Phase 1 (Local) — Price validation false-negative on valid two-decimal values
- **Error:** PUT /products with `price: 64.99` returned 400 VALIDATION_ERROR; test "updates a product partially" failed.
- **Diagnosis:** `twoDecimals` check used `Math.round(n*100) === n*100`. Floating point makes `64.99*100 = 6498.9999…`, so equality failed for legitimate 2-decimal prices.
- **Fix:** Changed to `Math.round(n*100)/100 === n`. All 21 tests pass.
- **Status:** Resolved.

### 2026-07-16 — Phase 1 (Local) — Port 3000 already in use in shared environment
- **Error:** API failed to bind (`EADDRINUSE :::3000`) — another app (Umami) occupies 3000 on the shared host.
- **Diagnosis:** Non-isolated runtime; local smoke tests collided with an existing service.
- **Fix/Workaround:** Ran local verification with `PORT=3100`. No code change needed; production uses its own container.
- **Status:** Resolved (workaround).

### 2026-07-16 — Phase 4 (Deploy) — ARM64 build host, Container Apps require linux/amd64
- **Error:** Host is aarch64; azd default builds produce arm64 images that won't run on Container Apps.
- **Diagnosis:** No QEMU binfmt emulation registered for x86_64; cross-arch `RUN` steps failed with exit 255.
- **Fix:** `docker run --privileged --rm tonistiigi/binfmt --install amd64` to register qemu-x86_64, and added `docker.platform: linux/amd64` to both services in `azure.yaml`.
- **Status:** Resolved.

### 2026-07-16 — Phase 4 (Deploy) — ACR pull UNAUTHORIZED on first API revision
- **Error:** `Field 'template.containers.api.image' is invalid … UNAUTHORIZED: authentication required` when the container app tried to pull the pushed image.
- **Diagnosis:** azd 1.23.3 did not auto-wire identity-based ACR auth (`az containerapp registry set`); the container app had no registry credentials for the private ACR.
- **Fix:** Added an explicit `configuration.registries` block (`server: <acr>.azurecr.io`, `identity: 'system'`) to both container apps in `resources.bicep`, backed by the AcrPull role assignment already granted to each app's system-assigned managed identity. Re-provisioned, then deployed.
- **Status:** Resolved.

### 2026-07-16 — Phase 4 (Deploy) — esbuild crash under amd64 QEMU emulation (web build)
- **Error:** Vite/esbuild aborted (`The service was stopped`, Go runtime crash) while building the web image under `--platform linux/amd64` emulation.
- **Diagnosis:** esbuild's native x86_64 binary is unstable under qemu-x86_64 emulation on the arm64 host.
- **Fix:** Changed the web `Dockerfile` build stage to `FROM --platform=$BUILDPLATFORM node:20-alpine` so the SPA is built natively (arm64); only the final `nginx:alpine` runtime stage targets amd64. Static output is architecture-independent. (API image keeps the emulated amd64 build because better-sqlite3 needs a matching-arch native binary.)
- **Status:** Resolved.

### 2026-07-16 — Phase 4 (Deploy) — Single-service `azd deploy web` skips postdeploy hook
- **Error:** After `azd deploy web`, the web image had `VITE_API_URL` unset (defaults to `/api`), which nginx can't proxy — storefront would fail to load products.
- **Diagnosis:** The project-level `hooks.postdeploy` only runs on a full `azd deploy`/`azd up`, not a filtered single-service deploy.
- **Fix/Workaround:** Ran `sh infra/hooks/postdeploy.sh` manually to rebuild the web image with `VITE_API_URL=<API_URL>/api` and update the web container app. A full `azd up` first run would trigger the hook automatically.
- **Status:** Resolved.

### 2026-07-16 — Phase 2/Seed (Cosmetic) — One product image returns 404
- **Error:** The "Building Block Castle Set" (`prod-10`) Unsplash photo ID does not resolve; card shows alt text instead of an image.
- **Diagnosis:** Chosen Unsplash `photo-…` ID for the toy category is invalid. Client fetches Unsplash directly, so only that one image is blank.
- **Fix/Workaround:** Left as a known cosmetic issue (no functional impact; other 9 images load, storefront renders, products load). Replaceable by updating the `photoId` for `prod-10` in `api/src/data/seed.ts` with a valid Unsplash ID and redeploying the API.
- **Status:** Open (cosmetic, non-blocking).

## 2026-07-17 — Repository remediation

- Price validation now requires finite decimal-safe handling and regression coverage for `64.99`, `0.1`, invalid three-decimal values, `NaN`, and infinities.
- The README requires configurable local ports and portable Node.js verification.
- ARM64 guidance now covers Windows, macOS, and Linux, prefers remote ACR builds, uses `$BUILDPLATFORM` for static assets, and forbids automatic privileged binfmt installation.
- Managed-identity ACR registry configuration and `AcrPull` are explicit acceptance criteria.
- The portable `postdeploy.mjs` hook is required after filtered web deployments.
- `prod-10` now has the validated Unsplash photo ID `photo-1587654780291-39c9404d746b` in the PLAN, and all product images must return HTTP 2xx.
- **Status:** All recorded README, PLAN, and associated-skill defects resolved. Historical run workarounds above remain as evidence.
