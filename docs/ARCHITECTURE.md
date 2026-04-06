# SecureFin Platform - Architecture Documentation

## Table of Contents

1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [State Backend](#state-backend)
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
- **Modular, DRY infrastructure** with 6 reusable Terraform modules
- **Environment parity** across dev, staging, and production
- **Branch-based deployment** with safety controls preventing unauthorized applies
- **Private-by-default** AKS cluster with Azure Policy guardrails
- **Automated post-deployment validation** (52 checks)

---

## Directory Structure

```
secureFin-test/
├── .github/workflows/
│   └── terraform.yml                  # CI/CD: Plan → Apply → Validate (3 jobs)
├── docs/
│   ├── ARCHITECTURE.md                # This document
│   ├── MODULE_1_REPORT.md             # Module 1 completion report
│   ├── MODULE_2_REPORT.md             # Module 2 completion report
│   └── ERRORS_AND_SOLUTIONS.md        # Notable errors & resolutions
├── infra/terraform/
│   ├── main.tf                        # Root module composition (all envs)
│   ├── variables.tf                   # Shared variable declarations
│   ├── outputs.tf                     # Root outputs
│   ├── providers.tf                   # AzureRM 4.x provider (OIDC)
│   ├── versions.tf                    # Terraform >= 1.5.0, AzureRM ~> 4.0
│   ├── backend.tf                     # Azure Blob Storage backend
│   ├── .terraform.lock.hcl            # Provider dependency lock
│   ├── modules/
│   │   ├── tags/                      # Mandatory compliance tagging
│   │   ├── resource-group/            # RG with naming validation (rg- prefix)
│   │   ├── network/                   # VNet, subnets, NSG
│   │   ├── aks/                       # Private AKS cluster
│   │   ├── identity/                  # Workload Identity Federation
│   │   └── policy/                    # Azure Policy guardrails
│   └── environments/
│       ├── dev/                       # backend.hcl + dev.tfvars
│       ├── staging/                   # backend.hcl + staging.tfvars
│       └── production/                # backend.hcl + production.tfvars
├── k8s/
│   ├── gatekeeper/                    # OPA Gatekeeper constraints
│   │   ├── constraint-templates/      # ACR-only, no-latest-tag, resource-limits
│   │   └── constraints/               # Constraint instances
│   ├── network-policies/              # Default-deny + app traffic allowlist
│   └── workload-identity/             # K8s ServiceAccount for WIF
├── scripts/
│   └── Post-Deployment-Validation.ps1 # 52-check PowerShell validation
├── .gitignore                         # Terraform, OS, IDE exclusions
├── .tflint.hcl                        # TFLint with azurerm ruleset
└── README.md
```

### Key Design Decisions

- **Single root, multiple tfvars**: All environments share the same Terraform code. Only `tfvars` and `backend.hcl` differ.
- **No bootstrap directory**: State backend was pre-created manually (chicken-and-egg problem solved pragmatically).
- **Provider registration**: Uses `resource_provider_registrations = "none"` with explicit `resource_providers_to_register` list to avoid 404s from deprecated namespaces.

---

## State Backend

The project uses a pre-created Azure Storage Account for Terraform state:

| Setting | Value |
|---------|-------|
| Storage Account | `tashdidstatebackup68` |
| Resource Group | `rg-securefin-tfstate` |
| Container | `tfstate` |
| Auth Mode | Azure AD RBAC (no shared keys) |
| State Locking | Azure Blob Storage lease (automatic, prevents concurrent modifications) |

---

## Module Design

### Module Dependency Chain

```
tags ──► rg_core ──► network ──► aks ──► workload_identity
         rg_aks ─────────────────┘
         rg_data
         All RGs ──► policy
```

### Tags Module

**Purpose**: Enforce mandatory tagging across all SecureFin resources.

| Tag | Value | Purpose |
|-----|-------|---------|
| Project | SecureFin | Resource identification |
| Environment | dev/staging/production | Environment isolation |
| Owner | DevOps Platform | Incident response ownership |
| CostCenter | SECUREFIN-P1 | Billing chargeback |
| ManagedBy | Terraform | Lifecycle management tracking |

### Resource Group Module

**Purpose**: Create resource groups with enforced naming conventions (`rg-` prefix validation) and mandatory tags.

Three isolated resource groups per environment:
- `rg-securefin-core-{env}` — Networking, DNS, shared components
- `rg-securefin-aks-{env}` — AKS cluster resources
- `rg-securefin-data-{env}` — Databases, caches, data stores

### Network Module

**Purpose**: VNet with purpose-built subnets and NSG.

| Resource | Configuration |
|----------|---------------|
| VNet | `vnet-securefin-{env}`, 10.0.0.0/16 |
| AKS Subnet | `snet-securefin-aks-{env}`, 10.0.1.0/24 |
| PEP Subnet | `snet-securefin-pep-{env}`, 10.0.2.0/24 |
| NSG | `nsg-securefin-aks-{env}`, attached to AKS subnet |

**Location**: `rg-securefin-core-{env}` (shared service, independent of compute lifecycle).

### AKS Module

**Purpose**: Private Kubernetes cluster optimized for free-tier with production-grade settings.

| Setting | Value |
|---------|-------|
| Cluster Name | `aks-securefin-{env}` |
| Kubernetes Version | 1.33 (auto-upgrade: stable channel) |
| SKU | Free |
| Network Plugin | Azure CNI |
| Network Policy | Azure |
| API Server | Private (not publicly accessible) |
| Node Pool | 1x Standard_D2s_v3, ephemeral OS disk, max_pods=50 |
| Addons | OMS Agent (LAW), Key Vault CSI, Azure Policy |
| Identity | SystemAssigned |

**RBAC**: AKS cluster identity gets Network Contributor on the AKS subnet for Azure CNI IP management.

### Identity Module

**Purpose**: Workload Identity Federation for pod-level Azure authentication.

| Resource | Configuration |
|----------|---------------|
| Managed Identity | `id-securefin-workload-{env}` in `rg-securefin-core-{env}` |
| Federated Credential | Bound to AKS OIDC issuer, namespace `default`, SA `app-sa` |

**Why in core RG**: Identity survives AKS rebuilds — RBAC assignments to Key Vault, Storage, etc. persist.

### Policy Module

**Purpose**: Azure Policy guardrails applied to all three resource groups.

| Policy | Effect | Description |
|--------|--------|-------------|
| Required Tags | Audit | Project, Environment, Owner, CostCenter, ManagedBy |
| Deny Public IPs | Deny | Zero public-facing resources |
| Allowed Locations | Deny | Restrict to westus3, westus2 |

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

| Event | Target Branch | Plan | Apply | Validate |
|-------|---------------|------|-------|----------|
| `pull_request` | dev | ✅ | ❌ | ❌ |
| `pull_request` | staging | ✅ | ❌ | ❌ |
| `pull_request` | production | ✅ | ❌ | ❌ |
| `push` | dev | ✅ | ✅ (auto) | ✅ |
| `push` | staging | ✅ | ⏸️ (approval) | ✅ |
| `push` | production | ✅ | ⏸️ (approval) | ✅ |

### Pipeline Architecture (3 Jobs)

```
┌──────────────────────────────────────────────────────┐
│              JOB 1: PLAN (always runs)                │
│  checkout → env-detect → setup-terraform → azure     │
│  login → fmt → tflint → checkov → init → validate    │
│  → plan → upload-artifact (push only)                 │
└──────────────────┬───────────────────────────────────┘
                   │ (only if push event)
                   ▼
┌──────────────────────────────────────────────────────┐
│     JOB 2: APPLY (push only, with approval)           │
│  checkout → setup-terraform → azure login → init      │
│  → download-artifact → terraform apply tfplan          │
└──────────────────┬───────────────────────────────────┘
                   │ (only if apply succeeded)
                   ▼
┌──────────────────────────────────────────────────────┐
│     JOB 3: VALIDATE (post-deployment)                 │
│  checkout → azure login → Post-Deployment-Validation  │
│  → 52 automated checks (RG, network, AKS, LAW,       │
│    identity, RBAC, policy)                             │
└──────────────────────────────────────────────────────┘
```

### GitHub Actions Versions (Node.js 24)

| Action | Version | Notes |
|--------|---------|-------|
| actions/checkout | v6 | Node.js 24 |
| hashicorp/setup-terraform | v4 | Node.js 24 |
| azure/login | v3 | Node.js 24 |
| terraform-linters/setup-tflint | v6 | Node.js 24 |
| bridgecrewio/checkov-action | v12 | Docker-based (not affected) |
| actions/upload-artifact | v6 | Node.js 24 |
| actions/download-artifact | v7 | Node.js 24 |

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
Run azure/login@v3
  with:
    client-id: ***
    tenant-id: ***
    subscription-id: ***
```

No `client-secret` or `certificate` parameters should appear.

### Post-Deployment Validation

After a successful apply, Job 3 runs `Post-Deployment-Validation.ps1` which performs 52 automated checks:

| Category | Checks |
|----------|--------|
| Resource Groups | Existence, location, mandatory tags |
| Network | VNet CIDR, subnets, NSG association |
| AKS | Cluster state, private API, Azure CNI, RBAC, addons |
| Log Analytics | Workspace existence, retention |
| Identity | Managed identity, federated credential |
| RBAC | Network Contributor on AKS subnet |
| Policy | Tag, public IP, location policy assignments |
| Kubernetes | Node pool config, OMS agent, Key Vault CSI |

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
