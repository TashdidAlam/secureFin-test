# =============================================================================
# Staging Environment - Provider Configuration
# =============================================================================
# WHY: Identical provider config to dev/production. OIDC authentication
# ensures staging uses the same zero-secret model. The subscription_id
# may differ if staging uses a separate Azure subscription (recommended
# for blast radius isolation in fintech).
# =============================================================================

provider "azurerm" {
  features {}

  use_oidc = true

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
}
