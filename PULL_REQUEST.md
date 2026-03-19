# Pull Request: SecureFin Platform — Terraform Foundation & CI/CD Pipeline

## Summary

This PR establishes the complete Terraform infrastructure foundation and GitHub Actions CI/CD pipeline for the SecureFin fintech platform. It implements a production-grade, zero-secret architecture using Azure Workload Identity (OIDC) and a branch-based deployment strategy with safety controls.

## Type of Change

- [x] New feature (non-breaking change that adds functionality)
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation only

## What's Included

### 📦 Reusable Modules (`infra/terraform/modules/`)
- **tags** — Centralized tagging strategy enforcing mandatory compliance tags (Project, Environment, Owner, CostCenter, ManagedBy) with support for additional custom tags
- **resource-group** — Resource group creation with naming convention validation (`rg-` prefix enforcement)

### 🌍 Environment Configurations (`infra/terraform/environments/`)
Three environments (`dev`, `staging`, `production`) each containing only:
- `backend.hcl` — External backend config values (RG, storage account, container, state key)
- `{env}.tfvars` — Environment-specific variable values

All shared Terraform code lives in the root `infra/terraform/` directory:
- `main.tf` — Module composition (tags + 3 resource groups: core, aks, data)
- `variables.tf` — Input variable declarations with defaults
- `providers.tf` — OIDC-authenticated AzureRM provider
- `backend.tf` — Azure backend with `use_oidc = true` and `use_azuread_auth = true`
- `versions.tf` — Terraform >= 1.5.0, AzureRM ~> 3.80.0
- `outputs.tf` — Resource group names, environment, tags

### 🔁 CI/CD Pipeline (`.github/workflows/terraform.yml`)
- **Branch-based deployment**: `dev-*` (plan only) → `dev` (apply) → `staging` (apply) → `production` (apply)
- **Path filtering**: Only triggers on `infra/terraform/**` changes; `docs/**` changes are ignored
- **OIDC authentication**: Uses `azure/login@v2` with federated credentials — zero secrets
- **Concurrency control**: One Terraform run per branch at a time
- **Saved plan files**: Apply executes exactly what was planned (`-out=tfplan`)
- **Full pipeline steps**: checkout → fmt check → **tflint** → **checkov security scan** → init (with backend.hcl) → validate → plan → conditional apply
- **TFLint**: Azure-aware linting with `tflint-ruleset-azurerm` catches invalid VM sizes, deprecated SKUs, missing provider constraints
- **Checkov**: Static security & compliance scanner (CIS Azure, PCI-DSS, SOC2) runs in soft-fail advisory mode

### 📖 Documentation (`docs/`)
- `ARCHITECTURE.md` — Full architecture documentation covering bootstrap rationale, module design, environment strategy, CI/CD pipeline behavior matrix, security architecture, and validation guide

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| OIDC over client secrets | Zero-secret auth; tokens are short-lived and scoped to workflow runs |
| Flat shared root layout | Eliminates code duplication; only tfvars/backend.hcl differ per environment |
| Identity values as variable defaults | Ensures provider always has valid auth even if ARM_* env vars are missing |
| Pre-created state backend | Simpler than bootstrapping via Terraform; avoids chicken-and-egg complexity |
| Separate resource groups per domain | Isolated RBAC, lifecycle management, and blast radius reduction |

## Validation Performed

| Check | Result |
|-------|--------|
| `terraform fmt -check -recursive` | ✅ Pass |
| `terraform init -backend=false` + `terraform validate` | ✅ Pass |

**Terraform version used**: v1.11.3 (satisfies `>= 1.5.0` constraint)
**AzureRM provider resolved**: v3.80.0 (satisfies `~> 3.80.0` constraint)

## Prerequisites for Deployment

Before the CI/CD pipeline can run, the following must be configured:

1. **State Backend**: Pre-create storage account `tashdidstatebackup68` with container `tfstate` in RG `rg-securefin-tfstate`
2. **Azure AD App Registration**: Create with OIDC federated credentials for GitHub Actions
3. **GitHub Repository Variables**: Configure `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
4. **RBAC**: Grant `Storage Blob Data Contributor` on the state storage account to the service principal

## Security Checklist

- [x] No client secrets, certificates, or access keys anywhere in the codebase
- [x] OIDC authentication for both provider and backend
- [x] Feature branches cannot run `terraform apply`
- [x] Azure identity values stored as GitHub repository variables (non-secret GUIDs)
- [x] Checkov security scanner integrated in CI pipeline (shift-left security)
- [x] TFLint with Azure ruleset enforces provider-aware best practices

## Files Changed

```
infra/terraform/            — 6 shared root files (main, variables, providers, backend, versions, outputs)
infra/terraform/modules/    — 6 files (tags + resource-group modules)
infra/terraform/environments/ — 6 files (backend.hcl + tfvars × 3 environments)
.github/workflows/          — 1 file (terraform.yml)
docs/                       — 1 file (ARCHITECTURE.md)
.tflint.hcl                 — TFLint config with terraform + azurerm rulesets
README.md                   — Complete project documentation
```

## How to Test

```bash
# Validate any environment locally
cd infra/terraform/environments/dev
terraform init -backend=false
terraform validate

# Run tflint locally
tflint --init --config ../../.tflint.hcl
tflint --config ../../.tflint.hcl --format compact

# Verify pipeline behavior by pushing this branch
# Expected: Plan ONLY (no apply) since this is a dev-* feature branch
```

## Target Branch

`dev` — This feature branch follows the `dev-*` naming convention and will trigger a **plan-only** pipeline run when pushed.
