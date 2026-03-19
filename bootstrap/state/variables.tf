# =============================================================================
# Bootstrap Layer - Variables
# =============================================================================
# WHY: Variables allow the bootstrap to be reused across different tenants or
# subscriptions without hardcoding values. All authentication is via OIDC.
# =============================================================================

variable "subscription_id" {
  description = "Azure subscription ID for the state resources"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "client_id" {
  description = "Client ID of the service principal with OIDC federation"
  type        = string
}

variable "location" {
  description = "Azure region for all bootstrap resources"
  type        = string
  default     = "eastus2"

  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region identifier."
  }
}

variable "environment" {
  description = "Environment label for bootstrap resources (always 'shared' for state)"
  type        = string
  default     = "shared"
}

variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "securefin"
}
