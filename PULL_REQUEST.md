# Pull Request: SecureFin Platform — Terraform Foundation & CI/CD Pipeline

## Summary

This PR establishes the complete Terraform infrastructure foundation and GitHub Actions CI/CD pipeline for the SecureFin fintech platform. It implements a production-grade, zero-secret architecture using Azure Workload Identity (OIDC), Customer Managed Key (CMK) encryption for Terraform state, and a branch-based deployment strategy with safety controls.

## Type of Change

- [x] New feature (non-breaking change that adds functionality)
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation only

## What's Included

### 🔐 Bootstrap Layer (`bootstrap/state/`)
- Resource Group for state management resources
- Azure Key Vault with purge protection and RBAC authorization
- RSA-2048 CMK key with 90-day automatic rotation policy
- Storage Account with:
  - GRS replication for geo-redundancy
  - `shared_access_key_enabled = false` (Azure AD auth only)
  - CMK encryption via User Assigned Managed Identity
  - Blob versioning and retention policies
- RBAC role assignments (Crypto Officer, Crypto Service Encryption User, Storage Blob Data Contributor)

### 📦 Reusable Modules (`infra/terraform/modules/`)
- **tags** — Centralized tagging strategy enforcing mandatory compliance tags (Project, Environment, Owner, CostCenter, ManagedBy) with support for additional custom tags
- **resource-group** — Resource group creation with naming convention validation (`rg-` prefix enforcement)

### 🌍 Environment Configurations (`infra/terraform/environments/`)
Three structurally identical environments (`dev`, `staging`, `production`) each containing:
- `versions.tf` — Terraform >= 1.5.0, AzureRM ~> 3.80.0
- `providers.tf` — OIDC-authenticated AzureRM provider
- `backend.tf` — Azure backend with `use_oidc = true` and `use_azuread_auth = true`
- `backend.hcl` — External backend config values
- `variables.tf` — Input variable declarations with validation
- `main.tf` — Module composition (tags + 3 resource groups: core, aks, data)
- `outputs.tf` — Resource group names, environment, tags
- `{env}.tfvars` — Environment-specific variable values

### 🔁 CI/CD Pipeline (`.github/workflows/terraform.yml`)
- **Branch-based deployment**: `dev-*` (plan only) → `dev` (apply) → `staging` (apply) → `production` (apply)
- **Path filtering**: Only triggers on `infra/terraform/**` changes; `docs/**` changes are ignored
- **OIDC authentication**: Uses `azure/login@v2` with federated credentials — zero secrets
- **Concurrency control**: One Terraform run per branch at a time
- **Saved plan files**: Apply executes exactly what was planned (`-out=tfplan`)
- **Full pipeline steps**: checkout → fmt check → init (with backend.hcl) → validate → plan → conditional apply

### 📖 Documentation (`docs/`)
- `ARCHITECTURE.md` — Full architecture documentation covering bootstrap rationale, module design, environment strategy, CI/CD pipeline behavior matrix, security architecture, and validation guide

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| OIDC over client secrets | Zero-secret auth; tokens are short-lived and scoped to workflow runs |
| CMK over platform-managed keys | Regulatory compliance (PCI-DSS, SOC2); organization-controlled key rotation |
| Separate bootstrap layer | Chicken-and-egg: state backend must exist before Terraform can use it |
| User Assigned MI for CMK | Survives resource recreation; can be pre-authorized before storage exists |
| `shared_access_key_enabled = false` | Eliminates shared key leakage risk entirely |
| Separate resource groups per domain | Isolated RBAC, lifecycle management, and blast radius reduction |
| Structural parity across environments | Ensures staging validation is meaningful for production |

## Validation Performed

| Check | Result |
|-------|--------|
| `terraform fmt -check -recursive` (bootstrap) | ✅ Pass |
| `terraform fmt -check -recursive` (modules) | ✅ Pass |
| `terraform fmt -check -recursive` (environments) | ✅ Pass |
| `terraform init -backend=false` + `terraform validate` (bootstrap/state) | ✅ Pass |
| `terraform init -backend=false` + `terraform validate` (environments/dev) | ✅ Pass |
| `terraform init -backend=false` + `terraform validate` (environments/staging) | ✅ Pass |
| `terraform init -backend=false` + `terraform validate` (environments/production) | ✅ Pass |

**Terraform version used**: v1.11.3 (satisfies `>= 1.5.0` constraint)
**AzureRM provider resolved**: v3.80.0 (satisfies `~> 3.80.0` constraint)

## Prerequisites for Deployment

Before the CI/CD pipeline can run, the following must be configured:

1. **Bootstrap**: Run `bootstrap/state/` locally to provision state backend infrastructure
2. **Azure AD App Registration**: Create with OIDC federated credentials for GitHub Actions
3. **GitHub Secrets**: Configure `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
4. **Backend.hcl**: Update all environment `backend.hcl` files with bootstrap output values
5. **Tfvars**: Replace placeholder GUIDs in `*.tfvars` with actual Azure identifiers

## Security Checklist

- [x] No client secrets, certificates, or access keys anywhere in the codebase
- [x] OIDC authentication for both provider and backend
- [x] Storage account shared keys disabled
- [x] CMK encryption with Key Vault purge protection
- [x] RBAC authorization (no legacy access policies)
- [x] Feature branches cannot run `terraform apply`
- [x] Sensitive values externalized to GitHub Actions secrets
- [x] TLS 1.2 minimum enforced on storage account

## Files Changed

```
37 files added:
  bootstrap/state/          — 5 files (versions, variables, main, outputs, tfvars)
  infra/terraform/modules/  — 6 files (tags + resource-group modules)
  infra/terraform/environments/ — 24 files (8 per environment × 3 environments)
  .github/workflows/        — 1 file (terraform.yml)
  docs/                     — 1 file (ARCHITECTURE.md)
  
2 files modified:
  .gitignore                — Allow .tfvars in version control
  README.md                 — Complete project documentation
```

## How to Test

```bash
# Validate any environment locally
cd infra/terraform/environments/dev
terraform init -backend=false
terraform validate

# Verify pipeline behavior by pushing this branch
# Expected: Plan ONLY (no apply) since this is a dev-* feature branch
```

## Target Branch

`dev` — This feature branch follows the `dev-*` naming convention and will trigger a **plan-only** pipeline run when pushed.
