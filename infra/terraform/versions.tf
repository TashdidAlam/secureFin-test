# =============================================================================
# SecureFin Platform - Terraform & Provider Versions
# =============================================================================
# WHY pin versions: Version drift between environments is the #1 cause of
# "works in dev, breaks in prod" issues. Pinning ensures identical behavior.
#
# WHY >= 1.5.0: Terraform 1.5+ introduced the `check` block, improved
# import workflows, and critical bug fixes for Azure backends.
#
# WHY ~> 4.0: AzureRM 4.x is the latest stable major version. It removes
# deprecated arguments (managed, enforce), renames others for consistency
# (enable_auto_scaling → auto_scaling_enabled), and uses the latest Azure
# API versions with full GA support for OIDC, Workload Identity, and AKS.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
