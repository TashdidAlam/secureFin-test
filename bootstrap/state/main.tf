# =============================================================================
# Bootstrap Layer - Main Configuration
# =============================================================================
# PURPOSE: Provision the foundational resources required for Terraform remote
# state management with enterprise-grade security:
#
#   1. Resource Group       — Isolated container for all state resources
#   2. User Assigned MI     — Identity for Storage Account CMK access
#   3. Key Vault            — HSM-backed key storage for CMK encryption
#   4. Key Vault Key        — The actual CMK used to encrypt the storage account
#   5. Storage Account      — Holds Terraform state files (.tfstate)
#   6. Storage Container    — Blob container for state files
#
# WHY CMK (Customer Managed Key)?
# ─────────────────────────────────
# In fintech, regulatory compliance (PCI-DSS, SOC2, ISO 27001) mandates that
# encryption keys must be under the organization's control — not Microsoft's
# default platform-managed keys. CMK via Key Vault ensures:
#   - Key rotation is auditable and controllable
#   - Key access is governed by RBAC, not shared secrets
#   - Compliance evidence is straightforward for auditors
#
# WHY is bootstrap separate from infra?
# ──────────────────────────────────────
# Terraform state storage is a prerequisite for Terraform itself. You cannot
# configure a remote backend that doesn't exist yet. The bootstrap layer:
#   - Uses local state (committed securely or stored in a vault)
#   - Is run once by an operator with elevated permissions
#   - Never participates in CI/CD — it IS the foundation CI/CD depends on
# =============================================================================

# Random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # WHY: Consistent naming convention across all bootstrap resources
  name_prefix = "${var.project}-state"
  # Storage account names: max 24 chars, lowercase alphanumeric only
  # st(2) + project(7) + tfstate(7) + hex(8) = 24
  storage_account_name = "st${substr(lower(var.project), 0, 7)}tfstate${random_id.suffix.hex}"

  tags = {
    Project     = "SecureFin"
    Environment = var.environment
    Owner       = "DevOps Platform"
    CostCenter  = "SECUREFIN-P1"
    ManagedBy   = "Terraform"
    Layer       = "Bootstrap"
  }
}

# =============================================================================
# 1. Resource Group - Isolated container for all state management resources
# =============================================================================
# WHY separate RG: State resources have a different lifecycle than application
# infra. They must NEVER be accidentally destroyed by a CI/CD pipeline.
resource "azurerm_resource_group" "state" {
  name     = "rg-${local.name_prefix}-${var.location}"
  location = var.location
  tags     = local.tags
}

# =============================================================================
# 2. User Assigned Managed Identity
# =============================================================================
# WHY: The storage account needs an identity to access Key Vault for CMK.
# User-assigned (not system-assigned) because:
#   - It survives resource recreation
#   - It can be pre-authorized in Key Vault before the storage account exists
#   - It decouples identity lifecycle from resource lifecycle
resource "azurerm_user_assigned_identity" "state_cmk" {
  name                = "id-${local.name_prefix}-cmk"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = local.tags
}

# =============================================================================
# 3. Azure Key Vault - Secure key storage for CMK
# =============================================================================
# WHY Key Vault:
#   - FIPS 140-2 Level 2 validated (software-protected keys at Standard SKU)
#   - Full audit trail of key operations via Azure Monitor
#   - RBAC-based access control (no vault access policies)

# Fetch current client config for Key Vault admin policies
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "state" {
  # Key Vault names: max 24 chars — kv-(3)+project(5)+-state-(7)+hex(8)=23
  name                = "kv-${substr(lower(var.project), 0, 5)}-state-${random_id.suffix.hex}"
  location            = azurerm_resource_group.state.location
  resource_group_name = azurerm_resource_group.state.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # WHY standard: Premium is for HSM-backed keys (BYOK scenarios).
  # Standard is sufficient for CMK with software-protected keys.
  sku_name = "standard"

  # WHY: Soft delete + purge protection are MANDATORY for CMK.
  # Without purge protection, a deleted key = permanently lost state encryption.
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # WHY RBAC: Access policies are legacy. RBAC provides:
  #   - Consistent Azure-wide authorization model
  #   - Granular permissions via built-in roles
  #   - Auditable via Azure AD logs
  enable_rbac_authorization = true

  tags = local.tags
}

