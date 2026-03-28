# =============================================================================
# Azure Policy Module - Variables
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "project" {
  description = "Project identifier used in policy naming"
  type        = string
}

variable "required_tags" {
  description = "List of tag keys that must be present on every resource"
  type        = list(string)
  default     = ["Project", "Environment", "Owner", "CostCenter", "ManagedBy"]
}

variable "allowed_locations" {
  description = "Azure regions where resources are permitted"
  type        = list(string)
  default     = ["eastus2", "eastus"]
}

variable "resource_group_ids" {
  description = "List of resource group IDs to assign policies to"
  type        = list(string)
}
