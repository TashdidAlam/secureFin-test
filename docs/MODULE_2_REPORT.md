# SecureFin Platform — Module 2 Complete Report

## Project: secureFin-test

**Repository**: `TashdidAlam/secureFin-test`  
**Report Date**: April 6, 2026  
**Module**: 2 — Security & Compliance Infrastructure  
**Status**: ✅ COMPLETE  

---

## 1. Executive Summary

Module 2 builds the **security and compliance layer** on top of Module 1's Terraform foundation. It delivers:

- **Network infrastructure** — VNet with purpose-built subnets and NSG
- **Private AKS cluster** — Kubernetes 1.33 with Azure CNI, free-tier optimized
- **Workload Identity Federation** — pod-level Azure authentication via OIDC
- **Azure Policy guardrails** — required tags, deny public IPs, allowed locations
- **Kubernetes manifests** — Gatekeeper constraints, network policies, service accounts
- **Post-deployment validation** — 52 automated checks in CI/CD pipeline
- **AzureRM 4.x upgrade** — from 3.80.0 to ~> 4.0 with all breaking changes resolved
- **CI/CD hardening** — 3-job pipeline (plan → apply → validate), Node.js 24 actions

---

## 2. Infrastructure Deployed (Dev Environment)

### Resource Groups

| Resource Group | Location | Purpose |
|----------------|----------|---------|
| `rg-securefin-core-dev` | westus3 | Networking, identity, Log Analytics |
| `rg-securefin-aks-dev` | westus3 | AKS cluster |
| `rg-securefin-data-dev` | westus3 | Future databases/caches |

### Network Resources (in rg-securefin-core-dev)

| Resource | Name | Configuration |
|----------|------|---------------|
| VNet | `vnet-securefin-dev` | 10.0.0.0/16 |
| AKS Subnet | `snet-securefin-aks-dev` | 10.0.1.0/24 |
| PEP Subnet | `snet-securefin-pep-dev` | 10.0.2.0/24 |
| NSG | `nsg-securefin-aks-dev` | Attached to AKS subnet |

### AKS Cluster (in rg-securefin-aks-dev)

| Setting | Value |
|---------|-------|
| Cluster Name | `aks-securefin-dev` |
| Kubernetes Version | 1.33 |
| SKU Tier | Free |
| Network Plugin | Azure CNI |
| Network Policy | Azure |
| API Server Access | Private |
| DNS Prefix | `aks-securefin-dev` |
| Node Pool | `systempool` — 1x Standard_D2s_v3 |
| OS Disk Type | Ephemeral |
| Max Pods | 50 |
| Auto Upgrade | Stable channel |
| Addons | OMS Agent, Key Vault CSI, Azure Policy |
| Identity | SystemAssigned |
| RBAC | Enabled |
| Workload Identity | Enabled |
| OIDC Issuer | Enabled |

### Log Analytics Workspace (in rg-securefin-core-dev)

| Setting | Value |
|---------|-------|
| Name | `law-securefin-dev` |
| SKU | PerGB2018 |
| Retention | 30 days |
| Purpose | AKS container insights, diagnostics |

### Managed Identity (in rg-securefin-core-dev)

| Setting | Value |
|---------|-------|
| Name | `id-securefin-workload-dev` |
| Federated Credential | AKS OIDC → namespace `default`, SA `app-sa` |

### RBAC Assignments

| Role | Principal | Scope |
|------|-----------|-------|
| Network Contributor | AKS cluster identity | AKS subnet |

### Azure Policies (Applied to all 3 RGs)

| Policy | Effect | Description |
|--------|--------|-------------|
| Required Tags | Audit | Enforces Project, Environment, Owner, CostCenter, ManagedBy |
| Deny Public IPs | Deny | Prevents creation of public IP resources |
| Allowed Locations | Deny | Restricts deployments to westus3, westus2 |

---

## 3. Terraform Modules Created

| Module | Files | Purpose |
|--------|-------|---------|
| `modules/tags/` | main.tf, variables.tf, outputs.tf | Mandatory tagging (Module 1) |
| `modules/resource-group/` | main.tf, variables.tf, outputs.tf | RG with naming validation (Module 1) |
| `modules/network/` | main.tf, variables.tf, outputs.tf | VNet, subnets, NSG |
| `modules/aks/` | main.tf, variables.tf, outputs.tf | Private AKS cluster |
| `modules/identity/` | main.tf, variables.tf, outputs.tf | Workload Identity Federation |
| `modules/policy/` | main.tf, variables.tf, outputs.tf | Azure Policy guardrails |

