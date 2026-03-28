# =============================================================================
# Network Module - Variables
# =============================================================================
# WHY a dedicated network module?
# ─────────────────────────────────
# In a zero-trust fintech platform, the network is the first line of defense.
# This module enforces:
#   - A single VNet with well-defined subnet boundaries
#   - Deny-by-default NSG rules (no implicit "allow all" traffic)
#   - Dedicated subnets per workload type (AKS, private endpoints)
#   - Explicit CIDR planning to prevent IP overlap as the platform grows
#
# Every subnet, NSG rule, and association is defined here — not scattered
# across individual resource modules. This gives the security team ONE place
# to audit all network-level controls.
# =============================================================================

# -----------------------------------------------------------------------------
# Required variables
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group where network resources are deployed"
  type        = string
}

variable "location" {
  description = "Azure region for all network resources"
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
  description = "Project identifier used in resource naming (e.g., securefin)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all network resources"
  type        = map(string)
}

# -----------------------------------------------------------------------------
# Network CIDR configuration
# -----------------------------------------------------------------------------
# WHY configurable CIDRs: Different environments may need different address
# spaces (e.g., production uses larger ranges). Defaults match the standard
# SecureFin design but can be overridden per environment.
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the VNet (e.g., [\"10.0.0.0/16\"])"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.vnet_address_space) > 0
    error_message = "VNet must have at least one address space."
  }
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS subnet — sized for pods + nodes (Azure CNI assigns IPs from this range)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR for private endpoints subnet — PaaS services (Key Vault, ACR, Storage) connect here"
  type        = string
  default     = "10.0.2.0/24"
}
