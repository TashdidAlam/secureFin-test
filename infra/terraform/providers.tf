# =============================================================================
# SecureFin Platform - Provider Configuration
# =============================================================================
# Authentication is handled entirely via ARM_* environment variables:
#   ARM_USE_OIDC          → Enables OIDC (Workload Identity) auth
#   ARM_CLIENT_ID         → App Registration client ID
#   ARM_TENANT_ID         → Azure AD tenant ID
#   ARM_SUBSCRIPTION_ID   → Target subscription
#
# In CI/CD, these are set from GitHub repository variables.
# For local development, use `az login` (no env vars needed).
# =============================================================================

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  use_oidc        = true
}
