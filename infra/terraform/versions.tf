# =============================================================================
# SecureFin Platform - Terraform & Provider Versions
# =============================================================================
# WHY pin versions: Version drift between environments is the #1 cause of
# "works in dev, breaks in prod" issues. Pinning ensures identical behavior.
#
# WHY >= 1.5.0: Terraform 1.5+ introduced the `check` block, improved
# import workflows, and critical bug fixes for Azure backends.
#
# WHY ~> 3.80.0: Pessimistic constraint allows patch updates (3.80.x) but
# prevents breaking minor version changes. AzureRM 3.80+ includes critical
# fixes for OIDC authentication and Key Vault RBAC.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80.0"
    }
  }
}
