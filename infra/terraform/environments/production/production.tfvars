# =============================================================================
# Production Environment - Variable Values
# =============================================================================
# WHY: Production values should use production-grade configurations.
# The subscription_id should point to the production subscription,
# which is isolated from dev/staging for blast radius control.
# =============================================================================

environment = "production"
location    = "eastus2"
project     = "securefin"

# Azure identity — replace with actual values for your production environment
# CRITICAL: Production should use a DIFFERENT subscription and service principal
# than dev/staging for security isolation.
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
