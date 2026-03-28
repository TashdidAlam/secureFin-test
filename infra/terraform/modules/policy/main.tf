# =============================================================================
# Azure Policy Module - Definitions & Assignments
# =============================================================================
# Enforces fintech compliance guardrails at the resource group level:
#   1. Require mandatory tags on all resources
#   2. Deny creation of public IP addresses
#   3. Restrict deployments to approved Azure regions
# =============================================================================

# ---------------------------------------------------------------------------
# Policy 1: Enforce Required Tags
# ---------------------------------------------------------------------------
# WHY: PCI-DSS and SOC 2 require accurate asset inventory. Tags provide
# automated tracking of ownership, cost center, and environment classification.
# A missing tag can mean a resource escapes compliance scanning.
#
# HOW: One policy definition per required tag. Each enforces "Deny" if the
# tag key is missing from the resource being created/updated.
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "require_tag" {
  for_each = toset(var.required_tags)

  name         = "require-tag-${lower(each.key)}-${var.project}-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Require tag: ${each.key} (${var.project}-${var.environment})"
  description  = "Denies resource creation if the '${each.key}' tag is missing. Required for ${var.project} compliance."

  policy_rule = jsonencode({
    if = {
      field  = "[concat('tags[', '${each.key}', ']')]"
      exists = "false"
    }
    then = {
      effect = "Deny"
    }
  })
}

resource "azurerm_resource_group_policy_assignment" "require_tag" {
  for_each = {
    for pair in setproduct(toset(var.resource_group_ids), toset(var.required_tags)) :
    "${pair[0]}|${pair[1]}" => {
      rg_id = pair[0]
      tag   = pair[1]
    }
  }

  name                 = "assign-tag-${lower(each.value.tag)}-${var.environment}-${index(var.resource_group_ids, each.value.rg_id)}"
  resource_group_id    = each.value.rg_id
  policy_definition_id = azurerm_policy_definition.require_tag[each.value.tag].id
  display_name         = "Enforce tag: ${each.value.tag}"
  description          = "Ensures all resources in this RG carry the '${each.value.tag}' tag."
  enforce              = true
}

# ---------------------------------------------------------------------------
# Policy 2: Deny Public IP Addresses
# ---------------------------------------------------------------------------
# WHY: SecureFin runs a private AKS cluster — no workload should have a
# direct public IP. Public IPs bypass the network perimeter, creating an
# uncontrolled ingress/egress path that violates zero-trust.
#
# HOW: Denies creation of Microsoft.Network/publicIPAddresses resources.
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "deny-public-ip-${var.project}-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Deny Public IP creation (${var.project}-${var.environment})"
  description  = "Prevents creation of public IP addresses to enforce private-only networking for ${var.project}."

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Network/publicIPAddresses"
    }
    then = {
      effect = "Deny"
    }
  })
}

resource "azurerm_resource_group_policy_assignment" "deny_public_ip" {
  count = length(var.resource_group_ids)

  name                 = "assign-deny-pip-${count.index}-${var.environment}"
  resource_group_id    = var.resource_group_ids[count.index]
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
  display_name         = "Deny Public IPs"
  description          = "Blocks public IP creation in this resource group."
  enforce              = true
}

# ---------------------------------------------------------------------------
# Policy 3: Restrict Allowed Locations
# ---------------------------------------------------------------------------
# WHY: Data residency is a regulatory requirement for fintech. Resources
# deployed outside approved regions may violate data sovereignty laws
# (GDPR, local banking regulations). Restricting locations ensures all
# compute and storage remain in compliant geographies.
#
# HOW: Uses the built-in "Allowed locations" policy definition. Only
# regions listed in var.allowed_locations are permitted.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  count = length(var.resource_group_ids)

  name                 = "assign-locations-${count.index}-${var.environment}"
  resource_group_id    = var.resource_group_ids[count.index]
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  display_name         = "Restrict to allowed locations"
  description          = "Limits resource deployment to approved Azure regions for data residency compliance."
  enforce              = true

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}
