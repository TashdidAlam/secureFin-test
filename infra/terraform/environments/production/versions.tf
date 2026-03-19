# =============================================================================
# Production Environment - Terraform & Provider Versions
# =============================================================================
# WHY: Production uses the EXACT same version constraints. Any version
# difference between staging and production invalidates pre-production
# testing and introduces unquantifiable risk.
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
