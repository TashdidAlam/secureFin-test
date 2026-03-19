# =============================================================================
# Staging Environment - Variables
# =============================================================================

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "client_id" {
  description = "Service principal client ID (OIDC federated)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "location" {
  description = "Primary Azure region for resource deployment"
  type        = string
  default     = "eastus2"
}

variable "project" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "securefin"
}
