# =============================================================================
# Staging Environment - Variable Values
# =============================================================================
# WHY: Staging should mirror production values where possible but may use
# reduced SKUs for cost optimization. Authentication IDs may point to a
# different subscription for isolation.
# =============================================================================

environment = "staging"
location    = "eastus2"
project     = "securefin"

# Azure identity — replace with actual values for your staging environment
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
