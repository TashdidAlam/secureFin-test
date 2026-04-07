# =============================================================================
# DNS Module - Outputs
# =============================================================================

output "aks_dns_zone_id" {
  description = "Resource ID of the AKS private DNS zone (passed to AKS module as private_dns_zone_id)"
  value       = azurerm_private_dns_zone.aks.id
}

output "aks_dns_zone_name" {
  description = "Name of the AKS private DNS zone"
  value       = azurerm_private_dns_zone.aks.name
}
