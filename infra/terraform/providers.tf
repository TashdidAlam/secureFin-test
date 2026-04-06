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

  # "none" alone caused 404s because Microsoft.Network wasn't registered.
  # Explicitly register only the providers SecureFin needs.
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Network",
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.ManagedIdentity",
    "Microsoft.Authorization",
    "Microsoft.Resources",
    "Microsoft.OperationalInsights",
  ]
}
