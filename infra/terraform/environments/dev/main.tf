# =============================================================================
# Dev Environment - Main Configuration
# =============================================================================
# WHY: This is the root composition layer for the dev environment. It wires
# together reusable modules (tags, resource-group) with environment-specific
# values. Each environment (dev/staging/prod) has its own main.tf to allow
# independent configuration while sharing the same module contracts.
# =============================================================================

# ---------------------------------------------------------------------------
# Tags Module
# ---------------------------------------------------------------------------
# WHY: Centralized tagging ensures every resource in the dev environment
# carries the mandatory compliance tags. The tags module enforces the
# SecureFin tagging strategy.
module "tags" {
  source = "../../modules/tags"

  project     = var.project
  environment = var.environment
}

# ---------------------------------------------------------------------------
# Resource Group: Core Services
# ---------------------------------------------------------------------------
# WHY: Core services (networking, DNS, shared components) are isolated in
# their own resource group for independent RBAC and lifecycle management.
module "rg_core" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-core-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: AKS Cluster
# ---------------------------------------------------------------------------
# WHY: AKS resources (cluster, node pools, managed identities) are isolated
# because AKS creates additional "MC_" resource groups automatically. Keeping
# the parent RG separate prevents permission bleed into core services.
module "rg_aks" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-aks-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: Data Services
# ---------------------------------------------------------------------------
# WHY: Data resources (databases, caches, storage) have stricter compliance
# requirements in fintech (PCI-DSS scope). Isolating them in a dedicated RG
# allows tighter RBAC and compliance boundary enforcement.
module "rg_data" {
  source = "../../modules/resource-group"

  name     = "rg-${var.project}-data-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}
