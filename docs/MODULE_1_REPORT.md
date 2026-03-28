# SecureFin Platform — Module 1 Complete Report

## Project: secureFin-test

**Repository**: `TashdidAlam/secureFin-test`
**Report Date**: March 19, 2026
**Module**: 1 — Terraform Foundation & CI/CD Pipeline
**Status**: ✅ COMPLETE

---

## 1. Executive Summary

Module 1 establishes a **production-grade Terraform CI/CD platform** for the SecureFin fintech application on Azure. It delivers:

- A **flat, shared Terraform root** with environment-specific tfvars/backend configs
- **OIDC-based authentication** (zero secrets stored anywhere)
- A **split plan/apply pipeline** with GitHub Environment approval gates
- **TFLint + Checkov** for linting and security scanning in CI
- **Reusable modules** for tags (compliance) and resource groups (naming validation)
- **3 environment configs** (dev, staging, production) with isolated state files

---

## 2. Azure Identity & Authentication

### Service Principal (Workload Identity Federation)

| Property | Value |
|---|---|
| Client ID | `93ec5cf8-4518-461f-96a6-b44fccf4a456` |
| Object ID | `30683a43-7f0b-4e83-b342-242bdb91a5e7` |
| Tenant ID | `63a9a134-4fad-44e4-a0cf-fd45d4185168` |
| Subscription ID | `48eeedd2-fbbe-4c61-803d-2a8ba099bf0b` |

### Federated Identity Credentials (FICs)

| FIC Subject | Purpose | Status |
|---|---|---|
| `repo:TashdidAlam/secureFin-test:pull_request` | PR plan jobs | ✅ Created |
| `repo:TashdidAlam/secureFin-test:ref:refs/heads/dev` | Dev apply | ✅ Created |
| `repo:TashdidAlam/secureFin-test:ref:refs/heads/staging` | Staging apply | ✅ Created |
| `repo:TashdidAlam/secureFin-test:ref:refs/heads/production` | Production apply | ✅ Created |

### GitHub Repository Variables

| Variable | Value | Type |
|---|---|---|
| `AZURE_CLIENT_ID` | `93ec5cf8-4518-461f-96a6-b44fccf4a456` | Repository variable |
| `AZURE_TENANT_ID` | `63a9a134-4fad-44e4-a0cf-fd45d4185168` | Repository variable |
| `AZURE_SUBSCRIPTION_ID` | `48eeedd2-fbbe-4c61-803d-2a8ba099bf0b` | Repository variable |

### Authentication Flow

```
GitHub Actions Runner
  → Requests OIDC JWT from GitHub (id-token: write)
  → Sends JWT to Azure AD with client_id + tenant_id
  → Azure AD validates FIC subject claim
  → Returns short-lived access token
  → Terraform uses token via ARM_* environment variables
```

**Key decisions**: Identity values are also hardcoded as Terraform variable defaults in `variables.tf` (fallback for local dev). ARM_* env vars from GitHub repo variables take precedence in CI.

---

## 3. State Backend

| Property | Value |
|---|---|
| Resource Group | `rg-securefin-tfstate` |
| Storage Account | `tashdidstatebackup68` |
| Container | `tfstate` |
| Auth Method | Azure AD RBAC (no shared keys) |
| RBAC Role | Storage Blob Data Contributor |

### State Keys Per Environment

| Environment | State File Key |
|---|---|
| dev | `dev.terraform.tfstate` |
| staging | `staging.terraform.tfstate` |
| production | `production.terraform.tfstate` |

**State Locking**: Terraform state locking is provided automatically by the Azure Blob Storage lease mechanism, preventing concurrent modifications. No additional configuration is required — the AzureRM backend acquires a lease on the state blob before any write operation.

