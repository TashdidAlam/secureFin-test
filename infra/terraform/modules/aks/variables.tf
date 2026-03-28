# =============================================================================
# AKS Module - Variables
# =============================================================================
# WHY a dedicated AKS module?
# ─────────────────────────────
# AKS is the compute backbone of SecureFin. This module enforces:
#   - Private cluster ONLY (no public API server)
#   - OIDC + Workload Identity (zero-secret pod authentication)
#   - Azure CNI (pods get real VNet IPs — required for Network Policies)
#   - Explicit version pinning (no surprise upgrades)
#   - Separated node pools (system vs. user vs. spot) for blast radius
#
# Every AKS configuration decision here is driven by PCI-DSS, SOC2, or
# zero-trust principles — not convenience defaults.
# =============================================================================

# -----------------------------------------------------------------------------
# Required variables — passed from root main.tf
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group for AKS resources"
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster"
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
  description = "Tags to apply to all AKS resources"
  type        = map(string)
}

# -----------------------------------------------------------------------------
# Network integration
# -----------------------------------------------------------------------------
# WHY passed as variable: The network module creates the subnet, and AKS
# consumes it. This explicit dependency prevents circular references and
# ensures the network exists before AKS tries to place nodes.
# -----------------------------------------------------------------------------

variable "aks_subnet_id" {
  description = "Resource ID of the subnet where AKS nodes and pods are placed (Azure CNI)"
  type        = string
}

# -----------------------------------------------------------------------------
# Kubernetes version
# -----------------------------------------------------------------------------
# WHY pinned: Kubernetes version drift between environments is the #1 cause
# of "works in dev, breaks in prod" failures. Pinning ensures identical
# API behavior across all environments.
#
# HOW TO UPDATE: Change this value, run plan, verify the upgrade path is
# supported (Azure only allows N-2 minor version jumps), then apply.
# Reference: az aks get-versions --location <region> -o table
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Pinned Kubernetes version (e.g., '1.33'). Use 'az aks get-versions' to list supported versions."
  type        = string
  default     = "1.33"
}

# -----------------------------------------------------------------------------
# System node pool (default)
# -----------------------------------------------------------------------------
# WHY a dedicated system pool: System pods (CoreDNS, konnectivity, metrics-server)
# must run on isolated nodes to prevent application workloads from starving
# critical cluster infrastructure. The CriticalAddonsOnly taint enforces this.
# -----------------------------------------------------------------------------

variable "system_node_count" {
  description = "Number of nodes in the system pool (runs CoreDNS, konnectivity, metrics-server)"
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_count >= 1
    error_message = "System node pool must have at least 1 node."
  }
}

variable "system_node_vm_size" {
  description = "VM size for system nodes (burstable is fine — system pods are lightweight)"
  type        = string
  default     = "Standard_B2s"
}

# -----------------------------------------------------------------------------
# User node pool
# -----------------------------------------------------------------------------
# WHY separate: Application workloads run here, isolated from system pods.
# Auto-scaling is enabled so the pool can grow/shrink based on demand.
# Production should set min=2 for HA, dev can use min=1 for cost savings.
# -----------------------------------------------------------------------------

variable "user_node_min_count" {
  description = "Minimum nodes in user pool (auto-scale lower bound)"
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum nodes in user pool (auto-scale upper bound)"
  type        = number
  default     = 3
}

variable "user_node_vm_size" {
  description = "VM size for user nodes (application workloads)"
  type        = string
  default     = "Standard_B2s"
}

# -----------------------------------------------------------------------------
# Spot node pool
# -----------------------------------------------------------------------------
# WHY spot: Spot VMs are 60-90% cheaper than on-demand. Ideal for:
#   - Dev/staging environments (acceptable interruptions)
#   - Batch jobs, CI runners, non-critical workloads in production
#   - Cost optimization without sacrificing architecture quality
#
# Spot eviction: Azure can reclaim these nodes with 30s notice. Workloads
# must tolerate interruption (use PodDisruptionBudgets for critical apps).
# -----------------------------------------------------------------------------

variable "spot_node_min_count" {
  description = "Minimum nodes in spot pool (can be 0 for cost savings)"
  type        = number
  default     = 0
}

variable "spot_node_max_count" {
  description = "Maximum nodes in spot pool"
  type        = number
  default     = 3
}

variable "spot_node_vm_size" {
  description = "VM size for spot nodes"
  type        = string
  default     = "Standard_B2s"
}

# -----------------------------------------------------------------------------
# Network configuration (Azure CNI)
# -----------------------------------------------------------------------------
# WHY configurable: Service CIDR and DNS IP must not overlap with VNet CIDR.
# These defaults use 10.1.0.0/16 (separate from VNet's 10.0.0.0/16).
# -----------------------------------------------------------------------------

variable "service_cidr" {
  description = "CIDR for Kubernetes ClusterIP services (must not overlap with VNet CIDR)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP for kube-dns within the service CIDR (must be inside service_cidr)"
  type        = string
  default     = "10.1.0.10"
}
