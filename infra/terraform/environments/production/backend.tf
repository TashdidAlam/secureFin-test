# =============================================================================
# Production Environment - Backend Configuration
# =============================================================================
# WHY: Production state is the most critical. The CMK-encrypted backend
# ensures state-at-rest encryption with organization-controlled keys.
# The state key "production.terraform.tfstate" isolates prod state from
# dev/staging in the shared storage container.
#
# SECURITY: CMK encryption is enforced at the storage account level.
# All state files are encrypted with the Customer Managed Key automatically.
# =============================================================================

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
    key              = "production.terraform.tfstate"
  }
}
