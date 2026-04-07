# =============================================================================
# DNS Module - Variables
# =============================================================================

variable "resource_group_name" {
  description = "Resource group for DNS zone resources"
  type        = string
}

variable "location" {
  description = "Azure region (used in DNS zone name: privatelink.<region>.azmk8s.io)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
}

variable "tags" {
  description = "Tags for all DNS resources"
  type        = map(string)
}

# ---------------------------------------------------------------------------
# VNet links
# ---------------------------------------------------------------------------

variable "env_vnet_id" {
  description = "Resource ID of the environment VNet to link to the AKS DNS zone"
  type        = string
}

variable "bastion_vnet_id" {
  description = "Resource ID of the Bastion VNet to link to the AKS DNS zone"
  type        = string
  default     = ""
}

variable "enable_bastion_dns_link" {
  description = "Whether to create the Bastion VNet DNS link (must be known at plan time)"
  type        = bool
  default     = false
}
