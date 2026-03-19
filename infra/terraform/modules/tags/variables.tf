# =============================================================================
# Tags Module - Variables
# =============================================================================
# WHY a dedicated tags module?
# ─────────────────────────────
# In a fintech platform, consistent tagging is not optional — it's mandatory for:
#   - Cost allocation and chargeback (CostCenter tag)
#   - Compliance auditing (ManagedBy, Owner tags)
#   - Environment isolation verification (Environment tag)
#   - Incident response (quickly identify resource ownership)
#
# A module ensures every team uses the SAME tags. No drift, no missing tags.
# =============================================================================

variable "project" {
  description = "Project name — used for resource identification and billing"
  type        = string
  default     = "SecureFin"
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "owner" {
  description = "Team or individual responsible for these resources"
  type        = string
  default     = "DevOps Platform"
}

variable "cost_center" {
  description = "Cost center code for billing and chargeback"
  type        = string
  default     = "SECUREFIN-P1"
}

variable "managed_by" {
  description = "Tool managing the resource lifecycle"
  type        = string
  default     = "Terraform"
}

variable "additional_tags" {
  description = "Additional tags to merge with the standard set"
  type        = map(string)
  default     = {}
}
