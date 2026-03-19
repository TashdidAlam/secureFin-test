# =============================================================================
# Resource Group Module - Main
# =============================================================================
# WHY: Encapsulates resource group creation with enforced naming conventions
# and mandatory tagging. Using a module ensures every resource group in the
# platform is created consistently — no one-off resource groups with missing
# tags or non-standard names.
# =============================================================================

resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}
