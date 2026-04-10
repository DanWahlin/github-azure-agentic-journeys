# SmartTodo Journey Issues

Tracked issues found during the journey run.

## Issue 1: `stepsGenerated` not in UpdateTodoInput

**Severity:** Medium  
**Phase:** Phase 1 — API  
**File:** PLAN.md (Data Access Layer section)

**Problem:** The PLAN.md defines `UpdateTodoInput` with only `title` and `status` fields, but `generateSteps` needs to set `stepsGenerated = true` after generating steps. The spec says to "set stepsGenerated = true on the todo" but provides no mechanism via the repository interface.

**Fix:** Added `stepsGenerated?: boolean` to `UpdateTodoInput` and updated the SQL implementation to support it. The PLAN.md should include this in the UpdateTodoInput definition or explicitly note that `generateSteps` needs a way to update the flag.

**Status:** ✅ Fixed in code and PLAN.md.

**Severity:** Low  
**Phase:** Phase 1 — API

**Problem:** The `mssql` package doesn't ship its own TypeScript types. The PLAN.md doesn't mention needing `@types/mssql` as a dev dependency. Build fails with TS7016 without it.

**Fix:** Added `@types/mssql` to devDependencies. PLAN.md should list this in the Node.js dependencies.

**Status:** ✅ Fixed in code and PLAN.md.

## Issue 3: README uses `az sql db execute` which doesn't exist

**Severity:** High  
**Phase:** Phase 3 — Deploy  
**File:** README.md (Step 3: Set up Azure SQL managed identity access)

**Problem:** The README instructs users to run `az sql db execute --server ... --database ... --query "CREATE USER..."` but `az sql db execute` is not a valid Azure CLI command. The PLAN.md correctly notes this and suggests using `sqlcmd`, but the README doesn't match.

**Fix:** README should be updated to use `sqlcmd` or a script approach consistent with PLAN.md.

**Status:** ✅ Fixed in README.md.

## Issue 4: `gpt-5-mini` model not available in most Azure regions

**Severity:** High  
**Phase:** Phase 3 — Deploy  
**File:** PLAN.md (Phase 3 AI Features, Phase 4 Deploy)

**Problem:** The PLAN.md specifies `gpt-5-mini` as the primary model with `gpt-4o` as fallback. However, `gpt-5-mini` with version `2025-01-27` is not available in common Azure regions like `westus3`. The deployment fails with `DeploymentModelNotSupported`. The PLAN.md Known Deployment Gotchas section (#7) mentions this but the default should be a model that actually works.

**Fix:** Kept `gpt-5-mini` as the default but added `gpt-4.1` as the documented fallback in PLAN.md model config and Known Deployment Gotchas. Bicep should be regenerated with the available model for the chosen region.

**Status:** ✅ Fixed in PLAN.md.

## Issue 5: AVM `web/site` module strips blob container URI in `functionAppConfig`

**Severity:** High  
**Phase:** Phase 3 — Deploy

**Problem:** The AVM `web/site` module (v0.15.1) does not correctly pass through the full blob container URI for `functionAppConfig.deployment.storage.value`. A value like `https://storage.blob.core.windows.net/deploymentpackage` gets stored as just `deploymentpackage`, causing `azd deploy` to fail with `InaccessibleStorageException: Blob Container Uri is malformed`.

**Fix:** After `azd provision`, manually patch the Function App via REST API to set the correct full URI. Alternatively, wait ~30 seconds for eventual consistency and retry `azd deploy`. The PLAN.md should mention this potential issue.

**Status:** ✅ Documented in PLAN.md Known Deployment Gotchas (#9).

## Issue 6: Post-provision script uses unsupported `--access-token` flag

**Severity:** Medium  
**Phase:** Phase 3 — Deploy  
**File:** PLAN.md (Post-Provision section)

**Problem:** The PLAN.md post-provision script uses `--access-token` flag with `sqlcmd`, but the go-sqlcmd version (installed via `brew install sqlcmd`) doesn't support that flag. It supports `--authentication-method ActiveDirectoryAzCli` instead.

**Fix:** Updated post-provision approach to use `sqlcmd -S ... --authentication-method ActiveDirectoryAzCli` which works with the go-sqlcmd version. PLAN.md should document both approaches.

**Status:** ✅ Fixed in PLAN.md.

## Issue 7: SQL firewall blocks local post-provision script

**Severity:** Medium  
**Phase:** Phase 3 — Deploy

**Problem:** The Bicep template only creates an `AllowAllWindowsAzureIps` firewall rule (`0.0.0.0`), which allows Azure services but not the developer's local machine. The post-provision script that sets up managed identity and schema runs from the developer's machine and gets blocked.

**Fix:** Need to add a firewall rule for the developer's IP before running the post-provision script: `az sql server firewall-rule create --server <name> --resource-group <rg> --name MyIP --start-ip-address <ip> --end-ip-address <ip>`. PLAN.md should document this prerequisite step.

**Status:** ✅ Fixed in PLAN.md (post-provision script + Known Deployment Gotchas #10).
