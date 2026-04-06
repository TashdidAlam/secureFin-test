# =============================================================================
# Identity Module - Outputs
# =============================================================================
# WHY: Downstream consumers need the identity's client_id and principal_id:
#   - Kubernetes ServiceAccount: annotated with client_id so the Workload
#     Identity webhook knows which Azure identity to request tokens for
#   - RBAC assignments: principal_id is used in azurerm_role_assignment to
#     grant the identity access to Azure resources (Key Vault, Storage, etc.)
#   - Future modules: will reference these outputs for least-privilege access
# =============================================================================

output "identity_id" {
  description = "Resource ID of the User Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.securefin_workload_id.id
}

output "identity_client_id" {
  description = "Client ID of the managed identity (used in K8s ServiceAccount annotation)"
  value       = azurerm_user_assigned_identity.securefin_workload_id.client_id
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity (used in Azure RBAC role assignments)"
  value       = azurerm_user_assigned_identity.securefin_workload_id.principal_id
}

output "identity_name" {
  description = "Name of the User Assigned Managed Identity"
  value       = azurerm_user_assigned_identity.securefin_workload_id.name
}

output "federated_credential_id" {
  description = "Resource ID of the Federated Identity Credential"
  value       = azurerm_federated_identity_credential.securefin_federated_cred.id
}
