# =============================================================================
# Dev Environment - Variable Values
# =============================================================================
# USAGE: terraform plan -var-file=environments/dev/dev.tfvars
#
# Azure identity values (subscription_id, tenant_id, client_id) are NOT in
# tfvars. They are set via ARM_* environment variables from GitHub repository
# variables in the CI/CD pipeline.
# =============================================================================

environment = "dev"
project     = "securefin"
