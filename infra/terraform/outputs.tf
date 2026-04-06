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
