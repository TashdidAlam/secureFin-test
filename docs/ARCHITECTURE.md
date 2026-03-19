# SecureFin Platform - Architecture Documentation

## Table of Contents

1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [Bootstrap Layer](#bootstrap-layer)
4. [Module Design](#module-design)
5. [Environment Strategy](#environment-strategy)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Security Architecture](#security-architecture)
8. [Validation Guide](#validation-guide)

---

## Overview

SecureFin is a cloud-native fintech platform deployed on Azure using Terraform for infrastructure-as-code and GitHub Actions for CI/CD automation. The architecture follows these core principles:

- **Zero-secret authentication** via Azure Workload Identity (OIDC)
- **Customer Managed Key (CMK)** encryption for Terraform state
- **Modular, DRY infrastructure** with reusable Terraform modules
- **Environment parity** across dev, staging, and production
- **Branch-based deployment** with safety controls preventing unauthorized applies

---

## Directory Structure

```
securefin-platform/
├── bootstrap/
│   └── state/                    # State backend infrastructure (run once)
│       ├── versions.tf           # Provider version constraints
│       ├── variables.tf          # Input variables
│       ├── main.tf               # RG, Storage, Key Vault, CMK, Identity
│       ├── outputs.tf            # Values needed for backend.hcl
│       └── terraform.tfvars      # Bootstrap variable values
├── infra/
│   └── terraform/
│       ├── modules/
│       │   ├── tags/             # Centralized tagging strategy
│       │   │   ├── variables.tf
│       │   │   ├── main.tf
│       │   │   └── outputs.tf
│       │   └── resource-group/   # Resource group with naming enforcement
│       │       ├── variables.tf
│       │       ├── main.tf
│       │       └── outputs.tf
│       └── environments/
│           ├── dev/              # Development environment
│           ├── staging/          # Staging environment
│           └── production/       # Production environment
│               ├── versions.tf
│               ├── providers.tf
│               ├── backend.tf
│               ├── backend.hcl
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               └── {env}.tfvars
├── docs/                         # Documentation (does NOT trigger CI/CD)
├── .github/
│   └── workflows/
│       └── terraform.yml         # CI/CD pipeline
└── README.md
```

---

## Bootstrap Layer

### Why Bootstrap is Separate

Terraform needs a remote backend (Azure Blob Storage) to store its state files. But that storage account doesn't exist yet — it needs to be created first. This creates a chicken-and-egg problem:

1. **Bootstrap** creates the state storage infrastructure using **local state**
2. **Main infrastructure** then uses the bootstrapped storage as its remote backend

The bootstrap layer:
- Is run **once** by an operator with elevated permissions
- Uses **local state** (committed securely or stored in a vault)
- **Never** participates in CI/CD — it IS the foundation CI/CD depends on

### Why CMK (Customer Managed Key)

In fintech, regulatory frameworks (PCI-DSS, SOC2, ISO 27001) require:
- Encryption keys must be under the organization's control
- Key rotation must be auditable
- Key access must be governed by RBAC

CMK via Azure Key Vault provides:
- **Key rotation** with automatic 90-day policy
- **RBAC-governed access** (no shared secrets for key operations)
- **Audit trail** via Azure Monitor logs
- **Purge protection** ensuring keys cannot be permanently deleted

### Bootstrap Resources Created

| Resource | Purpose |
|----------|---------|
| Resource Group | Isolated container for state resources |
| User Assigned Managed Identity | Identity for CMK access (survives recreates) |
| Key Vault | HSM-backed key storage with purge protection |
| Key Vault Key | RSA-2048 CMK with 90-day rotation |
| Storage Account | GRS-replicated, shared-key-disabled, CMK-encrypted |
| Storage Container | Private blob container for `.tfstate` files |

---

## Module Design

### Tags Module

**Purpose**: Enforce mandatory tagging across all SecureFin resources.

| Tag | Value | Purpose |
|-----|-------|---------|
| Project | SecureFin | Resource identification |
| Environment | dev/staging/production | Environment isolation |
| Owner | DevOps Platform | Incident response ownership |
| CostCenter | SECUREFIN-P1 | Billing chargeback |
| ManagedBy | Terraform | Lifecycle management tracking |

The module accepts `additional_tags` for resource-specific tags while ensuring mandatory tags are always present.

### Resource Group Module

**Purpose**: Create resource groups with enforced naming conventions (`rg-` prefix validation) and mandatory tags.

Each environment creates three isolated resource groups:
- `rg-securefin-core-{env}` — Networking, DNS, shared components
- `rg-securefin-aks-{env}` — AKS cluster resources
- `rg-securefin-data-{env}` — Databases, caches, data stores

---

## Environment Strategy

### Structural Parity

All environments use **identical Terraform structure**. The ONLY differences between environments are expressed through `.tfvars` files:

| File | Purpose |
|------|---------|
| `versions.tf` | Identical across all envs — version pinning |
| `providers.tf` | Identical structure — OIDC auth via variables |
| `backend.tf` | Same config — different `key` per environment |
| `backend.hcl` | Environment-specific storage account values |
| `main.tf` | Identical module calls — values from variables |
| `variables.tf` | Identical declarations |
| `{env}.tfvars` | Environment-specific values (the ONLY difference) |

### State Isolation

Each environment writes to a different state file key in the same storage container:
- `dev.terraform.tfstate`
- `staging.terraform.tfstate`
- `production.terraform.tfstate`

---

## CI/CD Pipeline

### Branching Strategy

```
dev-feature-login  ──push──▶  Plan Only (dev.tfvars)
dev-fix-network    ──push──▶  Plan Only (dev.tfvars)
                                  │
                                  ▼
dev                ──push──▶  Plan + Apply (dev.tfvars)
                                  │
                                  ▼ (merge/PR)
staging            ──push──▶  Plan + Apply (staging.tfvars)
                                  │
                                  ▼ (merge/PR)
production         ──push──▶  Plan + Apply (production.tfvars)
```

### Pipeline Behavior Matrix

| Branch | fmt | init | validate | plan | apply | tfvars |
|--------|-----|------|----------|------|-------|--------|
| `dev-*` | ✅ | ✅ | ✅ | ✅ | ❌ | dev.tfvars |
| `dev` | ✅ | ✅ | ✅ | ✅ | ✅ | dev.tfvars |
| `staging` | ✅ | ✅ | ✅ | ✅ | ✅ | staging.tfvars |
| `production` | ✅ | ✅ | ✅ | ✅ | ✅ | production.tfvars |

### Path Filtering

The pipeline **only triggers** when changes occur in `infra/terraform/**`. Changes to `docs/**` or any other directory will **not** trigger the pipeline.

### Safety Controls

1. **Feature branch protection**: `dev-*` branches can NEVER apply (enforced by conditional logic)
2. **Saved plan files**: Apply uses the exact plan generated earlier — no drift
3. **Concurrency control**: Only one Terraform run per branch at a time
4. **OIDC authentication**: No stored secrets in GitHub

---

## Security Architecture

### Authentication Flow

```
GitHub Actions Runner
        │
        ▼ (request OIDC token)
GitHub OIDC Provider
        │
        ▼ (JWT with repo/branch claims)
Azure AD (validates federation)
        │
        ▼ (issues Azure access token)
Azure Resources (Terraform operations)
```

### Zero-Secret Principles

| Layer | Mechanism | Why |
|-------|-----------|-----|
| CI/CD → Azure | OIDC (Workload Identity) | No client secrets to rotate/leak |
| Terraform → State | Azure AD auth (`use_azuread_auth`) | No storage account keys |
| State → Encryption | CMK via Key Vault | Organization-controlled encryption |
| Key Vault → Access | RBAC (no access policies) | Consistent, auditable authorization |
| Storage Account | `shared_access_key_enabled = false` | Keys physically disabled |

---

## Validation Guide

### Validating Feature Branch Behavior (dev-*)

```bash
# Create and push a feature branch
git checkout -b dev-feature-login
# Make changes to infra/terraform/**
git push origin dev-feature-login
```

**Expected**: Pipeline runs fmt → init → validate → plan. **Apply step is SKIPPED**.

Verify in GitHub Actions: The "Terraform Apply" step shows as skipped with the condition `steps.env-config.outputs.apply_allowed == 'true'` evaluating to `false`.

### Validating Dev Branch

```bash
git checkout dev
git merge dev-feature-login
git push origin dev
```

**Expected**: Pipeline runs fmt → init → validate → plan → **apply** using `dev.tfvars`.

### Validating Staging Branch

```bash
git checkout staging
git merge dev
git push origin staging
```

**Expected**: Pipeline runs fmt → init → validate → plan → **apply** using `staging.tfvars`.

### Validating Production Branch

```bash
git checkout production
git merge staging
git push origin production
```

**Expected**: Pipeline runs fmt → init → validate → plan → **apply** using `production.tfvars`.

### Validating Docs-Only Changes Don't Trigger

```bash
git checkout dev
echo "Updated docs" >> docs/ARCHITECTURE.md
git add docs/
git commit -m "docs: update architecture"
git push origin dev
```

**Expected**: Pipeline does **NOT** trigger. The path filter `infra/terraform/**` does not match `docs/**`.

### Validating OIDC Authentication

In GitHub Actions logs, look for:
```
Run azure/login@v2
  with:
    client-id: ***
    tenant-id: ***
    subscription-id: ***
```

No `client-secret` or `certificate` parameters should appear.

### Validating CMK Encryption

After bootstrap, verify in the Azure Portal:
1. Navigate to the Storage Account → Encryption
2. Confirm "Customer-managed keys" is selected
3. Verify the Key Vault and Key name match bootstrap outputs
