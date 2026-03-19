# =============================================================================
# Dev Environment - Variable Values
# =============================================================================
# WHY tfvars: Environment-specific values are separated from variable
# declarations. The CI/CD pipeline selects the correct tfvars file based
# on the target branch, ensuring dev values never leak into production.
#
# USAGE: terraform plan -var-file=dev.tfvars
#
# NOTE: Replace subscription_id, tenant_id, and client_id with actual values.
# In CI/CD, these are typically set via GitHub Actions secrets/variables
# and passed as -var flags or TF_VAR_ environment variables.
# =============================================================================

environment = "dev"
location    = "eastus2"
project     = "securefin"

# Azure identity — replace with actual values for your dev environment
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
