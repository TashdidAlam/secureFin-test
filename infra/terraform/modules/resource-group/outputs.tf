# =============================================================================
# Resource Group Module - Outputs
# =============================================================================
# WHY: Downstream modules (AKS, databases, networking) need the RG name
# and location to place their resources. Outputs create explicit dependency
# chains that Terraform uses for correct ordering.
# =============================================================================

output "name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.securefin_rg.name
}

output "location" {
  description = "The Azure region of the resource group"
  value       = azurerm_resource_group.securefin_rg.location
}

output "id" {
  description = "The resource ID of the resource group"
  value       = azurerm_resource_group.securefin_rg.id
}
