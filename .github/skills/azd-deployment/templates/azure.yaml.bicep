# Azure Developer CLI (azd) configuration for Bicep deployment
# Documentation: https://learn.microsoft.com/azure/developer/azure-developer-cli/

name: my-app-azure

# Use Bicep as the infrastructure provider
infra:
  provider: bicep
  path: infra

# Post-provision hooks run after infrastructure deployment
# Use for circular dependency resolution (e.g., WEBHOOK_URL)
hooks:
  postprovision:
    posix:
      shell: sh
      run: ./infra/hooks/postprovision.sh
    windows:
      shell: pwsh
      run: ./infra/hooks/postprovision.ps1

# NOTE: No services section when using pre-built Docker images
# The container image is specified directly in Bicep (containerImage parameter)
#
# Only add services section if building from source:
# services:
#   web:
#     project: ./src
#     language: python
#     host: containerapp
