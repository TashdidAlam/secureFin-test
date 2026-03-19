# =============================================================================
# Dev Environment - Outputs
# =============================================================================
# WHY: Outputs expose the created resource identifiers for downstream
# consumers (other Terraform workspaces, scripts, or CI/CD steps).
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
