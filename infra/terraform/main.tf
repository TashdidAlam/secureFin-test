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

# ===========================================================================
# MODULE 2 — Security & Compliance Infrastructure
# ===========================================================================
# The following modules build the secure compute platform on top of the
# resource group foundation. Dependency chain:
#   rg_core → network → aks → identity
# Terraform resolves this automatically via output → variable references.
# ===========================================================================

# ---------------------------------------------------------------------------
# Network: VNet, Subnets, NSG
# ---------------------------------------------------------------------------
# WHY in rg_core: Networking is a shared service — VNet, subnets, and NSGs
# are consumed by AKS, private endpoints, and future services (App Gateway,
# Azure Firewall). Placing them in the core RG ensures network lifecycle is
# independent of any single compute resource.
#
# DEPENDENCY: Requires rg_core to exist first (provides RG name + location).
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  resource_group_name = module.rg_core.name
  location            = module.rg_core.location
  environment         = var.environment
  project             = var.project
  tags                = module.tags.tags
}

# ---------------------------------------------------------------------------
# AKS: Private Kubernetes Cluster
# ---------------------------------------------------------------------------
# WHY in rg_aks: AKS creates a secondary "MC_" resource group for node VMs,
# disks, and load balancers. Isolating the parent AKS resource in its own RG
# keeps the MC_ resources separate from core networking and data services.
#
# DEPENDENCY: Requires network module for aks_subnet_id (Azure CNI places
# nodes and pods in this subnet).
# ---------------------------------------------------------------------------
module "aks" {
  source = "./modules/aks"

  resource_group_name = module.rg_aks.name
  location            = module.rg_aks.location
  environment         = var.environment
  project             = var.project
  tags                = module.tags.tags
  aks_subnet_id       = module.network.aks_subnet_id
  tenant_id           = var.tenant_id
}

# ---------------------------------------------------------------------------
# Identity: Workload Identity Federation
# ---------------------------------------------------------------------------
# WHY in rg_core: The managed identity is a shared security resource, not
# tied to AKS compute lifecycle. If AKS is rebuilt, the identity (and its
# RBAC assignments to Key Vault, Storage, etc.) survives.
#
# DEPENDENCY: Requires AKS module for oidc_issuer_url (the trust anchor
# that Azure AD uses to validate Kubernetes service account tokens).
# ---------------------------------------------------------------------------
module "workload_identity" {
  source = "./modules/identity"

  resource_group_name      = module.rg_core.name
  location                 = module.rg_core.location
  environment              = var.environment
  project                  = var.project
  tags                     = module.tags.tags
  oidc_issuer_url          = module.aks.oidc_issuer_url
  k8s_namespace            = "default"
  k8s_service_account_name = "app-sa"
}

# ---------------------------------------------------------------------------
# RBAC: Grant AKS cluster identity Network Contributor on the AKS subnet
# ---------------------------------------------------------------------------
# WHY: AKS with Azure CNI needs permissions to manage IPs in the subnet
# (assign pod IPs, configure load balancer rules). Without this, AKS
# provisioning fails with "AuthorizationFailed" on the subnet resource.
#
# SCOPE: Limited to the AKS subnet only (not the entire VNet) — least
# privilege. The cluster identity can't modify other subnets or the VNet.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "securefin_aks_network_role" {
  scope                = module.network.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks.cluster_identity_principal_id
}

# ===========================================================================
# MODULE 3 — CI/CD & GitOps Infrastructure
# ===========================================================================
# ACR stores container images built by the CI pipeline. AKS pulls images
# from ACR via the kubelet managed identity (AcrPull role). No image pull
# secrets or admin credentials are needed.
# ===========================================================================

# ---------------------------------------------------------------------------
# ACR: Azure Container Registry
# ---------------------------------------------------------------------------
# WHY in rg_core: ACR is a shared service — it stores images consumed by
# AKS clusters across all environments. Placing it in the core RG ensures
# the registry survives cluster rebuilds and can serve multiple clusters.
#
# DEPENDENCY: No hard dependencies — ACR can be created in parallel with
# AKS. The AcrPull role assignment below is what links them.
# ---------------------------------------------------------------------------
module "acr" {
  source = "./modules/acr"

  resource_group_name = module.rg_core.name
  location            = module.rg_core.location
  environment         = var.environment
  project             = var.project
  tags                = module.tags.tags
}

