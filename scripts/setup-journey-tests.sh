#!/usr/bin/env bash
#
# Setup script for Journey E2E Test Harness
#
# Configures GitHub repository secrets and variables required by the
# journey-e2e-test agentic workflow. Uses the GitHub CLI (gh).
#
# Usage:
#   ./scripts/setup-journey-tests.sh
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

# Try to auto-detect from current az login
if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
  DEFAULT_SUB_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
  DEFAULT_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
  info "Detected Azure subscription: ${DEFAULT_SUB_ID:0:8}..."
  info "Detected Azure tenant: ${DEFAULT_TENANT_ID:0:8}..."
else
  DEFAULT_SUB_ID=""
  DEFAULT_TENANT_ID=""
  warn "Azure CLI not authenticated — you'll need to enter values manually"
fi

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

read_value "Azure Subscription ID" "$DEFAULT_SUB_ID" "AZURE_SUBSCRIPTION_ID"
read_value "Azure Tenant ID" "$DEFAULT_TENANT_ID" "AZURE_TENANT_ID"
read_value "Azure Client ID (Service Principal App ID)" "" "AZURE_CLIENT_ID"

echo -en "  Azure Client Secret (Service Principal Secret): "
read -rs AZURE_CLIENT_SECRET
echo ""

echo -en "  Copilot GitHub Token (PAT with copilot scope): "
read -rs COPILOT_GITHUB_TOKEN
echo ""

# Validate we have all values
MISSING=0
for var in AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET COPILOT_GITHUB_TOKEN; do
  if [[ -z "${!var}" ]]; then
    error "Missing required value: $var"
    MISSING=1
  fi
done

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

echo -n "$COPILOT_GITHUB_TOKEN" | gh secret set COPILOT_GITHUB_TOKEN --repo "$REPO"
info "COPILOT_GITHUB_TOKEN"

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
