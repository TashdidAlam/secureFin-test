# =============================================================================
# Dev Environment - Backend Configuration Values
# =============================================================================
# USAGE: terraform init -backend-config=backend.hcl
#
# WHY external .hcl file: Backend configuration values are environment-
# specific and should not be hardcoded in backend.tf. Using -backend-config
# allows the CI/CD pipeline to inject the correct values per environment.
#
# PREREQUISITE: The storage account and container must be created BEFORE
# running this pipeline. The state backend lives in a dedicated resource
# group, separate from the application infrastructure.
#
# SECURITY: Enable Azure AD RBAC-only access on the storage account
# (shared_access_key_enabled = false) and grant the CI/CD service principal
# the "Storage Blob Data Contributor" role.
# =============================================================================

resource_group_name  = "rg-securefin-tfstate"
storage_account_name = "tashdidstatebackup68"
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
