# =============================================================================
# Identity Module - Variables
# =============================================================================
# WHY a dedicated identity module?
# ─────────────────────────────────
# Workload Identity is the zero-trust bridge between Kubernetes and Azure.
# Instead of storing Azure credentials as Kubernetes secrets (which can leak
# via etcd, logs, or pod env vars), pods authenticate using projected
# service account tokens that Azure AD trusts via OIDC federation.
#
# This module creates:
#   1. A User Assigned Managed Identity (the Azure-side identity)
#   2. A Federated Identity Credential (the trust relationship)
#
# The trust chain: Pod → ServiceAccount → Projected Token → Azure AD → Access
#
# WHY separate from AKS module:
# - Separation of concerns: AKS manages compute, identity manages auth
# - The same identity pattern will be reused for multiple service accounts
#   (e.g., app-sa, monitoring-sa, backup-sa) — each gets its own FIC
# - RBAC assignments on the identity are independent of AKS lifecycle
# =============================================================================

# -----------------------------------------------------------------------------
# Required variables
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group where the managed identity is created"
  type        = string
}

variable "location" {
  description = "Azure region for the managed identity"
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
  description = "Tags to apply to identity resources"
  type        = map(string)
}

# -----------------------------------------------------------------------------
# AKS OIDC integration
# -----------------------------------------------------------------------------
# WHY passed as variable: The AKS module outputs its OIDC issuer URL after
# cluster creation. This URL is the trust anchor — Azure AD will only accept
# tokens signed by this specific issuer. Passing it as a variable creates
# an explicit Terraform dependency: identity → AKS (correct ordering).
# -----------------------------------------------------------------------------

variable "oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster (output of aks module)"
  type        = string
}

# -----------------------------------------------------------------------------
# Kubernetes service account binding
# -----------------------------------------------------------------------------
# WHY configurable: Different workloads use different service accounts in
# different namespaces. The default (default:app-sa) covers the primary
# application, but the module can be instantiated multiple times for
# additional workload identities (e.g., monitoring, backup agents).
#
# SUBJECT FORMAT: system:serviceaccount:<namespace>:<service-account-name>
# This is the OIDC subject claim that Azure AD validates. If this doesn't
# match exactly, token exchange fails with a 400 error.
# -----------------------------------------------------------------------------

variable "k8s_namespace" {
  description = "Kubernetes namespace where the service account exists"
  type        = string
  default     = "default"
}

variable "k8s_service_account_name" {
  description = "Kubernetes service account name that maps to this Azure identity"
  type        = string
  default     = "app-sa"
}
