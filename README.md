# SecureFin Platform — Infrastructure as Code

Production-grade Terraform infrastructure and CI/CD pipeline for the SecureFin fintech platform on Azure.

## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- Azure CLI
- An Azure AD App Registration with OIDC federated credentials for GitHub Actions
- A GitHub repository with the following **repository variables** configured:
  - `AZURE_CLIENT_ID` — `93ec5cf8-4518-461f-96a6-b44fccf4a456`
  - `AZURE_TENANT_ID` — `63a9a134-4fad-44e4-a0cf-fd45d4185168`
  - `AZURE_SUBSCRIPTION_ID` — `48eeedd2-fbbe-4c61-803d-2a8ba099bf0b`

### 1. Configure GitHub Repository Variables

In your GitHub repository: **Settings → Secrets and variables → Actions → Variables tab**

| Variable | Value |
|----------|-------|
| `AZURE_CLIENT_ID` | App Registration client ID (OIDC federation) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

> **Note**: These are **repository variables**, not secrets. They are non-sensitive GUIDs.

### 2. Ensure State Backend Exists

The state backend must exist before running the pipeline:

```bash
# Verify storage account and container exist
az storage container show \
  --name tfstate \
  --account-name tashdidstatebackup68 \
  --auth-mode login

# Ensure the CI/CD service principal has Storage Blob Data Contributor
az role assignment create \
  --assignee 93ec5cf8-4518-461f-96a6-b44fccf4a456 \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name tashdidstatebackup68 --resource-group rg-securefin-tfstate --query id -o tsv)
```

### 3. Deploy via PR

```bash
# Feature branch — open PR to dev for plan-only
git checkout -b feature-login
# Make changes to infra/terraform/
git push origin feature-login
# Open PR targeting dev → pipeline runs plan

# After review, merge to dev
# (Apply requires push-triggered FIC — see docs/ARCHITECTURE.md)
```

### 4. Local Development

```bash
az login
cd infra/terraform
terraform init -backend-config=environments/dev/backend.hcl
terraform plan -var-file=environments/dev/dev.tfvars
```

## Project Structure

```
infra/terraform/
├── main.tf               # Shared configuration (all environments)
├── variables.tf          # Shared variable declarations
├── outputs.tf            # Shared outputs
├── providers.tf          # AzureRM provider (auth via ARM_* env vars)
├── versions.tf           # Terraform & provider version pins
├── backend.tf            # Backend config (values injected via backend.hcl)
├── modules/
│   ├── tags/             # Mandatory tagging strategy
│   └── resource-group/   # Resource group with naming enforcement
└── environments/
    ├── dev/
    │   ├── backend.hcl   # State backend values + key
    │   └── dev.tfvars    # Dev variable values
    ├── staging/
    │   ├── backend.hcl
    │   └── staging.tfvars
    └── production/
        ├── backend.hcl
        └── production.tfvars
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architecture documentation.

## Security

- **OIDC authentication** — no client secrets, certificates, or storage keys
- **Azure AD-only storage access** — shared access keys disabled
- **RBAC authorization** — Key Vault and Storage use Azure RBAC, not access policies
- **Branch-based safety** — PRs can never run `terraform apply`
- **TFLint** — Azure-aware linting with `tflint-ruleset-azurerm` in CI pipeline
- **Checkov** — Static IaC security scanner (CIS Azure, PCI-DSS, SOC2) in CI pipeline

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
