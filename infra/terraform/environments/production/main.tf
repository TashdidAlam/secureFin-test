# =============================================================================
# Production Environment - Main Configuration
# =============================================================================
# WHY: Production configuration is structurally identical to staging.
# Differences are expressed ONLY through tfvars (SKU sizes, replica counts,
# etc.). This "structural parity" principle ensures that what's tested in
# staging is exactly what runs in production.
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
