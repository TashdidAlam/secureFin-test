# =============================================================================
# Dev Environment - Provider Configuration
# =============================================================================
# WHY use_oidc: Azure Workload Identity Federation (OIDC) eliminates the need
# for stored secrets. The GitHub Actions runner exchanges a short-lived GitHub
# JWT token for an Azure AD token. Benefits:
#   - No client secrets to rotate or leak
#   - Tokens are scoped to a single workflow run
#   - Federated trust is auditable in Azure AD
#
# WHY variables for IDs: Subscription, tenant, and client IDs are passed as
# variables (set via CI/CD environment or tfvars), not hardcoded. This allows
# the same code to target different Azure environments.
# =============================================================================

provider "azurerm" {
  features {}

  # WHY: OIDC authentication — no secrets, no certificates, no keys
  use_oidc = true

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
}
