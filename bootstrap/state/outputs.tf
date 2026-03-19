# =============================================================================
# Bootstrap Layer - Outputs
# =============================================================================
# WHY: These outputs are consumed when configuring the backend.hcl files in
# each environment. After bootstrap completes, these values are used to
# populate the remote backend configuration for the main infra layer.
# =============================================================================

output "resource_group_name" {
  description = "Resource group containing Terraform state resources"
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Storage account name for Terraform remote state"
  value       = azurerm_storage_account.tfstate.name
}

output "storage_container_name" {
  description = "Blob container name for Terraform state files"
  value       = azurerm_storage_container.tfstate.name
}

output "key_vault_name" {
  description = "Key Vault name holding the CMK for state encryption"
  value       = azurerm_key_vault.state.name
}

output "key_vault_key_name" {
  description = "Name of the CMK key used for storage encryption"
  value       = azurerm_key_vault_key.state_cmk.name
}

output "managed_identity_id" {
  description = "User Assigned Managed Identity ID for CMK operations"
  value       = azurerm_user_assigned_identity.state_cmk.id
}

output "managed_identity_client_id" {
  description = "Client ID of the managed identity (for reference)"
  value       = azurerm_user_assigned_identity.state_cmk.client_id
}
