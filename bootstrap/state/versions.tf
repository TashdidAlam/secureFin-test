# =============================================================================
# Bootstrap Layer - Terraform & Provider Versions
# =============================================================================
# WHY: The bootstrap layer is SEPARATE from the main infrastructure because it
# provisions the very resources that Terraform needs to store its own state
# (storage account, key vault for CMK encryption). This is a chicken-and-egg
# problem — you can't use remote state before the remote state backend exists.
#
# The bootstrap layer uses LOCAL state, which is committed or stored securely
# by the platform team. It is run once (or very rarely) and is not part of
# the CI/CD pipeline.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

# WHY use_oidc variable: Defaults to false for local CLI runs (uses az login).
# Set to true in CI/CD pipelines for OIDC/Workload Identity authentication.
provider "azurerm" {
  features {
    key_vault {
      # WHY: Prevent accidental purge of Key Vault during bootstrap destroy.
      # CMK keys are critical — purge protection ensures recovery.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }

  use_oidc        = var.use_oidc
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
}
