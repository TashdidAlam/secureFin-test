# =============================================================================
# Production Environment - Variable Values
# =============================================================================
# USAGE: terraform plan -var-file=environments/production/production.tfvars
#
# Azure identity values are set via ARM_* environment variables from GitHub
# repository variables in the CI/CD pipeline.
# =============================================================================

environment = "production"
project     = "securefin"
