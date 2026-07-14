#!/usr/bin/env bash
#
# Setup script for Journey E2E Test Harness
#
# Configures GitHub repository secrets and variables required by the
# journey-e2e-test agentic workflow. Uses the GitHub CLI (gh).
#
# Usage:
#   ./.github/scripts/setup-journey-tests.sh
#
# Prerequisites:
#   - gh CLI authenticated (gh auth login)
#   - Azure CLI authenticated (az login) — to auto-detect values
#   - Repository context (run from repo root or set GH_REPO)
#

set -euo pipefail

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

info()  { echo -e "${GREEN}✓${RESET} $1"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $1"; }
error() { echo -e "${RED}✗${RESET} $1"; }
header(){ echo -e "\n${BOLD}$1${RESET}"; }

# ── Pre-flight checks ──────────────────────────────────────────────

header "Pre-flight checks"

if ! command -v gh &>/dev/null; then
  error "GitHub CLI (gh) is required. Install: https://cli.github.com/"
  exit 1
fi
info "gh CLI found: $(gh --version | head -1)"

if ! gh auth status &>/dev/null; then
  error "Not authenticated with GitHub CLI. Run: gh auth login"
  exit 1
fi
info "gh authenticated"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [[ -z "$REPO" ]]; then
  error "Could not detect repository. Run from repo root or set GH_REPO."
  exit 1
fi
info "Repository: $REPO"

# ── Collect Azure values ───────────────────────────────────────────

header "Azure configuration"

if ! command -v az &>/dev/null; then
  error "Azure CLI (az) is required to detect or create the service principal. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

if ! az account show &>/dev/null 2>&1; then
  error "Azure CLI is not authenticated. Run: az login"
  exit 1
fi

DEFAULT_SUB_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
DEFAULT_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
info "Detected Azure subscription: ${DEFAULT_SUB_ID:0:8}..."
info "Detected Azure tenant: ${DEFAULT_TENANT_ID:0:8}..."

# Prompt for each value with auto-detected defaults
read_value() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"
  
  if [[ -n "$default" ]]; then
    echo -en "  ${prompt} ${DIM}[${default:0:8}...]${RESET}: "
  else
    echo -en "  ${prompt}: "
  fi
  
  read -r input
  if [[ -z "$input" ]]; then
    eval "$var_name='$default'"
  else
    eval "$var_name='$input'"
  fi
}

read_secret_value() {
  local prompt="$1"
  local var_name="$2"
  local existing_value="${!var_name:-}"

  if [[ -n "$existing_value" ]]; then
    echo -en "  ${prompt} ${DIM}[from environment]${RESET}: "
  else
    echo -en "  ${prompt}: "
  fi

  read -rs input
  echo ""
  if [[ -z "$input" && -n "$existing_value" ]]; then
    eval "$var_name='$existing_value'"
  else
    eval "$var_name='$input'"
  fi
}

read_value "Azure Subscription ID" "$DEFAULT_SUB_ID" "AZURE_SUBSCRIPTION_ID"
read_value "Azure Tenant ID" "$DEFAULT_TENANT_ID" "AZURE_TENANT_ID"

SP_NAME="github-azure-agentic-journeys-e2e"
ROLE_NAME="Contributor"
SCOPE="/subscriptions/$AZURE_SUBSCRIPTION_ID"

