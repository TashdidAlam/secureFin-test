# =============================================================================
# Staging Environment - Terraform & Provider Versions
# =============================================================================
# WHY: Identical version constraints across all environments prevent drift.
# Staging is the final validation gate before production — version parity
# is essential for meaningful pre-production testing.
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