**Decision**: Storage account was pre-created manually (chicken-and-egg: Terraform can't create its own backend). The old `bootstrap/` directory that was meant to solve this was deleted as dead code.

---

## 4. Repository Structure (24 files)

```
secureFin-test/
├── .github/
│   └── workflows/
│       └── terraform.yml              # CI/CD pipeline (plan + apply jobs)
├── docs/
│   ├── ARCHITECTURE.md                # Full architecture documentation
│   └── MODULE_1_REPORT.md             # This report
├── infra/
│   └── terraform/
│       ├── main.tf                    # Module composition (tags + 3 RGs)
│       ├── variables.tf               # Shared variables with defaults
│       ├── outputs.tf                 # Output values
│       ├── providers.tf               # AzureRM provider (OIDC + skip reg)
│       ├── backend.tf                 # Azure backend config
│       ├── versions.tf                # Version pinning
│       ├── environments/
│       │   ├── dev/
│       │   │   ├── backend.hcl        # Dev backend config
│       │   │   └── dev.tfvars         # Dev variables
│       │   ├── staging/
│       │   │   ├── backend.hcl        # Staging backend config
│       │   │   └── staging.tfvars     # Staging variables
│       │   └── production/
│       │       ├── backend.hcl        # Production backend config
│       │       └── production.tfvars  # Production variables
│       └── modules/
│           ├── tags/
│           │   ├── main.tf            # Mandatory tag merging
│           │   ├── variables.tf       # Tag variable definitions
│           │   └── outputs.tf         # Merged tags output
│           └── resource-group/
│               ├── main.tf            # RG creation with validation
│               ├── variables.tf       # Name validation (rg- prefix)
│               └── outputs.tf         # RG name, location, ID
├── .gitignore                         # Terraform exclusions
├── .tflint.hcl                        # TFLint config (terraform + azurerm)
├── README.md                          # Project docs
└── PULL_REQUEST.md                    # PR description template
```

---

## 5. Terraform Configuration

### Provider

```hcl
provider "azurerm" {
  features {}
  subscription_id            = var.subscription_id
  tenant_id                  = var.tenant_id
  client_id                  = var.client_id
  use_oidc                   = true
  skip_provider_registration = true    # Avoids deprecated namespace 404s
}
```

### Version Constraints

| Component | Constraint |
|---|---|
| Terraform | `>= 1.5.0` |
| AzureRM Provider | `~> 3.80.0` |

### Resources Created Per Environment

| Resource | Naming Pattern |
|---|---|
| Core Resource Group | `rg-securefin-core-{env}` |
| AKS Resource Group | `rg-securefin-aks-{env}` |
| Data Resource Group | `rg-securefin-data-{env}` |

### Mandatory Tags (Applied to All Resources)

| Tag | Value |
|---|---|
| Project | securefin |
| Environment | dev / staging / production |
| Owner | platform-team |
| CostCenter | fintech-001 |
| ManagedBy | terraform |

---

## 6. CI/CD Pipeline Architecture

### Design: Split Plan/Apply with Approval Gates

```
┌─────────────────────────────────────────────────────┐
│                    TRIGGERS                          │
│  pull_request → dev/staging/production               │
│  push         → dev/staging/production               │
│  paths-ignore → docs/**                              │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│              JOB 1: PLAN (always runs)               │
│                                                      │
│  1. Checkout                                         │
│  2. Detect environment (branch → env mapping)        │
│  3. Setup Terraform 1.5.0                            │
│  4. Azure Login (OIDC)                               │
│  5. terraform fmt -check -recursive                  │
│  6. TFLint (init + lint)                             │
│  7. Checkov security scan (soft-fail)                │
│  8. terraform init -backend-config=<env>/backend.hcl │
│  9. terraform validate                               │
│ 10. terraform plan -var-file=<env>/<env>.tfvars      │
│ 11. Upload plan artifact (push events only)          │
│                                                      │
│  Outputs: tf_environment, apply_allowed              │
└─────────────────┬───────────────────────────────────┘
                  │ (only if push event)
                  ▼
┌─────────────────────────────────────────────────────┐
│     JOB 2: APPLY (push only, with approval)          │
│                                                      │
│  ⏸️  GitHub Environment approval gate                │
│     (staging/production require reviewer approval)   │
│                                                      │
│  1. Checkout                                         │
│  2. Setup Terraform 1.5.0                            │
│  3. Azure Login (OIDC)                               │
│  4. terraform init -backend-config=<env>/backend.hcl │
│  5. Download plan artifact                           │
│  6. terraform apply tfplan (no -auto-approve)        │
└─────────────────────────────────────────────────────┘
```

### Trigger Behavior Matrix

| Event | Target Branch | Plan Job | Apply Job |
|---|---|---|---|
| `pull_request` | dev | ✅ Runs | ❌ Skipped |
| `pull_request` | staging | ✅ Runs | ❌ Skipped |
| `pull_request` | production | ✅ Runs | ❌ Skipped |
| `push` | dev | ✅ Runs | ✅ Runs (auto if no reviewers) |
| `push` | staging | ✅ Runs | ⏸️ Waits for approval |
| `push` | production | ✅ Runs | ⏸️ Waits for approval |

### GitHub Environments (Approval Gates)

| Environment | Required Reviewers | Deployment Branches | Wait Timer |
|---|---|---|---|
| `dev` | None | `dev` only | None |
| `staging` | 1 (`TashdidAlam`) | `staging` only | None |
| `production` | 1 (`TashdidAlam`) | `production` only | Optional 5 min |

### Quality Gates in Pipeline

| Gate | Tool | Behavior |
|---|---|---|
| Format check | `terraform fmt -check -recursive` | Hard fail |
| Linting | TFLint (terraform + azurerm rulesets) | Hard fail |
| Security scan | Checkov (CIS Azure, PCI-DSS, SOC2) | Soft fail (advisory) |
| Validation | `terraform validate` | Hard fail |
| Approval | GitHub Environment reviewers | Blocking (staging/prod) |

### Artifact Flow Between Jobs

```
Plan Job                          Apply Job
   │                                  │
   ├─ terraform plan -out=tfplan      │
   │                                  │
   ├─ upload-artifact@v4 ─────────────┤
   │   name: tfplan-{env}             ├─ download-artifact@v4
   │   retention: 5 days              │   name: tfplan-{env}
   │                                  │
   │                                  ├─ terraform apply tfplan
```

### Concurrency Control

- Group key: `terraform-{branch_name}`
- `cancel-in-progress: false` — queues runs rather than cancelling
- Different environments CAN run in parallel (different branch names)

---

## 7. Branch Strategy

### Branches

| Branch | Purpose | Status |
|---|---|---|
| `main` | Production-ready code | Exists (initial) |
| `dev` | Development environment | ✅ Active, synced with remote |
| `staging` | Staging environment | ✅ Created, synced with remote |
| `production` | Production environment | Not yet created |
| `dev-initial-build` | Feature branch (Module 1 work) | ✅ Merged into dev |

### Deployment Flow

```
feature branch
    │
    ├── PR → dev          (plan only, review code)
    │   └── merge         (push triggers plan + apply to dev)
    │
    ├── PR → staging      (plan only, review plan)
    │   └── approve + merge (push triggers plan + apply with approval)
    │
    └── PR → production   (plan only, review plan carefully)
        └── approve + merge (push triggers plan + apply with approval)
```

---

## 8. Commit History (Chronological)

| # | Commit | Description |
|---|---|---|
| 1 | `0fc14d9` | Initial Terraform foundation and CI/CD pipeline |
| 2 | `80e924f` | Add TFLint, Checkov best practice checks |
| 3 | `f5a5d9c` | Fix path filter (paths → paths-ignore docs/) |
| 4 | `59b5130` | Address Copilot PR review + OIDC pull_request FIC alignment |
| 5 | `94403dc` | Refactor: use pre-created storage account for state backend |
| 6 | `42c2062` | Structure changed (flat shared root layout) |
| 7 | `c7b4fa2` | Fix: add Azure identity variables with actual values |
| 8 | `8e6de8d` | Chore: remove unused bootstrap layer, update stale comments |
| 9 | `9ededf9` | Fix: skip provider registration (deprecated namespace errors) |
| 10 | `8920b2b` | Merge PR #1: dev-initial-build → dev |
| 11 | `bc00504` | Merge dev-initial-build into local dev (push trigger) |
| 12 | `77b0099` | Some change |
| 13 | `b59fc73` | Environment added |
| 14 | `967faea` | Some changes (pipeline refactored to split plan/apply) |
| 15 | `22049b6` | Some change (YAML fix, final pipeline stabilization) |

---

## 9. Problems Solved During Module 1

| # | Problem | Root Cause | Fix |
|---|---|---|---|
| 1 | `AADSTS700016` — Application not found | GitHub secret `AZURE_CLIENT_ID_PLAN` had wrong name | Renamed to `AZURE_CLIENT_ID` |
| 2 | `403 Forbidden` on state storage | Missing RBAC role on storage account | Added `Storage Blob Data Contributor` |
| 3 | `404` on tfstate container | Container didn't exist | Created `tfstate` container |
| 4 | `AADSTS700038` — placeholder client ID | Secrets had `00000000-...` placeholder values | Switched to repository variables with real values |
| 5 | `AADSTS700038` still occurring | Terraform provider not using ARM_* env vars | Added identity values as variable defaults in `variables.tf` |
| 6 | `Error ensuring Resource Providers` | Deprecated namespaces (Microsoft.Media, etc.) return 404 | Added `skip_provider_registration = true` |
| 7 | No pipeline trigger on merge | Only `pull_request` trigger existed | Added `push` trigger for env branches |
| 8 | YAML parse error | Multi-line `${{ }}` expression | Collapsed to single line |
| 9 | Auto-approve not production-grade | `terraform apply -auto-approve` | Split into plan/apply jobs with GitHub Environment approval gates |

---

## 10. Security Posture

### Zero-Secret Architecture

- ❌ No client secrets stored anywhere
- ❌ No storage account keys used
- ❌ No passwords or tokens in code/config
- ✅ OIDC short-lived JWT tokens only
- ✅ Azure AD RBAC for storage access
- ✅ Branch-restricted environment deployments

### Pipeline Security

- ✅ `id-token: write` + `contents: read` (minimal permissions)
- ✅ Feature branches can plan but NEVER apply
- ✅ Apply requires GitHub Environment reviewer approval (staging/production)
- ✅ Deployment branches restricted per environment
- ✅ Concurrency control prevents parallel Terraform runs
- ✅ Plan artifact shared between jobs (no re-plan drift)

### Code Quality

- ✅ `terraform fmt -check -recursive` — formatting enforcement
- ✅ TFLint with terraform + azurerm rulesets — linting
- ✅ Checkov — CIS Azure, PCI-DSS, SOC2 scanning (soft-fail advisory)
- ✅ `terraform validate` — syntax and type validation
- ✅ Resource group naming validation (`rg-` prefix required)
- ✅ Environment variable validation (dev|staging|production only)

---

## 11. What's NOT Done Yet (Future Modules)

| Item | Status | Notes |
|---|---|---|
| `production` branch | ❌ Not created | Need to create branch + push |
| Actual Azure resources (AKS, databases, etc.) | ❌ Not yet | Module 1 is foundation only (3 RGs) |
| Network infrastructure (VNet, subnets, NSGs) | ❌ | Future module |
| AKS cluster | ❌ | Future module |
| Key Vault | ❌ | Future module |
| Database infrastructure | ❌ | Future module |
| Monitoring (App Insights, Log Analytics) | ❌ | Future module |
| DNS / domain configuration | ❌ | Future module |
| Checkov hard-fail enforcement | ❌ | Currently soft-fail (advisory mode) |
| PR comment with plan output | ❌ | Nice-to-have enhancement |

---

## 12. How to Verify Current State

### Check Pipeline Status
```
https://github.com/TashdidAlam/secureFin-test/actions
```

### Check GitHub Environments
```
https://github.com/TashdidAlam/secureFin-test/settings/environments
```

### Check Repository Variables
```
https://github.com/TashdidAlam/secureFin-test/settings/variables/actions
```

### Local Validation (No Azure Required)
```bash
cd infra/terraform
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```

---

## 13. Key Architecture Decisions (ADRs)

| Decision | Choice | Rationale |
|---|---|---|
| Terraform layout | Flat shared root with per-env tfvars | Avoids file duplication across environments |
| Authentication | OIDC (Workload Identity Federation) | Zero secrets, short-lived tokens, industry best practice |
| Secrets vs Variables | GitHub repository variables | Client/tenant/subscription IDs are non-sensitive GUIDs |
| State backend | Pre-created storage account | Solves Terraform chicken-and-egg problem |
| State auth | Azure AD RBAC (no shared keys) | Stronger security, auditable access |
| Provider registration | `skip_provider_registration = true` | Avoids 404 errors from deprecated Azure namespaces |
| Pipeline design | Split plan/apply jobs | Enables approval gates, artifact-based apply |
| Apply approval | GitHub Environments with reviewers | Enterprise-grade, no `-auto-approve` |
| Naming convention | `rg-{project}-{domain}-{env}` | Module-enforced via validation regex |
| Tagging | Mandatory via tags module | Compliance, cost tracking, ownership |

---

*This report covers Module 1 — Terraform Foundation & CI/CD Pipeline. All code is committed, pushed, and operational on the `dev` and `staging` branches.*
