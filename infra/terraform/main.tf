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

# ---------------------------------------------------------------------------
# User-Assigned Managed Identity for AKS Cluster
# ---------------------------------------------------------------------------
# WHY created at root (not inside AKS module): Custom private DNS zone
# requires the AKS identity to have "Private DNS Zone Contributor" role
# BEFORE the cluster is provisioned. By creating the identity at root level,
# we can: (1) create identity → (2) grant RBAC → (3) pass to AKS module.
# This breaks the circular dependency that would occur if the identity were
# inside the AKS module.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "id-aks-${var.project}-${var.environment}"
  resource_group_name = module.rg_aks.name
  location            = module.rg_aks.location
  tags                = module.tags.tags
}

module "aks" {
  source = "./modules/aks"

  resource_group_name = module.rg_aks.name
  location            = module.rg_aks.location
  environment         = var.environment
  project             = var.project
  tags                = module.tags.tags
  aks_subnet_id       = module.network.aks_subnet_id
  tenant_id           = var.tenant_id
  private_dns_zone_id = module.dns.aks_dns_zone_id
  aks_identity_id     = azurerm_user_assigned_identity.aks_identity.id

  depends_on = [
    azurerm_role_assignment.securefin_aks_network_role,
    azurerm_role_assignment.securefin_aks_dns_contributor
  ]
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
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# ---------------------------------------------------------------------------
# DNS: Private DNS Zones for services requiring private name resolution
# ---------------------------------------------------------------------------
# WHY: Creating our own private DNS zone instead of relying on AKS "System"
# mode gives us predictable zone names, full control over VNet links, and
# eliminates the GUID-prefix discovery hack. The zone is placed in rg_core
# as a shared networking resource.
#
# DEPENDENCY: Requires network module (env VNet ID) and bastion module
# (Bastion VNet ID) for VNet links used to resolve AKS API server.
# ---------------------------------------------------------------------------
module "dns" {
  source = "./modules/dns"

  resource_group_name     = module.rg_core.name
  location                = var.location
  environment             = var.environment
  tags                    = module.tags.tags
  env_vnet_id             = module.network.vnet_id
  bastion_vnet_id         = module.bastion.bastion_vnet_id
  enable_bastion_dns_link = true
}

# ---------------------------------------------------------------------------
# RBAC: Grant AKS cluster identity Private DNS Zone Contributor
# ---------------------------------------------------------------------------
# WHY: When using a custom private DNS zone, AKS needs to create/update
# DNS records for the API server private endpoint. Without this role,
# cluster provisioning fails because AKS can't register its API server IP.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "securefin_aks_dns_contributor" {
  scope                = module.dns.aks_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
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
#   Bastion VNet (10.2.0.0/16) ←── VNet Peering ──→ Env VNet (10.0.0.0/16)
#   ├── AzureBastionSubnet (10.2.0.0/26)
#   └── snet-jumpbox (10.2.1.0/27) ──kubectl──→ Private AKS API
#
# DNS: AKS private DNS zone links are handled by the dns module, which
# links the zone to both the env VNet and the Bastion VNet.
#
# COST: ~$155/mo total (1 Bastion + 1 VM) vs ~$155/env if per-environment
# ---------------------------------------------------------------------------

module "rg_bastion" {
  source = "./modules/resource-group"

  name     = "rg-${var.project}-bastion"
  location = var.location
  tags     = module.tags.tags
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
