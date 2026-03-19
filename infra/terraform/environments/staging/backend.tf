# =============================================================================
# Staging Environment - Backend Configuration
# =============================================================================
# WHY: Staging uses the same pre-created state storage account as dev but
# with a different state file key. This ensures state isolation between
# environments while sharing a single storage account in the dedicated
# state resource group.
# =============================================================================

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
    key              = "staging.terraform.tfstate"
  }
}
