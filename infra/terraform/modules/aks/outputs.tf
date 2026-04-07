# =============================================================================
# AKS Module - Outputs
# =============================================================================
# WHY: Downstream modules and Kubernetes manifests need cluster metadata:
#   - Identity module: needs oidc_issuer_url for federated credentials
#   - kubectl/Helm: needs cluster name for kubeconfig
#   - Monitoring module (future): needs cluster ID for diagnostic settings
#   - CI/CD pipeline: needs cluster name for `az aks get-credentials`
#
# SECURITY NOTE: No sensitive outputs (kubeconfig, certificates) are exposed.
# Cluster access is through `az aks get-credentials` with Azure AD auth.
# =============================================================================

# ---------------------------------------------------------------------------
# Cluster identity
# ---------------------------------------------------------------------------

output "cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.securefin_aks.id
}

output "cluster_name" {
  description = "Name of the AKS cluster (used by az aks get-credentials)"
  value       = azurerm_kubernetes_cluster.securefin_aks.name
}

# ---------------------------------------------------------------------------
# OIDC + Workload Identity
# ---------------------------------------------------------------------------
# WHY exported: The identity module needs the OIDC issuer URL to create
# federated credentials that allow Kubernetes service accounts to exchange
# projected tokens for Azure AD access tokens. Without this output, the
# identity module can't establish the trust relationship.
# ---------------------------------------------------------------------------

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation (consumed by identity module)"
  value       = azurerm_kubernetes_cluster.securefin_aks.oidc_issuer_url
}

# ---------------------------------------------------------------------------
# Network metadata
# ---------------------------------------------------------------------------

output "cluster_fqdn" {
  description = "Private FQDN of the AKS API server (only resolvable from within VNet)"
  value       = azurerm_kubernetes_cluster.securefin_aks.private_fqdn
}

# ---------------------------------------------------------------------------
# Node resource group
# ---------------------------------------------------------------------------
# WHY exported: AKS creates a secondary "MC_" resource group for node VMs,
# disks, and load balancers. RBAC assignments and Azure Policy may need to
# target this group explicitly.
# ---------------------------------------------------------------------------

output "node_resource_group" {
  description = "Name of the auto-created MC_ resource group containing node VMs"
  value       = azurerm_kubernetes_cluster.securefin_aks.node_resource_group
}

# ---------------------------------------------------------------------------
# Cluster identity (UserAssigned — created at root level)
# ---------------------------------------------------------------------------
# NOTE: The cluster_identity_principal_id is now available at root level
# from the azurerm_user_assigned_identity resource, not from this module.
# ---------------------------------------------------------------------------

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity (used for ACR pull access)"
  value       = azurerm_kubernetes_cluster.securefin_aks.kubelet_identity[0].object_id
}
