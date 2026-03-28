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
# AKS Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
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
    managed            = true
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
  # DEFAULT NODE POOL (SYSTEM)
  # ---------------------------------------------------------------------------
  # WHY "System" mode: This pool is tainted with CriticalAddonsOnly, which
  # prevents user workloads from scheduling here. Only system components
  # (CoreDNS, konnectivity-agent, metrics-server, Azure CNI DaemonSets)
  # run on these nodes.
  #
  # WHY min 1 node: System pool cannot scale to 0 — the cluster needs at
  # least one node for DNS resolution and API server connectivity.
  #
  # WHY os_disk_type Managed: Default Managed disks with Premium SSD. For
  # system nodes, Ephemeral OS disks are an option but require VM sizes
  # with sufficient temp storage (not all B-series qualify).
  # ---------------------------------------------------------------------------
  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_node_vm_size
    vnet_subnet_id      = var.aks_subnet_id
    os_disk_size_gb     = 30
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = false

    # WHY: Only system-critical pods run here. User workloads are rejected
    # by the CriticalAddonsOnly taint (they schedule on the user pool).
    only_critical_addons_enabled = true

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
# NODE POOL: User Workloads
# ---------------------------------------------------------------------------
# WHY separate resource: azurerm_kubernetes_cluster_node_pool allows
# independent lifecycle management. The user pool can be scaled, upgraded,
# or replaced without touching the system pool.
#
# WHY auto-scaling: Fintech workloads have variable load (market hours vs.
# off-hours). Auto-scaling saves cost during low-traffic periods while
# ensuring capacity during peaks.
#
# WHY no taint: User pool accepts all workloads by default. Specific apps
# can use nodeSelector or tolerations for pool affinity if needed.
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 30
  enable_auto_scaling   = true
  min_count             = var.user_node_min_count
  max_count             = var.user_node_max_count
  mode                  = "User"
  tags                  = var.tags
}

# ---------------------------------------------------------------------------
# NODE POOL: Spot (Cost Optimization)
# ---------------------------------------------------------------------------
# WHY spot: Spot VMs cost 60-90% less than on-demand. Azure can evict them
# with 30 seconds notice when capacity is needed elsewhere.
#
# SUITABLE FOR: Dev/staging workloads, batch processing, CI runners,
# non-critical background jobs, load testing.
#
# NOT SUITABLE FOR: Production API servers, databases, stateful workloads
# that can't tolerate sudden eviction.
#
# SCHEDULING: The kubernetes.azure.com/scalesetpriority=spot:NoSchedule
# taint ensures only pods with explicit spot tolerations land here.
# This prevents critical workloads from accidentally running on spot nodes.
#
# WHY spot_max_price = -1: Pay whatever the current market price is. This
# maximizes availability (Azure only evicts for capacity, not price).
# Setting a price cap would cause more frequent evictions.
#
# WHY eviction_policy = Delete: When evicted, the node is deleted entirely
# (vs. deallocated). The auto-scaler will provision a new spot VM when
# capacity becomes available. Deallocate is only useful for stateful VMs.
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.spot_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 30
  enable_auto_scaling   = true
  min_count             = var.spot_node_min_count
  max_count             = var.spot_node_max_count
  mode                  = "User"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1
  tags                  = var.tags

  # WHY: Taint ensures only workloads that explicitly tolerate spot eviction
  # are scheduled here. Without this, the scheduler might place a critical
  # API server pod on a spot node that gets evicted during peak traffic.
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  # WHY: Labels allow PodSpec nodeSelector to target spot nodes for
  # cost-optimized workloads (e.g., batch jobs, dev environments).
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
}
