# =============================================================================
# Staging Environment - Backend Configuration Values
# =============================================================================
# USAGE: terraform init -backend-config=backend.hcl
#
# NOTE: Replace with outputs from the bootstrap layer.
# SECURITY: CMK encryption is enforced at the storage account level.
# =============================================================================

resource_group_name  = "rg-securefin-state-eastus2"
storage_account_name = "stsecurefintfstateXXXX"
container_name       = "tfstate"
