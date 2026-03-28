# =============================================================================
# SecureFin Platform - Provider Configuration
# =============================================================================
# Authentication uses OIDC (Workload Identity Federation) in CI/CD.
# Azure identity values are declared as variables with defaults in variables.tf
# and can be overridden via ARM_* env vars or -var flags.
# =============================================================================

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = true

  # resource_provider_registrations = "none" replaces skip_provider_registration in 4.x
  resource_provider_registrations = "none"
}
