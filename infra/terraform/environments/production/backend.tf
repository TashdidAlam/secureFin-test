# =============================================================================
# Production Environment - Backend Configuration
# =============================================================================
# WHY: Production state is the most critical. The state key
# "production.terraform.tfstate" isolates prod state from dev/staging
# in the shared storage container within the dedicated state resource group.
# =============================================================================

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
    key              = "production.terraform.tfstate"
  }
}
