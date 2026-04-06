# =============================================================================
# AKS Module - Main
# =============================================================================
# WHY: Defines a private, zero-trust AKS cluster with separated node pools,
# OIDC-based workload identity, and Azure CNI networking.
#
# ARCHITECTURE DECISIONS:
# ─────────────────────────
# 1. PRIVATE CLUSTER: API server has no public endpoint. kubectl access
#    requires VPN, bastion, or Azure CLI's `az aks command invoke`.
#    This eliminates the #1 AKS attack vector (public API exposure).
#
# 2. SYSTEM-ASSIGNED IDENTITY: The cluster itself uses a SystemAssigned
#    managed identity for Azure API calls (node provisioning, disk attach).
#    This is separate from workload identity (which pods use).
#
# 3. AZURE CNI: Every pod gets a real VNet IP. Required for:
#    - Kubernetes Network Policies (Azure implementation)
#    - Private endpoint connectivity (pods → PaaS via private IPs)
#    - NSG enforcement (Azure can see individual pod IPs)
#
# 4. SEPARATED NODE POOLS: System, user, and spot pools are isolated to
#    prevent workload interference and enable independent scaling.
#
# 5. RBAC + AAD: Azure AD integration with Kubernetes RBAC for audit-grade
#    authentication. Local accounts are disabled entirely.
# =============================================================================

