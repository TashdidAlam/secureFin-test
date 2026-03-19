# =============================================================================
# SecureFin Platform - Variables
# =============================================================================
# Azure identity values (subscription_id, tenant_id, client_id) are NOT
# Terraform variables. They are passed via ARM_* environment variables
# which the AzureRM provider and backend read automatically:
#   ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# =============================================================================

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
