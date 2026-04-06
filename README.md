# SecureFin Platform — Infrastructure as Code

Production-grade Terraform infrastructure, security & compliance layer, and CI/CD pipeline for the SecureFin fintech platform on Azure.

## Current Status

| Module | Status | Description |
|--------|--------|-------------|
| Module 1 — Foundation & CI/CD | ✅ Complete | Terraform root, modules, pipeline, OIDC auth |
| Module 2 — Security & Compliance | ✅ Complete | Network, AKS, Identity, RBAC, Policy, Validation |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure (westus3)                           │
│                                                             │
│  rg-securefin-core-dev          rg-securefin-aks-dev        │
│  ┌─────────────────────┐       ┌──────────────────────┐    │
│  │ VNet 10.0.0.0/16    │       │ AKS (Private Cluster)│    │
│  │  ├─ aks-subnet      │◄─────►│  K8s 1.33            │    │
│  │  │  10.0.1.0/24     │       │  Azure CNI           │    │
│  │  └─ pep-subnet      │       │  1x Standard_D2s_v3  │    │
│  │     10.0.2.0/24     │       │  Key Vault CSI       │    │
│  │                     │       │  OMS Agent (LAW)     │    │
│  │ Managed Identity    │       │  Azure Policy        │    │
│  │ Log Analytics (LAW) │       │  Ephemeral OS Disk   │    │
│  └─────────────────────┘       └──────────────────────┘    │
│                                                             │
│  rg-securefin-data-dev          Azure Policy               │
│  ┌─────────────────────┐       ┌──────────────────────┐    │
│  │ (Future: databases, │       │ Required Tags        │    │
│  │  caches, storage)   │       │ Deny Public IPs      │    │
│  └─────────────────────┘       │ Allowed Locations    │    │
│                                └──────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Terraform >= 1.5.0 (CI uses 1.5.0, local dev: any >= 1.5.0)
- Azure CLI (`az login`)
- GitHub repository variables configured (see below)

### GitHub Repository Variables

| Variable | Description |
|----------|-------------|
| `AZURE_CLIENT_ID` | App Registration client ID (OIDC federation) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |

### Deploy via CI/CD

```bash
# Feature branch → PR to dev → plan only
git checkout -b feature/my-change
# Make changes to infra/terraform/
git push origin feature/my-change
# Open PR targeting dev → pipeline runs plan

# Merge to dev → auto-apply
# Merge dev → staging → approval required
# Merge staging → production → approval required
```

### Local Development

```bash
az login
cd infra/terraform
terraform init -backend-config=environments/dev/backend.hcl
terraform plan -var-file=environments/dev/dev.tfvars
```

## Project Structure

```
secureFin-test/
├── .github/workflows/
│   └── terraform.yml                  # CI/CD: Plan → Apply → Validate
├── docs/
│   ├── ARCHITECTURE.md                # Full architecture documentation
│   ├── MODULE_1_REPORT.md             # Module 1 completion report
│   └── MODULE_2_REPORT.md             # Module 2 completion report
├── infra/terraform/
│   ├── main.tf                        # Root module composition
│   ├── variables.tf                   # Shared variables
│   ├── outputs.tf                     # Root outputs
│   ├── providers.tf                   # AzureRM provider (OIDC)
│   ├── versions.tf                    # Version constraints
│   ├── backend.tf                     # Azure backend config
│   ├── modules/
│   │   ├── tags/                      # Mandatory tagging
│   │   ├── resource-group/            # RG with naming validation
│   │   ├── network/                   # VNet, subnets, NSG
│   │   ├── aks/                       # Private AKS cluster
│   │   ├── identity/                  # Workload Identity Federation
│   │   └── policy/                    # Azure Policy guardrails
│   └── environments/
│       ├── dev/                       # Dev backend + tfvars
│       ├── staging/                   # Staging backend + tfvars
│       └── production/                # Production backend + tfvars
├── k8s/
│   ├── gatekeeper/                    # OPA constraint templates + constraints
│   ├── network-policies/              # Default-deny + app traffic rules
│   └── workload-identity/             # Kubernetes service account for WIF
├── scripts/
│   └── Post-Deployment-Validation.ps1 # 52-check validation script
├── .gitignore
├── .tflint.hcl                        # TFLint config (terraform + azurerm)
└── README.md
```

## CI/CD Pipeline

Three-job pipeline: **Plan → Apply → Validate**

| Job | Trigger | Description |
|-----|---------|-------------|
| Plan | PR + Push | fmt, tflint, checkov, init, validate, plan |
| Apply | Push only | Downloads plan artifact, applies with approval gates |
| Validate | After Apply | Runs 52-check PowerShell validation script |

