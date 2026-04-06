# =============================================================================
# ACR Module - Outputs
# =============================================================================
# WHY: Downstream modules, CI/CD pipelines, and GitOps manifests need:
#   - acr_id: for RBAC role assignments (AcrPull, AcrPush)
#   - acr_name: for `docker login` and image tag references
#   - acr_login_server: for Helm values and Kubernetes image references
# =============================================================================

output "acr_id" {
  description = "Resource ID of the Azure Container Registry"
  value       = azurerm_container_registry.securefin_acr.id
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.securefin_acr.name
}

output "acr_login_server" {
  description = "Login server URL (e.g., acrsecurefindev.azurecr.io) for docker push/pull"
  value       = azurerm_container_registry.securefin_acr.login_server
}
