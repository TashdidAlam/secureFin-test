# =============================================================================
# Production Environment - Backend Configuration Values
# =============================================================================
# USAGE: terraform init -backend-config=backend.hcl
#
# PREREQUISITE: The storage account and container must be created BEFORE
# running this pipeline. All environments share the same storage account
# but use different state file keys for isolation.
#
# SECURITY: Enable Azure AD RBAC-only access on the storage account
# (shared_access_key_enabled = false) and grant the CI/CD service principal
# the "Storage Blob Data Contributor" role.
# =============================================================================

resource_group_name  = "rg-securefin-tfstate"
storage_account_name = "tashdidstatebackup68"
container_name       = "tfstate"
key                  = "production.terraform.tfstate"
