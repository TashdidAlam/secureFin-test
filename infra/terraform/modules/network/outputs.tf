# =============================================================================
# Network Module - Outputs
# =============================================================================
# WHY: Downstream modules (AKS, identity, future private endpoints) need
# network resource IDs and names to place their resources into the correct
# subnet and VNet. These outputs create explicit Terraform dependency chains
# that ensure networking is fully provisioned before compute or PaaS.
#
# OUTPUT CONSUMERS:
# - modules/aks:      needs aks_subnet_id for node/pod placement
# - modules/identity: needs vnet_id for potential network-scoped RBAC
# - Future modules:   need private_endpoint_subnet_id for PaaS connectivity
# =============================================================================

output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.securefin_vnet.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.securefin_vnet.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet (used by AKS module for node/pod placement)"
  value       = azurerm_subnet.securefin_aks_snet.id
}

output "aks_subnet_name" {
  description = "Name of the AKS subnet"
  value       = azurerm_subnet.securefin_aks_snet.name
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoints subnet (used by future PaaS modules)"
  value       = azurerm_subnet.securefin_pep_snet.id
}

output "private_endpoint_subnet_name" {
  description = "Name of the private endpoints subnet"
  value       = azurerm_subnet.securefin_pep_snet.name
}

output "aks_nsg_id" {
  description = "Resource ID of the AKS NSG (for audit and diagnostic logging)"
  value       = azurerm_network_security_group.securefin_aks_nsg.id
}

output "aks_nsg_name" {
  description = "Name of the AKS NSG"
  value       = azurerm_network_security_group.securefin_aks_nsg.name
}

output "pep_nsg_id" {
  description = "Resource ID of the Private Endpoints NSG (for audit and diagnostic logging)"
  value       = azurerm_network_security_group.securefin_pep_nsg.id
}

output "pep_nsg_name" {
  description = "Name of the Private Endpoints NSG"
  value       = azurerm_network_security_group.securefin_pep_nsg.name
}
