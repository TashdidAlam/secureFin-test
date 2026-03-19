# =============================================================================
# TFLint Configuration — SecureFin Platform
# =============================================================================
# PURPOSE: Enforce Terraform best practices and Azure-specific rules beyond
# what `terraform validate` catches. TFLint detects:
#   - Missing provider version constraints
#   - Deprecated syntax and resource attributes
#   - Azure-specific misconfigurations (via azurerm ruleset)
#   - Naming convention violations
#   - Unused declarations
# =============================================================================

# ---------------------------------------------------------------------------
# Core Terraform Ruleset (bundled with TFLint)
# ---------------------------------------------------------------------------
# WHY: Catches Terraform language-level issues like missing required_providers
# version constraints, deprecated interpolation syntax, and unused variables.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# ---------------------------------------------------------------------------
# Azure Provider Ruleset
# ---------------------------------------------------------------------------
# WHY: Azure-specific rules catch misconfigurations that Terraform validate
# misses — invalid VM sizes, deprecated SKUs, unsupported regions, etc.
# This is CRITICAL for a fintech platform where misconfigured resources
# can cause compliance failures or unexpected costs.
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
