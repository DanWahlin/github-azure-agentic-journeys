# SmartTodo — Issues Log

Sanitized issues encountered during journey-runner executions. No secrets included.

---

## Run 2026-07-16 · env jr-smarttodo-0716 · westus · Node.js/TypeScript · Linux host

### Issue 1 — Postprovision hook failed: `sqlcmd` not installed
- **Phase:** Phase 3 (Deploy) — postprovision
- **Error:** `azd provision` post hook exited 1 with `ERROR: sqlcmd is not installed.`
  `infra/hooks/postprovision.sh` requires go-sqlcmd, absent on this Linux host; installing
  system packages was not permitted.
- **Diagnosis:** Without `sqlcmd` the hook cannot create the managed-identity DB user or apply
  schema + seed. `az sql db execute` does not exist.
- **Fix / workaround:** Initialized the DB with a safe available mechanism — the same Node
  `mssql`/tedious driver the app uses, authenticated via an Azure AD access token
  (`az account get-access-token --resource https://database.windows.net`; deploying user is the
  SQL Entra admin). Created the Function App MI user + roles and applied the exact
  `postprovision-schema.sql`. No secrets used. The faithful `sqlcmd` hook stays wired in
  `azure.yaml` per PLAN.md.
- **Final status:** RESOLVED via workaround; DB initialized (3 todos, 7 steps); live API passed.

### Issue 2 — SQL connection timeout from dev host (redirect ports blocked)
- **Phase:** Phase 3 (Deploy) — DB init from dev host
- **Error:** `Failed to connect to <server>:1433 in 15000ms` despite a host-IP firewall rule and
  reachable TCP 1433.
- **Diagnosis:** Azure SQL default **Redirect** policy needs outbound ports 11000–11999, which
  are blocked in this environment; the post-login redirect timed out.
- **Fix / workaround:** `az sql server conn-policy update --connection-type Proxy` so all traffic
  stays on 1433. In-Azure Function App traffic is unaffected.
- **Final status:** RESOLVED.

### Issue 3 — Azure Functions Core Tools (`func`) not installed
- **Phase:** Phase 1 (local) / verification
- **Error:** `func: command not found`.
- **Diagnosis:** Core Tools not installed; system installs not permitted.
- **Fix / workaround:** Skipped local `func start` per run instructions; verified API against the
  live Azure deployment via curl. Local `tsc` build and `node --test` unit tests still ran.
- **Final status:** DOCUMENTED / expected; no impact on deployment or verification.

### Note — Xcode/iOS Simulator not run (Linux)
- Full SwiftUI source generated and statically verified (file tree + Codable field names and
  status enum raw values match the API JSON contract). Xcode/simulator not attempted on Linux,
  per run instructions.

## 2026-07-17 — Repository remediation

- `sqlcmd`, Azure Functions Core Tools v4, Azurite, Node.js 24 LTS, and platform-gated Xcode/Docker requirements are explicit with Windows, macOS, and Linux installation guidance.
- `postprovision.mjs` now owns prerequisite checks, argument-safe `sqlcmd` execution, temporary firewall cleanup, Redirect-to-Proxy handling, and original-policy restoration in `finally`.
- The README and PLAN document Azure SQL Redirect ports 11000–11999 and the AMD64-only local SQL Server container.
- Windows and Linux use generated Swift-source inspection plus backend build, deployment, and API verification; iOS execution remains macOS/Xcode-only.
- **Status:** Documentation and skill defects resolved. Full macOS and Windows live execution remains unclaimed.
