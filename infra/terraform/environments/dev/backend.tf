# =============================================================================
# Dev Environment - Backend Configuration
# =============================================================================
# WHY azurerm backend: Native support for Azure Blob Storage with built-in
# state locking via blob leases. No external lock table needed (unlike S3+DynamoDB).
#
# WHY use_oidc = true: Backend operations (reading/writing state) also use
# Workload Identity. No storage account keys are ever used.
#
# WHY use_azuread_auth = true: Forces all storage operations through Azure AD
# RBAC instead of shared key authentication. The storage account must have
# shared_access_key_enabled = false for a zero-shared-key architecture.
#
# WHY backend.hcl: The backend values (storage account name, resource group,
# container) are passed at init time via:
#   terraform init -backend-config=backend.hcl
# The storage account is pre-created in a dedicated resource group, separate
# from the application infrastructure managed by this Terraform code.
# =============================================================================

terraform {
  backend "azurerm" {
    # WHY: OIDC for state operations — consistent with the provider auth model
    use_oidc = true

    # WHY: Azure AD auth eliminates shared key usage for blob operations
    use_azuread_auth = true

    # WHY: Environment-specific state file key prevents state collision
    # across dev/staging/production in the same storage container
    key = "dev.terraform.tfstate"

    # NOTE: resource_group_name, storage_account_name, and container_name
    # are provided via backend.hcl at init time
  }
}
