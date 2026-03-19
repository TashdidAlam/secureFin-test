# =============================================================================
# SecureFin Platform - Variables
# =============================================================================
# Azure identity values (subscription_id, tenant_id, client_id) are NOT
# Terraform variables. They are passed via ARM_* environment variables
# which the AzureRM provider and backend read automatically:
#   ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# =============================================================================

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "48eeedd2-fbbe-4c61-803d-2a8ba099bf0b"
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  default     = "63a9a134-4fad-44e4-a0cf-fd45d4185168"
}

variable "client_id" {
  description = "App Registration client ID (service principal with OIDC federation)"
  type        = string
  default     = "93ec5cf8-4518-461f-96a6-b44fccf4a456"
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