# ---------------------------------------------------------------------------
# RBAC: Grant AKS kubelet identity AcrPull on the Container Registry
# ---------------------------------------------------------------------------
# WHY: AKS nodes use the kubelet managed identity (not the cluster identity)
# to pull container images. AcrPull is the least-privilege built-in role
# that grants read-only access to registry images.
#
# WHY kubelet identity (not cluster identity): The cluster identity manages
# Azure resources (VMs, disks, LBs). The kubelet identity is what actually
# runs on each node and pulls images. Using the correct identity follows
# the separation-of-duties principle.
#
# SCOPE: Limited to this specific ACR instance — the kubelet can't pull
# from any other registry in the subscription.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "securefin_aks_acr_pull" {
  scope                            = module.acr.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = module.aks.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}

# ---------------------------------------------------------------------------
# Bastion + Jump Box: Secure Admin Access to Private AKS
# ---------------------------------------------------------------------------
# WHY SEPARATE RG: Bastion is a shared admin tool — one Bastion serves ALL
# environments (dev/staging/prod) via VNet peering. Isolating it in its own
# RG allows independent lifecycle (destroy/recreate without affecting workloads)
# and prevents Azure Policy conflicts (e.g., "Deny Public IP" on core RG
# doesn't block Bastion's required public IP).
#
# ARCHITECTURE:
#   Bastion VNet (10.1.0.0/16) ←── VNet Peering ──→ Env VNet (10.0.0.0/16)
#   ├── AzureBastionSubnet (10.1.0.0/26)
#   └── snet-jumpbox (10.1.1.0/27) ──kubectl──→ Private AKS API
#
# COST: ~$155/mo total (1 Bastion + 1 VM) vs ~$155/env if per-environment
# ---------------------------------------------------------------------------

module "rg_bastion" {
  source = "./modules/resource-group"

  name     = "rg-${var.project}-bastion"
  location = var.location
  tags     = module.tags.tags
}

# ---------------------------------------------------------------------------
# Data source: Find the AKS private DNS zone in the MC_ resource group
# ---------------------------------------------------------------------------
# WHY: Private AKS in "System" mode creates a GUID-prefixed DNS zone
# (e.g., <guid>.privatelink.<region>.azmk8s.io) in the MC_ resource group.
# We can't hardcode the zone name, so we discover it dynamically by listing
# all private DNS zones in the MC_ RG and filtering by suffix.
# ---------------------------------------------------------------------------

data "azurerm_resources" "aks_dns_zones" {
  resource_group_name = module.aks.node_resource_group
  type                = "Microsoft.Network/privateDnsZones"
}

locals {
  # Filter to find the zone ending with privatelink.<region>.azmk8s.io
  aks_dns_zone_suffix = "privatelink.${var.location}.azmk8s.io"
  aks_dns_zone_name = one([
    for r in data.azurerm_resources.aks_dns_zones.resources :
    r.name if endswith(r.name, local.aks_dns_zone_suffix)
  ])
}

module "bastion" {
  source = "./modules/bastion"

  resource_group_name = module.rg_bastion.name
  location            = module.rg_bastion.location
  environment         = var.environment
  project             = var.project
  tags                = module.tags.tags

  # VNet peering to current environment's VNet
  env_vnet_id                  = module.network.vnet_id
  env_vnet_name                = module.network.vnet_name
  env_vnet_resource_group_name = module.rg_core.name

  # Private DNS zone link for AKS API server resolution
  aks_private_dns_zone_name           = local.aks_dns_zone_name != null ? local.aks_dns_zone_name : ""
  aks_private_dns_zone_resource_group = local.aks_dns_zone_name != null ? module.aks.node_resource_group : ""
}

# ---------------------------------------------------------------------------
# Azure Policy: Compliance Guardrails
# ---------------------------------------------------------------------------
# WHY: Azure Policy enforces organizational standards at the ARM layer —
# before resources are provisioned, not after. This is the "shift-left"
# equivalent for infrastructure: non-compliant deployments are rejected
# at creation time, not flagged retroactively.
#
# POLICIES ENFORCED:
#   1. Required tags — every resource must carry Project, Environment,
#      Owner, CostCenter, ManagedBy tags (PCI-DSS asset inventory)
#   2. Deny public IPs — zero public-facing resources (private AKS)
#   3. Allowed locations — data residency compliance (eastus2, eastus)
#
# SCOPE: Applied to all three resource groups (core, aks, data) so no
# resource can bypass the guardrails regardless of which RG it lands in.
# ---------------------------------------------------------------------------
module "policy" {
  source = "./modules/policy"

  environment = var.environment
  project     = var.project

  resource_group_ids = {
    core    = module.rg_core.id
    aks     = module.rg_aks.id
    data    = module.rg_data.id
    bastion = module.rg_bastion.id
  }
}
