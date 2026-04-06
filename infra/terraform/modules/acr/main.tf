# =============================================================================
# ACR Module - Azure Container Registry
# =============================================================================
# Provisions a private Azure Container Registry for storing SecureFin
# container images. ACR integrates with AKS via the AcrPull RBAC role
# (assigned at root level, not here) — no image pull secrets needed.
#
# SECURITY POSTURE:
#   - Admin account DISABLED (RBAC-only access)
#   - Anonymous pull DISABLED (no public image access)
#   - Data endpoint DISABLED in Basic SKU (no dedicated data endpoints)
#   - Managed identity authentication via AcrPull role
#
# COST: Basic SKU costs ~$0.167/day ($5/month). Sufficient for dev/test
# with 10 GB included storage. Upgrade to Standard ($20/month) or
# Premium ($50/month) for geo-replication, content trust, or private link.
# =============================================================================

# ---------------------------------------------------------------------------
# Azure Container Registry
# ---------------------------------------------------------------------------
# WHY: The CI pipeline builds Docker images and pushes them to ACR. AKS
# pulls images from ACR via kubelet identity (AcrPull role). This eliminates
# Docker Hub rate limits, keeps images within the Azure network, and enables
# image scanning with Microsoft Defender for Containers (future).
#
# NAMING: ACR names must be globally unique, 5-50 chars, alphanumeric only.
# Pattern: acr<project><env> → e.g., acrsecurefindev
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "securefin_acr" {
  name                = "acr${var.project}${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # ---------------------------------------------------------------------------
  # ADMIN ACCOUNT — DISABLED
  # ---------------------------------------------------------------------------
  # WHY: Admin accounts use a shared username/password that:
  #   - Cannot be scoped (full push+pull+delete access)
  #   - Cannot be audited per-user (shared credential)
  #   - Cannot be rotated without downtime (all consumers break)
  # AKS uses its kubelet managed identity + AcrPull role instead.
  # CI/CD uses OIDC federated identity + AcrPush role instead.
  # ---------------------------------------------------------------------------
  admin_enabled = false

  # ---------------------------------------------------------------------------
  # ANONYMOUS PULL — DISABLED
  # ---------------------------------------------------------------------------
  # WHY: Anonymous pull would make all images publicly downloadable.
  # SecureFin images contain proprietary financial logic — public access
  # is a data leakage risk.
  # ---------------------------------------------------------------------------
  anonymous_pull_enabled = false

  tags = var.tags
}
