# =============================================================================
# Staging Environment - Variable Values
# =============================================================================
# USAGE: terraform plan -var-file=environments/staging/staging.tfvars
#
# Azure identity values are set via ARM_* environment variables from GitHub
# repository variables in the CI/CD pipeline.
# =============================================================================

environment = "staging"
project     = "securefin"
