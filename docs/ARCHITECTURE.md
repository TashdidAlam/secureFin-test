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
- **Single shared Terraform root** — environments differ only by tfvars
- **Modular, DRY infrastructure** with reusable Terraform modules
- **Environment parity** across dev, staging, and production
- **Branch-based deployment** with safety controls preventing unauthorized applies

---

## Directory Structure

```
securefin-platform/
├── bootstrap/
│   └── state/                    # State backend infrastructure (run once)
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
├── infra/
│   └── terraform/
│       ├── main.tf               # Shared root — all environments use this
│       ├── variables.tf          # Shared variable declarations
│       ├── outputs.tf            # Shared outputs
│       ├── providers.tf          # AzureRM provider (auth via ARM_* env vars)
│       ├── versions.tf           # Terraform & provider version constraints
│       ├── backend.tf            # Backend config (values from backend.hcl)
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
│           ├── dev/
│           │   ├── backend.hcl   # Backend values + state key
│           │   └── dev.tfvars    # Dev-specific variable values
│           ├── staging/
│           │   ├── backend.hcl
│           │   └── staging.tfvars
│           └── production/
│               ├── backend.hcl
│               └── production.tfvars
├── docs/
├── .github/
│   └── workflows/
│       └── terraform.yml         # CI/CD pipeline
└── README.md
```

### Key Design Decision: Shared Root

All Terraform configuration files (main.tf, variables.tf, outputs.tf, providers.tf, versions.tf, backend.tf) live in a **single root directory** (`infra/terraform/`). Environments are differentiated solely by:

- **tfvars files** — environment-specific variable values (environment name, location, etc.)
- **backend.hcl files** — backend configuration including the state file key

This eliminates code duplication across environments. Adding a new resource or module is a single change — no need to edit 3 identical files.

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

### State Backend

The project uses a pre-created Azure Storage Account for Terraform state:

| Setting | Value |
|---------|-------|
| Storage Account | `tashdidstatebackup68` |
| Resource Group | `rg-securefin-tfstate` |
| Container | `tfstate` |
| Auth Mode | Azure AD RBAC (no shared keys) |

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

The module accepts `additional_tags` for resource-specific tags while ensuring mandatory tags always win via merge order.

### Resource Group Module

**Purpose**: Create resource groups with enforced naming conventions (`rg-` prefix validation) and mandatory tags.

Each environment creates three isolated resource groups:
- `rg-securefin-core-{env}` — Networking, DNS, shared components
- `rg-securefin-aks-{env}` — AKS cluster resources
- `rg-securefin-data-{env}` — Databases, caches, data stores

---

## Environment Strategy

### Single Root, Multiple tfvars

Unlike the traditional "copy-paste environment directories" pattern, SecureFin uses a **single Terraform root** with environment-specific data files:

| File | Location | Shared? |
|------|----------|---------|
| `main.tf` | `infra/terraform/` | Yes — all envs |
| `variables.tf` | `infra/terraform/` | Yes — all envs |
| `outputs.tf` | `infra/terraform/` | Yes — all envs |
| `providers.tf` | `infra/terraform/` | Yes — all envs |
| `versions.tf` | `infra/terraform/` | Yes — all envs |
| `backend.tf` | `infra/terraform/` | Yes — all envs |
| `backend.hcl` | `environments/{env}/` | Per-env |
| `{env}.tfvars` | `environments/{env}/` | Per-env |

### State Isolation

Each environment writes to a different state file key in the same storage container:
- `dev.terraform.tfstate`
- `staging.terraform.tfstate`
- `production.terraform.tfstate`

The key is specified in each environment's `backend.hcl`.

### Authentication

Azure identity values are **NOT in Terraform variables or tfvars files**. They are passed as `ARM_*` environment variables which the AzureRM provider reads automatically:

| Env Var | Source | Purpose |
|---------|--------|---------|
| `ARM_CLIENT_ID` | `vars.AZURE_CLIENT_ID` | App Registration client ID |
| `ARM_TENANT_ID` | `vars.AZURE_TENANT_ID` | Azure AD tenant ID |
| `ARM_SUBSCRIPTION_ID` | `vars.AZURE_SUBSCRIPTION_ID` | Target subscription |
| `ARM_USE_OIDC` | `true` | Enable OIDC auth |
| `ARM_USE_AZUREAD` | `true` | Azure AD auth for storage |

For local development, use `az login` — the provider auto-detects the CLI session.

---

## CI/CD Pipeline

### Trigger Model

The pipeline triggers on **pull requests** targeting `dev`, `staging`, or `production`:

```
feature-branch  ──PR → dev──▶  Plan ONLY (dev.tfvars)
dev             ──PR → staging──▶  Plan ONLY (staging.tfvars)
staging         ──PR → production──▶  Plan ONLY (production.tfvars)
```

Apply is gated on push events (post-merge). The current FIC is configured for `pull_request` subject type, so only PRs authenticate successfully.

### Pipeline Steps

| Step | Working Dir | Description |
|------|-------------|-------------|
| Checkout | repo root | Fetch repository code |
| Env Detect | repo root | Resolve backend.hcl and tfvars paths |
| Setup Terraform | — | Install pinned Terraform version |
| Azure Login | — | OIDC token exchange with Azure AD |
| Format Check | `infra/terraform` | `terraform fmt -check -recursive` |
| TFLint | `infra/terraform` | Azure-aware linting |
| Checkov | `infra/terraform` | Security & compliance scan (soft-fail) |
| Init | `infra/terraform` | `terraform init -backend-config=environments/{env}/backend.hcl` |
| Validate | `infra/terraform` | Syntax and consistency check |
| Plan | `infra/terraform` | `terraform plan -var-file=environments/{env}/{env}.tfvars` |
| Apply | `infra/terraform` | Conditional — only on push events |

### Path Filtering

The pipeline **only triggers** when changes occur outside `docs/**`. Documentation-only changes do not trigger the pipeline.

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
| Key Vault → Access | RBAC (no access policies) | Consistent, auditable authorization |
| Storage Account | `shared_access_key_enabled = false` | Keys physically disabled |

### GitHub Repository Variables

Azure identity values are stored as **repository variables** (not secrets) because they are non-sensitive GUIDs:

| Variable | Purpose |
|----------|---------|
| `AZURE_CLIENT_ID` | App Registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |

---

## Validation Guide

### Validating PR Behavior (Plan Only)

```bash
# Create a feature branch and open a PR to dev
git checkout -b feature-login
# Make changes to infra/terraform/**
git push origin feature-login
# Open PR targeting dev branch
```

**Expected**: Pipeline runs fmt → tflint → checkov → init → validate → plan. **Apply step is SKIPPED**.

### Validating Docs-Only Changes Don't Trigger

```bash
echo "Updated docs" >> docs/ARCHITECTURE.md
git add docs/ && git commit -m "docs: update"
git push origin feature-branch
```

**Expected**: Pipeline does **NOT** trigger.

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

### Local Development

```bash
# Login with Azure CLI
az login
az account set --subscription "48eeedd2-fbbe-4c61-803d-2a8ba099bf0b"

# Run Terraform from the shared root
cd infra/terraform
terraform init -backend-config=environments/dev/backend.hcl
terraform plan -var-file=environments/dev/dev.tfvars
```
