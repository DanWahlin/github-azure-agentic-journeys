#!/usr/bin/env bash
# Post-provision hook for SmartTodo.
# Grants the Function App's managed identity access to Azure SQL and applies
# the schema + seed data. Wired into azure.yaml as hooks.postprovision and
# runs automatically after `azd provision`. Requires: az (logged in), sqlcmd
# (go-sqlcmd: `brew install sqlcmd` on macOS), and the deploying user set as
# Microsoft Entra admin on the SQL server (done in Bicep).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v sqlcmd >/dev/null 2>&1; then
  echo "ERROR: sqlcmd not found. Install it (macOS: brew install sqlcmd) and re-run:" >&2
  echo "  ./infra/hooks/postprovision.sh" >&2
  exit 1
fi

SQL_SERVER=$(azd env get-value SQL_SERVER_NAME)
SQL_DB=$(azd env get-value SQL_DATABASE_NAME)
FUNC_APP=$(azd env get-value FUNCTION_APP_NAME)
RG=$(azd env get-value RESOURCE_GROUP_NAME)

# SQL_SERVER_NAME may be the short name or the FQDN — normalize both forms.
SQL_SERVER_SHORT=${SQL_SERVER%.database.windows.net}
SQL_FQDN="${SQL_SERVER_SHORT}.database.windows.net"

# sqlcmd runs from this machine, so the SQL firewall needs the client IP.
# "Allow Azure services" is not enough for local connections.
MY_IP=$(curl -s https://api.ipify.org)
echo "Adding temporary SQL firewall rule for ${MY_IP}..."
az sql server firewall-rule create \
  --resource-group "$RG" --server "$SQL_SERVER_SHORT" \
  --name PostProvisionClientIP \
  --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" >/dev/null

cleanup() {
  echo "Removing temporary SQL firewall rule..."
  az sql server firewall-rule delete \
    --resource-group "$RG" --server "$SQL_SERVER_SHORT" \
    --name PostProvisionClientIP >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Creating managed identity database user for ${FUNC_APP}..."
sqlcmd -S "$SQL_FQDN" -d "$SQL_DB" \
  --authentication-method ActiveDirectoryAzCli \
  -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '${FUNC_APP}') CREATE USER [${FUNC_APP}] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [${FUNC_APP}]; ALTER ROLE db_datawriter ADD MEMBER [${FUNC_APP}]; ALTER ROLE db_ddladmin ADD MEMBER [${FUNC_APP}];"

echo "Applying schema and seed data..."
sqlcmd -S "$SQL_FQDN" -d "$SQL_DB" \
  --authentication-method ActiveDirectoryAzCli \
  -i "${SCRIPT_DIR}/postprovision-schema.sql"

echo "Post-provision SQL setup complete."