### Quality Gates

| Gate | Tool | Mode |
|------|------|------|
| Format | `terraform fmt` | Hard fail |
| Lint | TFLint (azurerm ruleset) | Hard fail |
| Security | Checkov (CIS/PCI/SOC2) | Soft fail |
| Validation | `terraform validate` | Hard fail |
| Approval | GitHub Environments | Blocking (staging/prod) |

## Security

- **Zero-secret architecture** — OIDC authentication, no client secrets or keys
- **Private AKS** — API server not publicly accessible
- **Azure Policy** — required tags, deny public IPs, allowed locations
- **Network Policies** — default-deny with explicit allow rules
- **Workload Identity** — pods authenticate via Kubernetes service accounts
- **Key Vault CSI** — secrets injected as volumes, not env vars
- **Checkov scanning** — shift-left security in CI pipeline

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full architecture, design decisions, auth flows |
| [docs/MODULE_1_REPORT.md](docs/MODULE_1_REPORT.md) | Module 1 completion report |
| [docs/MODULE_2_REPORT.md](docs/MODULE_2_REPORT.md) | Module 2 completion report |
| [docs/ERRORS_AND_SOLUTIONS.md](docs/ERRORS_AND_SOLUTIONS.md) | Notable errors & how they were resolved |
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

---

## Free-Tier Cost Optimization (Trade-offs)

This project is deployed on an Azure **Free Account ($200 credit)**. The following trade-offs were made to minimize costs while preserving the security architecture. All changes are reversible from git history.

### What We Changed vs. Production Config

| Area | Production Config | Free-Tier Config | Monthly Savings |
|------|-------------------|-------------------|-----------------|
| **Node Pools** | 3 pools (system + user + spot) | 1 combined pool | ~$30–60/mo (1 fewer always-on VM) |
| **System Pool Taint** | `CriticalAddonsOnly` (system-only) | Removed (accepts all workloads) | — (enables single-pool) |
| **User Pool** | 1–3 nodes, auto-scaling | Removed | ~$30/mo |
| **Spot Pool** | 0–3 nodes, auto-scaling | Removed | $0 (was already min 0) |
| **VM Size** | `Standard_B2s_v2` | `Standard_B2s_v2` (kept) | — |
| **Total Running VMs** | 2+ (system=1, user=1+) | 1 | ~$30/mo saved |

### Estimated Monthly Cost (Free-Tier Config)

| Resource | SKU/Tier | Estimated Cost |
|----------|----------|----------------|
| AKS Control Plane | Free tier (no SLA) | $0 |
| 1x Standard_B2s_v2 VM | 2 vCPU, 8 GB RAM (burstable) | ~$30/mo |
| 30 GB Managed OS Disk | Standard SSD | ~$2.40/mo |
| VNet / Subnets / NSGs | — | $0 |
| Resource Groups (3) | — | $0 |
| Managed Identity + FIC | — | $0 |
| Azure Policy (RG scope) | — | $0 |
| Private DNS Zone (AKS) | Auto-created for private cluster | ~$0.50/mo |
| **Total** | | **~$33/mo** |

> With $200 credit, this configuration runs for approximately **6 months**.

### What We Kept (Free or Negligible Cost)

These security features are preserved because they are either free or have negligible cost:

- **Private AKS cluster** — API server not exposed to internet
- **OIDC + Workload Identity** — zero-secret pod authentication
- **Azure CNI + Network Policies** — pod-level network segmentation
- **Azure Policy (Gatekeeper)** — admission control inside the cluster
- **Deny-by-default NSGs** — explicit allow rules only
- **Tag enforcement policies** — compliance guardrails at ARM layer
- **Deny public IP policy** — prevents accidental public exposure
- **Location restriction policy** — data residency enforcement
- **Local accounts disabled** — Azure AD-only authentication
- **Kubernetes Network Policies** — default-deny + app-specific allow rules
- **OPA Gatekeeper constraints** — ACR-only images, no latest tag, require resource limits

### How to Restore Production Config

```bash
# View the commit that removed user/spot pools
git log --oneline --all -- infra/terraform/modules/aks/

# Restore the full AKS module from before free-tier optimization
git diff HEAD~1 -- infra/terraform/modules/aks/
```

Key changes to make for production:
1. Add `only_critical_addons_enabled = true` to default_node_pool
2. Re-add `azurerm_kubernetes_cluster_node_pool.user` resource
3. Re-add `azurerm_kubernetes_cluster_node_pool.spot` resource
4. Restore user/spot variables in `modules/aks/variables.tf`
5. Consider upgrading AKS to Standard tier (`sku_tier = "Standard"`) for SLA
