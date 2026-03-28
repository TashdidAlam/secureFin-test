# =============================================================================
# Azure Policy Module - Outputs
# =============================================================================

output "tag_policy_ids" {
  description = "Map of tag name to policy definition ID"
  value       = { for k, v in azurerm_policy_definition.require_tag : k => v.id }
}

output "deny_public_ip_policy_id" {
  description = "Policy definition ID for the deny-public-IP policy"
  value       = azurerm_policy_definition.deny_public_ip.id
}

output "tag_assignment_ids" {
  description = "Map of tag name to policy assignment ID"
  value       = { for k, v in azurerm_resource_group_policy_assignment.require_tag : k => v.id }
}

output "deny_public_ip_assignment_ids" {
  description = "Map of resource group key to deny-public-IP policy assignment ID"
  value       = { for k, v in azurerm_resource_group_policy_assignment.deny_public_ip : k => v.id }
}

output "allowed_locations_assignment_ids" {
  description = "Map of resource group key to allowed-locations policy assignment ID"
  value       = { for k, v in azurerm_resource_group_policy_assignment.allowed_locations : k => v.id }
}
