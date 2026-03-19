# =============================================================================
# Resource Group Module - Variables
# =============================================================================
# WHY a resource group module?
# ─────────────────────────────
# Resource groups in SecureFin are not just containers — they are security
# boundaries. Each domain (core, AKS, data) gets its own RG to enable:
#   - Isolated RBAC permissions per domain
#   - Independent lifecycle management
#   - Clear cost attribution via RG-level billing
#   - Blast radius reduction (a misconfigured "delete RG" only affects one domain)
# =============================================================================

variable "name" {
  description = "Name of the resource group (e.g., rg-securefin-core-dev)"
  type        = string

  validation {
    condition     = can(regex("^rg-", var.name))
    error_message = "Resource group name must start with 'rg-' per naming convention."
  }
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the resource group"
  type        = map(string)
}
