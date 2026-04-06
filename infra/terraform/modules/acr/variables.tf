# =============================================================================
# ACR Module - Variables
# =============================================================================
# WHY a dedicated ACR module?
# ─────────────────────────────
# Azure Container Registry is the secure image store for SecureFin workloads.
# This module enforces:
#   - Admin account disabled (RBAC-only authentication)
#   - No anonymous pull (images are private)
#   - Standardized naming (globally unique, alphanumeric only)
#
# ACR is decoupled from AKS so the registry can survive cluster rebuilds
# and serve multiple clusters (dev, staging, production).
# =============================================================================

# -----------------------------------------------------------------------------
# Required variables — passed from root main.tf
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group for ACR resources"
  type        = string
}

variable "location" {
  description = "Azure region for the ACR instance"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project" {
  description = "Project identifier used in resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all ACR resources"
  type        = map(string)
}

# -----------------------------------------------------------------------------
# ACR configuration
# -----------------------------------------------------------------------------

variable "sku" {
  description = "ACR SKU tier (Basic for dev/free-tier, Standard or Premium for production)"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be one of: Basic, Standard, Premium."
  }
}