# ---------------------------------------------------------------------------
# Log Analytics Workspace (Container Insights)
# ---------------------------------------------------------------------------
# WHY: Checkov CKV_AZURE_4 requires AKS logging to Azure Monitor.
# Uses PerGB2018 (default) pricing — ingestion from a single-node dev
# cluster is < 1 GB/day, well within free-tier allowance.
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "securefin_law" {
  name                = "law-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "securefin_aks" {
  name                = "aks-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.project}-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # ---------------------------------------------------------------------------
  # PRIVATE CLUSTER — NO PUBLIC API SERVER
  # ---------------------------------------------------------------------------
  # WHY: A public AKS API server is directly accessible from the internet.
  # In fintech, this is unacceptable. Private cluster ensures the API server
  # gets a private IP within the VNet, accessible only from:
  #   - Resources within the VNet (or peered VNets)
  #   - Azure Bastion / VPN Gateway
  #   - `az aks command invoke` (Azure CLI tunneling)
  #
  # TRADE-OFF: CI/CD pipelines can't reach the API directly. Solutions:
  #   - Use `az aks command invoke` in GitHub Actions
  #   - Deploy a self-hosted runner inside the VNet
  #   - Use Azure Arc-enabled Kubernetes (future module)
  # ---------------------------------------------------------------------------
  private_cluster_enabled = true

  # ---------------------------------------------------------------------------
  # UPGRADE CHANNEL (CKV_AZURE_171)
  # ---------------------------------------------------------------------------
  # WHY: Ensures the cluster receives automatic patch updates. "stable" applies
  # well-tested patches without jumping minor versions unexpectedly.
  # ---------------------------------------------------------------------------
  automatic_upgrade_channel = "stable"

  # ---------------------------------------------------------------------------
  # OIDC + WORKLOAD IDENTITY
  # ---------------------------------------------------------------------------
  # WHY oidc_issuer_enabled: AKS exposes an OIDC discovery endpoint that
  # Azure AD trusts. This allows Kubernetes service accounts to exchange
  # K8s tokens for Azure AD tokens — zero secrets.
  #
  # WHY workload_identity_enabled: Installs the Azure Workload Identity
  # webhook into kube-system. This webhook mutates pod specs to inject
  # the AZURE_* environment variables and projected token volumes that
  # Azure SDKs use for DefaultAzureCredential.
  #
  # FLOW: Pod → ServiceAccount → Projected Token → Azure AD → Access Token
  # ---------------------------------------------------------------------------
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ---------------------------------------------------------------------------
  # AZURE POLICY (Gatekeeper) — Kubernetes Admission Control
  # ---------------------------------------------------------------------------
  # WHY: Extends Azure Policy enforcement into the Kubernetes cluster. Without
  # this, Azure Policy only governs ARM-layer resources (RGs, VMs, NICs) but
  # NOT what runs inside the cluster (pods, deployments, services).
  #
  # WHAT IT DOES: Installs the Azure Policy addon (Gatekeeper) into AKS,
  # enabling built-in and custom policy definitions to enforce K8s constraints
  # (e.g., no privileged containers, require resource limits, ACR-only images).
  # ---------------------------------------------------------------------------
  azure_policy_enabled = true

  # ---------------------------------------------------------------------------
  # AZURE MONITOR — CONTAINER INSIGHTS (CKV_AZURE_4)
  # ---------------------------------------------------------------------------
  # WHY: Sends container logs, metrics, and inventory to Log Analytics.
  # Required for compliance (CKV_AZURE_4) and production observability.
  # Cost is minimal for a single-node dev cluster (< 1 GB/day ingestion).
  # ---------------------------------------------------------------------------
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.securefin_law.id
  }

  # ---------------------------------------------------------------------------
  # SECRETS STORE CSI DRIVER (CKV_AZURE_172)
  # ---------------------------------------------------------------------------
  # WHY: Enables mounting Azure Key Vault secrets as Kubernetes volumes.
  # secret_rotation_enabled ensures secrets auto-refresh without pod restarts.
  # The CSI driver addon itself is free — no extra Azure cost.
  # ---------------------------------------------------------------------------
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # ---------------------------------------------------------------------------
  # DISABLE LOCAL ACCOUNTS
  # ---------------------------------------------------------------------------
  # WHY: Local accounts use client certificates that bypass Azure AD. If
  # compromised, there's no audit trail and no way to revoke access without
  # rotating the entire cluster credential. Disabling them forces all
  # authentication through Azure AD + RBAC (auditable, revocable, MFA-capable).
  # ---------------------------------------------------------------------------
  local_account_disabled = true

  # ---------------------------------------------------------------------------
  # AZURE AD INTEGRATION + KUBERNETES RBAC
  # ---------------------------------------------------------------------------
  # WHY: Maps Azure AD identities (users, groups, service principals) to
  # Kubernetes RBAC roles. Enables:
  #   - SSO for kubectl (az login → kubectl get pods)
  #   - Audit trail in Azure AD sign-in logs
  #   - Conditional Access policies (MFA, device compliance)
  #   - azure_rbac_enabled = true: use Azure RBAC for K8s authorization
  # ---------------------------------------------------------------------------
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id
  }

  # ---------------------------------------------------------------------------
  # CLUSTER IDENTITY
  # ---------------------------------------------------------------------------
  # WHY SystemAssigned: The cluster needs an identity to manage Azure
  # resources (provision nodes, attach disks, configure LBs). SystemAssigned
  # is simpler than UserAssigned for the cluster itself — Azure manages the
  # lifecycle. Workload identity (for pods) uses a separate UserAssigned
  # identity created in the identity module.
  # ---------------------------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # DEFAULT NODE POOL (COMBINED SYSTEM + USER)
  # ---------------------------------------------------------------------------
  # COST TRADE-OFF: In production, system and user workloads should be on
  # separate pools (CriticalAddonsOnly taint). For the free-tier deployment,
  # we consolidate into a single pool to minimize VM costs (1 node instead
  # of 2+). System pods (CoreDNS, konnectivity) share the node with app
  # workloads. This is acceptable for dev/test but NOT for production.
  #
  # TO RESTORE PRODUCTION CONFIG:
  #   1. Add only_critical_addons_enabled = true here
  #   2. Re-add the user and spot node pool resources (see git history)
  # ---------------------------------------------------------------------------
  default_node_pool {
    name                 = "system"
    node_count           = var.system_node_count
    vm_size              = var.system_node_vm_size
    vnet_subnet_id       = var.aks_subnet_id
    os_disk_size_gb      = 30
    os_disk_type         = "Ephemeral"
    max_pods             = 50
    type                 = "VirtualMachineScaleSets"
    auto_scaling_enabled = false

    tags = var.tags
  }

  # ---------------------------------------------------------------------------
  # NETWORK PROFILE (AZURE CNI + AZURE NETWORK POLICY)
  # ---------------------------------------------------------------------------
  # WHY Azure CNI (not kubenet):
  #   - Pods get real VNet IPs (visible to NSGs, UDRs, Azure Firewall)
  #   - Required for Azure Network Policy enforcement
  #   - Required for Windows node pools (future)
  #   - Pod-to-pod traffic stays within VNet (no encapsulation overhead)
  #
  # WHY Azure Network Policy (not Calico):
  #   - Native Azure integration — managed by AKS, not a third-party addon
  #   - Works with Azure CNI's dataplane for per-pod enforcement
  #   - Sufficient for deny-by-default + namespace isolation patterns
  #   - Calico would be chosen only if we need egress policies or DNS policies
  #
  # WHY service_cidr 10.1.0.0/16: Must not overlap with VNet CIDR (10.0.0.0/16).
  # Kubernetes ClusterIP services use this range internally.
  # ---------------------------------------------------------------------------
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }
}

# ---------------------------------------------------------------------------
# NODE POOLS: User & Spot (REMOVED — FREE-TIER COST OPTIMIZATION)
# ---------------------------------------------------------------------------
# REMOVED FOR FREE-TIER: User and Spot node pools are removed to minimize
# VM costs. All workloads (system + user) run on the single default pool.
#
# PRODUCTION RESTORATION: Re-add these resources from git history when
# moving to a paid subscription. The production config should have:
#   - System pool: only_critical_addons_enabled = true, 1-2 nodes
#   - User pool: auto-scaling 1-3 nodes for application workloads
#   - Spot pool: auto-scaling 0-3 nodes for non-critical/batch workloads
# ---------------------------------------------------------------------------