header "Azure service principal"
EXISTING_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING_APP_ID" ]]; then
  info "Found existing service principal: $SP_NAME (${EXISTING_APP_ID:0:8}...)"
  AZURE_CLIENT_ID="$EXISTING_APP_ID"
  warn "Azure does not expose existing client secret values. Creating a fresh secret for this workflow."
  SP_SECRET_JSON=$(az ad app credential reset --id "$AZURE_CLIENT_ID" --display-name "github-actions-journey-e2e" --years 1 -o json)
  AZURE_CLIENT_SECRET=$(echo "$SP_SECRET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
else
  warn "Service principal not found: $SP_NAME"
  echo -en "  Create it now with $ROLE_NAME on subscription ${AZURE_SUBSCRIPTION_ID:0:8}...? [Y/n]: "
  read -r CREATE_SP
  if [[ "$CREATE_SP" =~ ^[Nn]$ ]]; then
    read_value "Azure Client ID (Service Principal App ID)" "" "AZURE_CLIENT_ID"
    read_secret_value "Azure Client Secret (Service Principal Secret)" "AZURE_CLIENT_SECRET"
  else
    info "Creating service principal: $SP_NAME"
    SP_JSON=$(az ad sp create-for-rbac \
      --name "$SP_NAME" \
      --role "$ROLE_NAME" \
      --scopes "$SCOPE" \
      --years 1 \
      -o json)
    AZURE_CLIENT_ID=$(echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')
    AZURE_CLIENT_SECRET=$(echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
    CREATED_TENANT_ID=$(echo "$SP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tenant", ""))')
    if [[ -n "$CREATED_TENANT_ID" ]]; then
      AZURE_TENANT_ID="$CREATED_TENANT_ID"
    fi
    info "Created service principal: $SP_NAME (${AZURE_CLIENT_ID:0:8}...)"
  fi
fi

echo -en "  Copilot GitHub Token (PAT with copilot scope; press Enter to keep existing repo secret if present): "
read -rs COPILOT_GITHUB_TOKEN
echo ""

HAS_EXISTING_COPILOT_SECRET=0
if gh secret list --repo "$REPO" | awk '{print $1}' | grep -qx "COPILOT_GITHUB_TOKEN"; then
  HAS_EXISTING_COPILOT_SECRET=1
fi

# Validate we have all values
MISSING=0
for var in AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET; do
  if [[ -z "${!var}" ]]; then
    error "Missing required value: $var"
    MISSING=1
  fi
done

if [[ -z "$COPILOT_GITHUB_TOKEN" && $HAS_EXISTING_COPILOT_SECRET -eq 0 ]]; then
  error "Missing required value: COPILOT_GITHUB_TOKEN"
  MISSING=1
fi

if [[ $MISSING -eq 1 ]]; then
  error "Cannot continue without all required values."
  exit 1
fi

# ── Set GitHub Variables (non-sensitive) ───────────────────────────

header "Setting GitHub repository variables"

gh variable set AZURE_CLIENT_ID      --body "$AZURE_CLIENT_ID"      --repo "$REPO"
info "AZURE_CLIENT_ID"

gh variable set AZURE_TENANT_ID      --body "$AZURE_TENANT_ID"      --repo "$REPO"
info "AZURE_TENANT_ID"

gh variable set AZURE_SUBSCRIPTION_ID --body "$AZURE_SUBSCRIPTION_ID" --repo "$REPO"
info "AZURE_SUBSCRIPTION_ID"

# ── Set GitHub Secrets (sensitive) ─────────────────────────────────

header "Setting GitHub repository secrets"

echo -n "$AZURE_CLIENT_SECRET" | gh secret set AZURE_CLIENT_SECRET --repo "$REPO"
info "AZURE_CLIENT_SECRET"

if [[ -n "$COPILOT_GITHUB_TOKEN" ]]; then
  echo -n "$COPILOT_GITHUB_TOKEN" | gh secret set COPILOT_GITHUB_TOKEN --repo "$REPO"
  info "COPILOT_GITHUB_TOKEN"
else
  info "COPILOT_GITHUB_TOKEN already exists; keeping existing secret"
fi

# ── Summary ────────────────────────────────────────────────────────

header "Setup complete!"

echo ""
echo -e "  ${BOLD}Variables set:${RESET}"
echo "    • AZURE_CLIENT_ID"
echo "    • AZURE_TENANT_ID"
echo "    • AZURE_SUBSCRIPTION_ID"
echo ""
echo -e "  ${BOLD}Secrets set:${RESET}"
echo "    • AZURE_CLIENT_SECRET"
echo "    • COPILOT_GITHUB_TOKEN"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "    1. Compile the agentic workflow:  gh aw compile"
echo "    2. Commit and push the changes"
echo "    3. Trigger manually:  gh aw run journey-e2e-test"
echo "       Or wait for the weekly schedule (Monday ~6:00 UTC)"
echo ""
echo -e "  ${BOLD}Verify setup:${RESET}"
echo "    gh variable list --repo $REPO"
echo "    gh secret list --repo $REPO"
echo ""