# WHY: The deploying identity needs Crypto Officer to create and manage keys
resource "azurerm_role_assignment" "deployer_crypto_officer" {
  scope                = azurerm_key_vault.state.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# WHY: The managed identity needs Crypto Service Encryption User to USE the
# key for wrapping/unwrapping (encrypt/decrypt storage account data).
# This is the minimum privilege — it cannot create, delete, or rotate keys.
resource "azurerm_role_assignment" "cmk_identity_crypto_user" {
  scope                = azurerm_key_vault.state.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.state_cmk.principal_id
}

# =============================================================================
# 4. Key Vault Key - The CMK used for storage encryption
# =============================================================================
# WHY RSA-2048: Industry standard for symmetric key wrapping.
# The storage account's AES-256 data encryption key is wrapped (encrypted)
# with this RSA key, giving us control over the master encryption.
resource "azurerm_key_vault_key" "state_cmk" {
  name         = "cmk-tfstate-encryption"
  key_vault_id = azurerm_key_vault.state.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]

  # WHY: Automatic rotation ensures keys don't become stale.
  # 90-day rotation meets most compliance frameworks.
  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  tags = local.tags

  # WHY: Key creation must wait for RBAC propagation.
  # Azure RBAC assignments can take up to 5 minutes to propagate.
  depends_on = [azurerm_role_assignment.deployer_crypto_officer]
}

# =============================================================================
# 5. Storage Account - Terraform state blob storage
# =============================================================================
# WHY Blob Storage for state:
#   - Native Terraform backend support
#   - Built-in locking via blob leases
#   - Versioning for state history
#   - Geo-redundancy options
resource "azurerm_storage_account" "tfstate" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  # WHY Standard_GRS: Terraform state is critical. Geo-redundant storage
  # ensures state survives a full regional outage. For fintech, data
  # durability is non-negotiable.
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"

  # WHY: TLS 1.2 minimum is required by PCI-DSS and most security frameworks
  min_tls_version = "TLS1_2"

  # WHY: Azure AD auth ONLY — no shared keys, no SAS tokens.
  # This is critical: shared_access_key_enabled = false means the ONLY way
  # to access this storage account is via Azure AD RBAC. No key leakage risk.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # WHY: Public network access allows Terraform CLI and CI/CD runners to
  # reach the storage account. In production, restrict this to specific
  # IP ranges or private endpoints.
  public_network_access_enabled = true

  # WHY: Blob versioning enables state recovery if corruption occurs
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 365
    }

    container_delete_retention_policy {
      days = 365
    }
  }

  # WHY CMK: Customer Managed Key encryption — the entire reason this
  # bootstrap layer exists. CMK is enforced at the storage account level,
  # meaning ALL blobs (including tfstate files) are encrypted with our key.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.state_cmk.id]
  }

  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.state_cmk.id
    user_assigned_identity_id = azurerm_user_assigned_identity.state_cmk.id
  }

  tags = local.tags
}

# =============================================================================
# 6. Storage Container - Blob container for Terraform state
# =============================================================================
resource "azurerm_storage_container" "tfstate" {
  name                 = "tfstate"
  storage_account_name = azurerm_storage_account.tfstate.name

  # WHY private: No anonymous access to state files. Ever.
  container_access_type = "private"
}

# =============================================================================
# 7. RBAC - Grant CI/CD identity access to state storage
# =============================================================================
# WHY Storage Blob Data Contributor: Grants the bootstrap operator (the
# identity running this Terraform) access to manage state blobs.
resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# WHY: The CI/CD service principal (via OIDC) is a DIFFERENT identity from
# the bootstrap operator. It needs its own Storage Blob Data Contributor
# role to read, write, and delete state blobs during pipeline runs.
resource "azurerm_role_assignment" "cicd_blob_contributor" {
  count                = var.cicd_principal_id != "" ? 1 : 0
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.cicd_principal_id
}
