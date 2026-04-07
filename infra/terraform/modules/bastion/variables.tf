# =============================================================================
# Bastion Module - Variables
# =============================================================================

variable "resource_group_name" {
  description = "Resource group for Bastion and Jump Box resources (separate from env RGs)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
}

variable "project" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
}

# ---------------------------------------------------------------------------
# Bastion VNet configuration
# ---------------------------------------------------------------------------

variable "bastion_vnet_address_space" {
  description = "Address space for the Bastion VNet (must not overlap with env VNets or AKS service_cidr)"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "bastion_subnet_cidr" {
  description = "CIDR for AzureBastionSubnet (minimum /26)"
  type        = string
  default     = "10.2.0.0/26"
}

variable "jumpbox_subnet_cidr" {
  description = "CIDR for Jump Box subnet"
  type        = string
  default     = "10.2.1.0/27"
}

# ---------------------------------------------------------------------------
# VNet peering — connect to environment VNet
# ---------------------------------------------------------------------------

variable "env_vnet_id" {
  description = "Resource ID of the environment VNet to peer with"
  type        = string
}

variable "env_vnet_name" {
  description = "Name of the environment VNet (used in peering resource naming)"
  type        = string
}

variable "env_vnet_resource_group_name" {
  description = "Resource group of the environment VNet (needed for the remote peering)"
  type        = string
}

# ---------------------------------------------------------------------------
# Private DNS zone link — REMOVED (now handled by dns module)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Jump Box configuration
# ---------------------------------------------------------------------------

variable "jumpbox_vm_size" {
  description = "VM size for the Jump Box (B2s = 2 vCPU, 4 GB RAM — enough for kubectl/helm)"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for the Jump Box VM"
  type        = string
  default     = "azureadmin"
}
