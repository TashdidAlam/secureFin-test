# =============================================================================
# SecureFin Platform - Backend Configuration
# =============================================================================
# All backend values (resource_group_name, storage_account_name,
# container_name, key) are provided at init time via:
#   terraform init -backend-config=environments/{env}/backend.hcl
#
# WHY use_oidc: Backend operations (reading/writing state) also use
# Workload Identity. No storage account keys are ever used.
#
# WHY use_azuread_auth: Forces all storage operations through Azure AD
# RBAC instead of shared key authentication.
# =============================================================================

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}