### Module Dependency Chain

```
tags ──► rg_core ──► network ──► aks ──► workload_identity
         rg_aks ─────────────────┘
         rg_data
         All 3 RGs ──► policy
```

---

## 4. Kubernetes Manifests

### Gatekeeper Constraint Templates & Constraints (`k8s/gatekeeper/`)

| Constraint | Purpose |
|------------|---------|
| ACR Only | Restrict container images to Azure Container Registry |
| No Latest Tag | Prevent use of `:latest` image tag |
| Require Resource Limits | Enforce CPU/memory limits on all pods |

### Network Policies (`k8s/network-policies/`)

| Policy | Purpose |
|--------|---------|
| Default Deny | Deny all ingress/egress by default |
| Allow App Traffic | Explicit allowlist for application traffic |

### Workload Identity (`k8s/workload-identity/`)

| Manifest | Purpose |
|----------|---------|
| service-account.yaml | Kubernetes SA annotated for Azure WIF |

---

## 5. CI/CD Pipeline Evolution

### Module 1 Pipeline (2 Jobs)
- Plan → Apply

### Module 2 Pipeline (3 Jobs)
- Plan → Apply → **Validate**

### Key Changes

| Change | Details |
|--------|---------|
| Job 3: Validate | Runs `Post-Deployment-Validation.ps1` after successful apply |
| Action Versions | All upgraded to Node.js 24 compatible versions |
| Provider Version | AzureRM 3.80.0 → ~> 4.0 |
| Provider Registration | `skip_provider_registration` → explicit `resource_providers_to_register` |
| Terraform Version | 1.5.0 (unchanged, constraint: >= 1.5.0) |

### GitHub Actions Versions

| Action | Module 1 | Module 2 |
|--------|----------|----------|
| actions/checkout | v4 | **v6** |
| hashicorp/setup-terraform | v3 | **v4** |
| azure/login | v2 | **v3** |
| terraform-linters/setup-tflint | v4 | **v6** |
| bridgecrewio/checkov-action | v12 | v12 (Docker) |
| actions/upload-artifact | v4 | **v6** |
| actions/download-artifact | v4 | **v7** |

---

## 6. Post-Deployment Validation

**Script**: `scripts/Post-Deployment-Validation.ps1`  
**Total Checks**: 52  
**Result**: 52/52 PASS

| Category | # Checks | What's Validated |
|----------|----------|------------------|
| Resource Groups | 6 | Existence, location (×3 RGs) |
| Tags | 15 | 5 mandatory tags × 3 RGs |
| Network | 6 | VNet CIDR, subnets (×2), NSG, NSG association |
| AKS | 10 | Cluster state, private API, CNI, RBAC, K8s version, addons |
| Log Analytics | 2 | Workspace existence, retention |
| Identity | 2 | Managed identity, federated credential |
| RBAC | 1 | Network Contributor role assignment |
| Policy | 10 | Tag, public IP, location policies across all RGs |

---

## 7. Checkov Security Scan Results

**Mode**: Soft-fail (advisory)  
**5 of 9 findings fixed**; 4 remaining are **unfixable on free-tier AKS**:

| # | Finding | Status | Notes |
|---|---------|--------|-------|
| 1 | AKS network policy | ✅ Fixed | Azure Network Policy enabled |
| 2 | AKS RBAC | ✅ Fixed | `role_based_access_control_enabled = true` |
| 3 | AKS API authorized IP ranges | ❌ Can't fix | Private cluster already; auth IP ranges not supported on free SKU |
| 4 | AKS SLA/uptime | ❌ Can't fix | Requires Standard/Premium SKU ($$$) |
| 5 | AKS disk encryption | ❌ Can't fix | Requires customer-managed key + Key Vault Premium |
| 6 | AKS logging | ✅ Fixed | OMS agent with Log Analytics workspace |
| 7 | NSG on subnet | ✅ Fixed | NSG attached to AKS subnet |
| 8 | Subnet service endpoints | ❌ Can't fix | Not needed for current architecture |
| 9 | Azure CNI | ✅ Fixed | `network_plugin = "azure"` |

---

## 8. AzureRM Provider Upgrade (3.80 → 4.x)

### Breaking Changes Resolved

| Old (v3) | New (v4) | Affected Module |
|----------|----------|-----------------|
| `enable_auto_scaling` | `auto_scaling_enabled` | AKS |
| `skip_provider_registration = true` | `resource_provider_registrations = "none"` | Provider |
| N/A | `resource_providers_to_register = [...]` | Provider |
| AKS `managed` attribute (deprecated) | Removed | AKS |
| Policy `enforce` attribute (deprecated) | Removed | Policy |

