# =============================================================================
# Dev Environment - Backend Configuration Values
# =============================================================================
# USAGE: terraform init -backend-config=backend.hcl
#
# WHY external .hcl file: Backend configuration values are environment-
# specific and should not be hardcoded in backend.tf. Using -backend-config
# allows the CI/CD pipeline to inject the correct values per environment.
#
# NOTE: Replace these values with the outputs from the bootstrap layer.
# After running bootstrap, use:
#   terraform -chdir=bootstrap/state output storage_account_name
#   terraform -chdir=bootstrap/state output resource_group_name
#
# SECURITY: CMK encryption is enforced at the storage account level.
# All state files are encrypted with the Customer Managed Key automatically.
# =============================================================================

resource_group_name  = "rg-securefin-state-eastus2"
storage_account_name = "stsecurefintfstateXXXX"
container_name       = "tfstate"
