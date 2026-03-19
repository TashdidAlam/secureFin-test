# =============================================================================
# Staging Environment - Main Configuration
# =============================================================================
# WHY: Staging mirrors production as closely as possible. Same resource groups,
# same module structure, same tagging. The ONLY differences should be in
# tfvars (e.g., smaller SKUs, fewer replicas).
# =============================================================================

# ---------------------------------------------------------------------------
# Tags Module
# ---------------------------------------------------------------------------
module "tags" {
  source = "../../modules/tags"

  project     = var.project
  environment = var.environment
}

# ---------------------------------------------------------------------------
# Resource Group: Core Services
# ---------------------------------------------------------------------------
module "rg_core" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-core-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: AKS Cluster
# ---------------------------------------------------------------------------
module "rg_aks" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-aks-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: Data Services
# ---------------------------------------------------------------------------
module "rg_data" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-data-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}
