# =============================================================================
# SecureFin Platform - Main Configuration
# =============================================================================
# All environments (dev, staging, production) share this single configuration.
# Environment-specific values are injected via tfvars files located at:
#   environments/{env}/{env}.tfvars
# =============================================================================

# ---------------------------------------------------------------------------
# Tags Module
# ---------------------------------------------------------------------------
# Centralized tagging ensures every resource carries the mandatory compliance
# tags (Project, Environment, Owner, CostCenter, ManagedBy).
module "tags" {
  source = "./modules/tags"

  project     = var.project
  environment = var.environment
}

# ---------------------------------------------------------------------------
# Resource Group: Core Services
# ---------------------------------------------------------------------------
# Core services (networking, DNS, shared components) are isolated in their
# own resource group for independent RBAC and lifecycle management.
module "rg_core" {
  source = "./modules/resource-group"

  name     = "rg-${var.project}-core-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: AKS Cluster
# ---------------------------------------------------------------------------
# AKS resources are isolated because AKS creates additional "MC_" resource
# groups automatically. Keeping the parent RG separate prevents permission
# bleed into core services.
module "rg_aks" {
  source = "./modules/resource-group"

  name     = "rg-${var.project}-aks-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Resource Group: Data Services
# ---------------------------------------------------------------------------
# Data resources have stricter compliance requirements in fintech (PCI-DSS).
# Isolating them in a dedicated RG allows tighter RBAC and compliance
# boundary enforcement.
module "rg_data" {
  source = "./modules/resource-group"

  name     = "rg-${var.project}-data-${var.environment}"
  location = var.location
  tags     = module.tags.tags
}
