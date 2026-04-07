# =============================================================================
# DNS Module - Private DNS Zones
# =============================================================================
# WHY: Manages private DNS zones for services that need private name
# resolution (AKS API server, ACR, Key Vault, etc.). Using our own DNS
# zone (instead of AKS "System" mode auto-created GUID zone) gives us:
#   - Predictable zone names (no GUID prefix)
#   - Full control over VNet links (link to Bastion, future VNets)
#   - Easier multi-environment management
#
# ARCHITECTURE:
#   Private DNS Zone ──── VNet Link ──→ Env VNet (10.0.0.0/16)
#         │
#         └──────── VNet Link ──→ Bastion VNet (10.2.0.0/16)
#
# NOTE: Setting private_dns_zone_id on AKS will ForceNew the cluster.
# The AKS identity needs "Private DNS Zone Contributor" on the zone.
# =============================================================================

# ---------------------------------------------------------------------------
# Private DNS Zone: AKS API Server
# ---------------------------------------------------------------------------
# WHY: Private AKS clusters need a DNS zone to resolve the API server's
# private FQDN. By creating our own zone, we avoid the System-mode GUID
# prefix and can link it to any VNet we control.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# VNet Link: Environment VNet → AKS DNS Zone
# ---------------------------------------------------------------------------
# WHY: Pods and services in the env VNet need to resolve the AKS API server
# hostname. Without this link, kube-system components lose API connectivity.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "aks_to_env" {
  name                  = "dnslink-aks-to-env-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = var.env_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# ---------------------------------------------------------------------------
# VNet Link: Bastion VNet → AKS DNS Zone
# ---------------------------------------------------------------------------
# WHY: The Jump Box in the Bastion VNet runs kubectl against the private AKS
# API. Without this link, kubectl fails with DNS resolution errors because
# the Bastion VNet can't resolve privatelink.*.azmk8s.io hostnames.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "aks_to_bastion" {
  count = var.enable_bastion_dns_link ? 1 : 0

  name                  = "dnslink-aks-to-bastion"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = var.bastion_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}
