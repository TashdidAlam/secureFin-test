# SecureFin Platform — Infrastructure as Code

Production-grade Terraform infrastructure and CI/CD pipeline for the SecureFin fintech platform on Azure.

## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- Azure CLI
- An Azure AD App Registration with OIDC federated credentials for GitHub Actions
- A GitHub repository with the following secrets configured:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`

### 1. Bootstrap State Backend

The bootstrap layer provisions the remote state infrastructure (Storage Account with CMK encryption via Key Vault). Run this **once** before any other Terraform operations:

```bash
cd bootstrap/state

# Update terraform.tfvars with your Azure identifiers
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# Capture outputs for backend.hcl files
terraform output
```

Update `backend.hcl` in each environment (`infra/terraform/environments/{dev,staging,production}/`) with the bootstrap outputs.

### 2. Configure GitHub Secrets

In your GitHub repository settings, add:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | App Registration client ID with OIDC federation |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

### 3. Push and Deploy

```bash
# Feature branch — plan only
git checkout -b dev-feature-login
git push origin dev-feature-login

# Dev — plan + apply
git checkout dev
git push origin dev

# Staging — plan + apply
git checkout staging
git merge dev
git push origin staging

# Production — plan + apply
git checkout production
git merge staging
git push origin production
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architecture documentation.

## Security

- **OIDC authentication** — no client secrets, certificates, or storage keys
- **CMK encryption** — Terraform state encrypted with Customer Managed Key
- **Azure AD-only storage access** — shared access keys disabled
- **RBAC authorization** — Key Vault and Storage use Azure RBAC, not access policies
- **Branch-based safety** — feature branches can never run `terraform apply`

## Tagging

All resources include mandatory tags:

| Tag | Value |
|-----|-------|
| Project | SecureFin |
| Environment | dev / staging / production |
| Owner | DevOps Platform |
| CostCenter | SECUREFIN-P1 |
| ManagedBy | Terraform |

## License

Proprietary. All rights reserved.