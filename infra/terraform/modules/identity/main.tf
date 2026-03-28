# =============================================================================
# Identity Module - Main
# =============================================================================
# WHY: Creates the Azure-side identity that Kubernetes pods assume via
# Workload Identity Federation. This replaces the legacy approach of
# mounting Azure credentials as Kubernetes secrets.
#
# ZERO-SECRET FLOW:
# ─────────────────
#   1. Pod starts with a ServiceAccount annotated with the identity's client_id
#   2. Azure Workload Identity webhook injects a projected token volume
#   3. Azure SDK (DefaultAzureCredential) reads the projected token
#   4. SDK sends token to Azure AD with the OIDC issuer URL
#   5. Azure AD validates: issuer matches FIC, subject matches SA
#   6. Azure AD returns a short-lived access token scoped to the identity's RBAC
#   7. Pod uses the access token to call Azure APIs (Key Vault, Storage, etc.)
#
# At NO point does a secret, password, or certificate exist in the cluster.
# =============================================================================

# ---------------------------------------------------------------------------
# User Assigned Managed Identity
# ---------------------------------------------------------------------------
# WHY User Assigned (not System Assigned):
# - System Assigned identities are tied to a single resource lifecycle (e.g.,
#   if the AKS cluster is deleted, the identity is deleted too)
# - User Assigned identities have an independent lifecycle — they survive
#   cluster rebuilds, which is critical for RBAC assignments that reference
#   them (Key Vault access policies, Storage RBAC, etc.)
# - A single User Assigned identity can be shared across multiple pods/SAs
#   if they need the same Azure permissions (DRY principle)
#
# NAMING: id-{project}-workload-{env} — clearly identifies this as a
# workload identity (not a cluster identity or deployment identity).
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${var.project}-workload-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Federated Identity Credential
# ---------------------------------------------------------------------------
# WHY: This is the trust relationship between AKS and Azure AD. It tells
# Azure AD: "When a token arrives from THIS OIDC issuer, with THIS subject
# claim, treat it as THIS managed identity."
#
# SUBJECT CLAIM FORMAT:
#   system:serviceaccount:<namespace>:<service-account-name>
#
# This must EXACTLY match the Kubernetes ServiceAccount that pods use.
# A mismatch causes AADSTS700211 ("subject claim does not match").
#
# AUDIENCE: api://AzureADTokenExchange — this is the standard audience for
# Azure Workload Identity Federation. Do NOT change this unless you have a
# custom audience configuration in Azure AD.
#
# SECURITY: Only tokens from the specific AKS cluster (identified by
# oidc_issuer_url) AND the specific service account (identified by subject)
# can assume this identity. An attacker would need both cluster access AND
# the ability to create pods in the target namespace with the target SA.
# ---------------------------------------------------------------------------

resource "azurerm_federated_identity_credential" "workload" {
  name                = "fic-${var.project}-${var.k8s_namespace}-${var.k8s_service_account_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.workload.id

  # The AKS OIDC issuer URL — Azure AD only trusts tokens from this issuer
  issuer = var.oidc_issuer_url

  # The Kubernetes service account that maps to this Azure identity
  # Format: system:serviceaccount:<namespace>:<name>
  subject = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"

  # Standard audience for Azure Workload Identity Federation
  audience = ["api://AzureADTokenExchange"]
}
