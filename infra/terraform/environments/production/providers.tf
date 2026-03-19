# =============================================================================
# Production Environment - Provider Configuration
# =============================================================================
# WHY: Production MUST use OIDC — this is non-negotiable for fintech.
# The production subscription should be a completely separate Azure
# subscription with its own RBAC boundary for maximum isolation.
# =============================================================================

provider "azurerm" {
  features {}

  use_oidc = true

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
}