---

## 9. Repository Structure (Final)

```
secureFin-test/                         # 47 tracked files
├── .github/workflows/
│   └── terraform.yml                   # CI/CD: Plan → Apply → Validate
├── docs/
│   ├── ARCHITECTURE.md                 # Architecture documentation
│   ├── MODULE_1_REPORT.md              # Module 1 report
│   ├── MODULE_2_REPORT.md              # This report
│   └── ERRORS_AND_SOLUTIONS.md         # Error reference guide
├── infra/terraform/
│   ├── main.tf                         # 6 modules composed
│   ├── variables.tf                    # 5 variables
│   ├── outputs.tf                      # 5 outputs
│   ├── providers.tf                    # AzureRM 4.x, OIDC
│   ├── versions.tf                     # TF >= 1.5.0, AzureRM ~> 4.0
│   ├── backend.tf                      # Azure Blob Storage
│   ├── .terraform.lock.hcl             # Provider lock
│   ├── modules/
│   │   ├── tags/          (3 files)    # Mandatory tagging
│   │   ├── resource-group/(3 files)    # RG + naming validation
│   │   ├── network/       (3 files)    # VNet, subnets, NSG
│   │   ├── aks/           (3 files)    # Private AKS cluster
│   │   ├── identity/      (3 files)    # Workload Identity
│   │   └── policy/        (3 files)    # Azure Policy
│   └── environments/
│       ├── dev/           (2 files)    # backend.hcl + dev.tfvars
│       ├── staging/       (2 files)    # backend.hcl + staging.tfvars
│       └── production/    (2 files)    # backend.hcl + production.tfvars
├── k8s/
│   ├── gatekeeper/
│   │   ├── constraint-templates/ (3)   # ACR-only, no-latest, resource-limits
│   │   └── constraints/          (3)   # Constraint instances
│   ├── network-policies/         (2)   # Default-deny + app traffic
│   └── workload-identity/        (1)   # K8s SA for WIF
├── scripts/
│   └── Post-Deployment-Validation.ps1  # 52-check validation
├── .gitignore
├── .tflint.hcl
└── README.md
```

---

## 10. Commit History (Module 2)

| # | Commit | Description |
|---|--------|-------------|
| 1 | `ca06dd0` | feat(module-2): add security & compliance infrastructure |
| 2 | `ba67078` | fix: address PR review comments (9 issues) |
| 3 | `4584c71` | Merge PR #2: module-2 feature branch → dev |
| 4 | `6b52d14` | fix: upgrade AzureRM provider to 3.117.x for stable AKS API |
| 5 | `ba633aa` | Merge feature branch into dev |
| 6 | `e6affa3` | chore: upgrade AzureRM 4.x, switch to westus3, free-tier optimization |
| 7 | `e928d29` | fix: remove unused client_id variable (tflint) |
| 8 | `727bc55` | fix: refactor policy module — map(string) for static for_each keys |
| 9 | `4dbe41b` | fix: update policy outputs from splat to for_each syntax |
| 10 | `8901d45` | fix: register required resource providers to prevent 404 errors |
| 11 | `dd27480` | vm group changed |
| 12 | `aa7d38e` | refactor: standardize HCL naming + fix Checkov + AKS outbound |
| 13 | `0a60380` | fix(aks): pre-create ContainerInsights solution with tags |
| 14 | `dee2ea4` | ci: add post-deployment validation stage to pipeline |
| 15 | `6d15538` | ci: upgrade GitHub Actions to Node.js 24 compatible versions |

---

## 11. What's Next (Future Modules)

| Item | Priority | Notes |
|------|----------|-------|
| Key Vault integration | High | Secret management for applications |
| Container Registry (ACR) | High | Private registry for container images |
| Database infrastructure | Medium | CosmosDB / Azure SQL in rg-data |
| Ingress Controller | Medium | NGINX or App Gateway for traffic routing |
| Cert Manager | Medium | TLS certificate automation |
| Monitoring dashboards | Low | Azure Workbooks / Grafana |
| Production branch | Low | Create + deploy to production |
| Checkov hard-fail | Low | After resolving free-tier limitations |

---

*This report covers Module 2 — Security & Compliance Infrastructure. All code is committed, deployed, validated (52/52 checks pass), and pushed to the `dev` branch.*
