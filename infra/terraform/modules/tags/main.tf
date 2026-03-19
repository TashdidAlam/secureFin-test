# =============================================================================
# Tags Module - Main
# =============================================================================
# WHY: Centralizes the tagging strategy. All resources in SecureFin MUST
# include the mandatory tags defined here. The merge() function allows
# consumers to add resource-specific tags without losing the base set.
# =============================================================================

locals {
  # WHY: Mandatory tags are defined as a base set. These are non-negotiable
  # for compliance, cost tracking, and operational visibility.
  mandatory_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = var.managed_by
  }

  # WHY merge: Allows resource-specific tags (e.g., "Service = AKS") to be
  # added without duplicating the base tags in every resource block.
  # additional_tags is merged AFTER mandatory, so mandatory tags cannot be
  # accidentally overridden.
  tags = merge(local.mandatory_tags, var.additional_tags)
}
