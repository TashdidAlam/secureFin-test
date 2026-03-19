# =============================================================================
# Staging Environment - Backend Configuration
# =============================================================================
# WHY: Staging uses the same state storage infrastructure as dev but with a
# different state file key. This ensures state isolation between environments
# while reusing the CMK-encrypted storage account.
#
# SECURITY: CMK encryption is enforced at the storage account level.
# All state files are encrypted with the Customer Managed Key automatically.
# =============================================================================

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
    key              = "staging.terraform.tfstate"
  }
}
