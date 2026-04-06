# =============================================================================
# SecureFin Platform - Outputs
# =============================================================================

output "core_resource_group_name" {
  description = "Name of the core services resource group"
  value       = module.rg_core.name
}

output "aks_resource_group_name" {
  description = "Name of the AKS resource group"
  value       = module.rg_aks.name
}

output "data_resource_group_name" {
  description = "Name of the data services resource group"
  value       = module.rg_data.name
}

output "bastion_resource_group_name" {
  description = "Name of the Bastion resource group"
  value       = module.rg_bastion.name
}

output "environment" {
  description = "Current environment name"
  value       = var.environment
}

output "tags" {
  description = "Tags applied to all resources in this environment"
  value       = module.tags.tags
}

# ---------------------------------------------------------------------------
# ACR Outputs (Module 3 — CI/CD & GitOps)
# ---------------------------------------------------------------------------

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = module.acr.acr_name
}

output "acr_login_server" {
  description = "ACR login server URL (used by CI/CD for docker push and K8s image references)"
  value       = module.acr.acr_login_server
}

# ---------------------------------------------------------------------------
# Bastion + Jump Box Outputs
# ---------------------------------------------------------------------------

output "bastion_name" {
  description = "Name of the Azure Bastion host"
  value       = module.bastion.bastion_name
}

output "jumpbox_name" {
  description = "Name of the Jump Box VM"
  value       = module.bastion.jumpbox_name
}

output "jumpbox_admin_username" {
  description = "Admin username for the Jump Box"
  value       = module.bastion.jumpbox_admin_username
}

output "jumpbox_ssh_private_key" {
  description = "SSH private key for the Jump Box (terraform output -raw jumpbox_ssh_private_key)"
  value       = module.bastion.jumpbox_ssh_private_key
  sensitive   = true
}
