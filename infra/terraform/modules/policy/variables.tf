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
  default     = ["westus3", "westus"]
}

variable "resource_group_ids" {
  description = "Map of resource group name labels to IDs for policy assignment (keys must be static)"
  type        = map(string)
}
