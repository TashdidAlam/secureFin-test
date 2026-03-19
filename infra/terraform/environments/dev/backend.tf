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
# RBAC instead of shared key authentication. Combined with the storage account's
# shared_access_key_enabled = false (set in bootstrap), this creates a
# zero-shared-key architecture.
#
# WHY backend.hcl: Sensitive backend values (storage account name, resource
# group) are externalized to a .hcl file and passed at init time via:
#   terraform init -backend-config=backend.hcl
# This keeps the backend block clean and avoids hardcoding environment-specific
# values in tracked Terraform files.
#
# SECURITY NOTE: CMK encryption is enforced at the storage account level
# (configured in the bootstrap layer). Every blob written to this container
# — including tfstate files — is automatically encrypted with the Customer
# Managed Key. No additional configuration is needed here.
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
