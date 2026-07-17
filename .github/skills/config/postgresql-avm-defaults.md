# PostgreSQL AVM Module — Critical Configuration

The AVM PostgreSQL Flexible Server module (`br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2`) has defaults that break password-based applications. Apply **all** of these when deploying n8n, Superset, or any app using PostgreSQL with password auth.

## Required Params

```bicep
module postgresServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.15.2' = {
  params: {
    // ... name, location, tags, etc.
    publicNetworkAccess: 'Enabled'    // Default: Disabled — firewall rules silently ignored
    highAvailability: 'Disabled'      // Required for Burstable tier (Standard_B1ms)
    availabilityZone: -1              // No zone preference
    authConfig: {
      passwordAuth: 'Enabled'         // Default: Disabled (Entra-only)
      activeDirectoryAuth: 'Disabled'
    }
    administratorLogin: '<username>'
    administratorLoginPassword: '<password>'  // Pin via azd env, not newGuid()
    firewallRules: [
      { name: 'AllowAllAzureServices', startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
    ]
  }
}
```

## Why Each Setting Matters

| Setting | Default | Problem If Not Set |
|---------|---------|-------------------|
| `publicNetworkAccess` | `Disabled` | Firewall rules silently ignored — connection timeout |
| `authConfig.passwordAuth` | `Disabled` | "authentication failed" — only Entra ID accepted |
| `highAvailability` | May enable | "HANotSupportedForBurstableSkuWithMoreInfo" on Burstable tier |
| `administratorLoginPassword` via `newGuid()` | Regenerates each deploy | Password mismatch on redeploy — auth fails |

## Password Pinning

`newGuid()` generates a new password on every `azd up`. PostgreSQL keeps the original. Generate a cryptographically secure value with Node.js or the current platform's secure API, then pin it once with `azd env set POSTGRES_PASSWORD <generated-secret>`. Don't require OpenSSL or shell command substitution. See [`../../../docs/tool-installation.md`](../../../docs/tool-installation.md#secure-cross-platform-secret-generation).

Reference in `main.parameters.json`:
```json
{ "postgresPassword": { "value": "${POSTGRES_PASSWORD}" } }
```
