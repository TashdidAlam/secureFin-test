# =============================================================================
# Bootstrap Layer - Terraform Variable Values
# =============================================================================
# USAGE: terraform plan -var-file="terraform.tfvars"
#
# NOTE: Replace these with your actual Azure tenant and subscription values.
# The client_id must be a service principal with OIDC federation configured.
# =============================================================================

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
location        = "eastus2"
project         = "securefin"
environment     = "shared"
