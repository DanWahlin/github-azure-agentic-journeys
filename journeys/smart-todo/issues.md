# SmartTodo Journey — Issues

## Issue: clean non-interactive `azd up` omits required Entra principal login

**Severity:** Medium — provisioning cannot start with `--no-prompt`.

**Discovered:** solution predictability run `sol-smarttodo-0717`, 2026-07-17

**Status:** Resolved, integrated into source guidance, and verified from a brand-new solution environment.

### Observed behavior

A fresh environment had the subscription, location, principal object ID, and SQL password configured. `azd up --no-prompt` stopped before creating resources:

```text
Missing required inputs:
- principalLogin
  Environment variable: AZURE_PRINCIPAL_LOGIN
```

The generated `infra/main.parameters.json` requires:

- `AZURE_PRINCIPAL_ID`
- `AZURE_PRINCIPAL_LOGIN`
- `AZURE_PRINCIPAL_TYPE`

The SmartTodo README/PLAN and shared skills now tell a clean runner how to resolve and set the complete group.

### Source integration

The SmartTodo README/PLAN and shared runner/template guidance now require a cross-platform preflight that resolves user versus service-principal identity explicitly, persists all three values with `azd env set`, and reports every missing value before provisioning begins without printing tokens or secrets.

---

## Issue: Foundry model deployment can race the parent account

**Severity:** High — Azure provisioning creates several billable resources, then fails with `RequestConflict`.

**Status:** Resolved, integrated into source guidance, and verified from a brand-new solution environment.

### Observed behavior

The model child deployment and account were emitted in the same resource module. Azure rejected an operation against the account because its provisioning state was not yet terminal.

### Source integration

Source guidance now requires serialized Foundry account and model deployment stages when raw resources are used. The verified solution uses a nested Bicep module for the model and passes the created account name into it.

---

## Issue: generated SQL firewall-rule name contains an Azure reserved word

**Severity:** Medium — `azd` validation explicitly states that deployment will fail.

**Status:** Resolved, integrated into source guidance, and verified from a brand-new solution environment.

### Observed behavior

The rule name `AllowAllWindowsAzureIps` contains the reserved word `WINDOWS`.

### Source integration

Source guidance now requires a neutral rule name such as `AllowAzureServices` while preserving the `0.0.0.0` start/end addresses required for Azure-services access. The fresh run validated without the reserved-name warning and created the renamed rule successfully.
