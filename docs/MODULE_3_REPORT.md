# SecureFin Platform — Module 3 Progress Report

**Date:** April 6, 2026
**Author:** DevOps Team
**Scope:** Modules 1–3 (Foundation → Security → CI/CD & GitOps)
**Status:** Module 3 in progress (Steps 1–4 of 7 complete)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Module 1 — Foundation & CI/CD (Complete)](#2-module-1--foundation--cicd)
3. [Module 2 — Security & Compliance (Complete)](#3-module-2--security--compliance)
4. [Module 3 — CI/CD & GitOps (In Progress)](#4-module-3--cicd--gitops)
5. [Repository Structure](#5-repository-structure)
6. [Architecture Diagram](#6-architecture-diagram)
7. [Infrastructure Inventory](#7-infrastructure-inventory)
8. [Security Posture](#8-security-posture)
9. [Cost Analysis](#9-cost-analysis)
10. [What's Next — Remaining Steps](#10-whats-next--remaining-steps)

---

## 1. Executive Summary

The SecureFin platform is a production-grade fintech infrastructure on Azure, built with infrastructure as code (Terraform), automated CI/CD (GitHub Actions), and GitOps (ArgoCD + Helm). The project follows a 3-module approach:

| Module | Status | Commits | Key Deliverables |
|--------|--------|---------|------------------|
| Module 1 — Foundation & CI/CD | ✅ Complete | 15 | Terraform root, 6 modules, 3-job pipeline, OIDC auth |
| Module 2 — Security & Compliance | ✅ Complete | 15+ | Private AKS, VNet, NSG, Workload Identity, Azure Policy, Gatekeeper, 52-check validation |
| Module 3 — CI/CD & GitOps | ⏳ Steps 1–4 of 7 | In progress | GitOps repo, ACR module, App CI pipeline, Dockerfile |

**Zero-secret architecture throughout** — every authentication flow uses OIDC Workload Identity Federation. No passwords, client secrets, or static tokens anywhere.

---

## 2. Module 1 — Foundation & CI/CD

### What Was Built

Module 1 established the Terraform foundation and CI/CD pipeline from scratch.

**Terraform Foundation:**
- Root configuration (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `backend.tf`)
- 3 reusable modules: `tags`, `resource-group` (2 initially, expanded to 3 in M2)
- Environment strategy: single root config + per-environment `tfvars` and `backend.hcl`
- Remote state: Azure Storage Account (`tashdidstatebackup68`) with container `securefin-tfstate`
- Provider: AzureRM (started ~3.80, later upgraded to ~4.0 in Module 2)

**CI/CD Pipeline (`.github/workflows/terraform.yml`):**
- 3-job pipeline: Plan → Apply → Validate
- OIDC authentication via Azure App Registration (`github-oidc-app-securefin`, Client ID: `93ec5cf8-4518-461f-96a6-b44fccf4a456`)
- 4 Federated Identity Credentials (1 per branch: dev, staging, production + pull_request)
- Quality gates: `terraform fmt`, TFLint, Checkov (CIS/PCI/SOC2), `terraform validate`
- GitHub Environment approval for staging/production
- Concurrency control (no parallel applies per environment)
- Node.js 24 compatible actions (`checkout@v6`, `upload-artifact@v6`, etc.)

**Azure OIDC Identity:**
- App Registration: `github-oidc-app-securefin`
- RBAC roles: Contributor, User Access Administrator, Resource Policy Contributor, Storage Blob Data Contributor (all at subscription scope)
- 14 total FICs across both repos (expanded in Module 3)

### Problems Solved

9 issues resolved including: AADSTS700016 (wrong tenant), 403 on state storage (missing Storage Blob Data Contributor), provider registration 404s, and Node.js 20 deprecation (actions upgraded to v6).

---

## 3. Module 2 — Security & Compliance

### What Was Built

Module 2 built the entire security and compliance infrastructure on top of Module 1's foundation.

**Terraform Modules (6 total after M2):**

| Module | Resources | Purpose |
|--------|-----------|---------|
| `tags` | Local values | Centralized compliance tagging (Project, Environment, Owner, CostCenter, ManagedBy) |
| `resource-group` | `azurerm_resource_group` | Reusable RG module (used 3x: core, aks, data) |
| `network` | VNet, 2 subnets, NSG, 4 rules | VNet 10.0.0.0/16, aks-subnet /24, pep-subnet /24, NSG with deny-all-inbound |
| `aks` | AKS cluster, LAW, ContainerInsights | Private cluster, K8s 1.33, Azure CNI, 1 node (free-tier), OIDC + Workload Identity, Azure Policy addon, Key Vault CSI, Secrets Store CSI, local accounts disabled, Azure AD RBAC |
| `identity` | User-Assigned MI, Federated Credential | Workload Identity for pod-to-Azure auth (zero-secret) |
| `policy` | 3 Azure Policy assignments | Required tags, deny public IPs, allowed locations (westus3) |

**Kubernetes Manifests (`k8s/`):**

| Category | Files | Purpose |
|----------|-------|---------|
| Gatekeeper | 3 constraint templates + 3 constraints | ACR-only images, no `:latest` tag, require resource limits |
| Network Policies | 2 policies | Default deny-all + allow-app-traffic (port 8080 ingress, DNS egress) |
| Workload Identity | 1 service account | `app-sa` with `azure.workload.identity/client-id` annotation |

**RBAC Assignments:**
- AKS cluster identity → Network Contributor on AKS subnet
- Workload Identity MI → scoped access for pod-to-Azure communication

**Post-Deployment Validation:**
- `scripts/Post-Deployment-Validation.ps1` — 52 automated checks
- Categories: Resource Groups (6), Networking (9), AKS Cluster (15), Security (8), Identity (6), Compliance (8)
- Result: **52/52 passing** ✅

**Checkov Compliance:**
- 9 checks evaluated, 5 fixed, 4 accepted (free-tier limitations: no availability zones, single node pool, no Defender, no disk encryption set)

### AzureRM 4.x Migration

Provider upgraded from ~3.80 to ~4.0 during Module 2:
- `resource_provider_registrations = "none"` with explicit `resource_providers_to_register` list
- Removed deprecated `default_node_pool.type = "VirtualMachineScaleSets"` (now default)
- Updated identity block syntax

---

## 4. Module 3 — CI/CD & GitOps (In Progress)

Module 3 introduces the application delivery pipeline: a second repository for GitOps, a container registry, a Docker build pipeline, and (upcoming) ArgoCD for continuous deployment.

### 7-Step Implementation Plan

| Step | Status | Description |
|------|--------|-------------|
| 1. GitOps Repo Structure | ✅ Complete | Created `securefin-gitops` repo with Helm chart + ArgoCD ApplicationSet |
| 2. Azure OIDC for GitOps Repo | ✅ Complete | 7 additional FICs for `securefin-gitops` (14 total across both repos) |
| 3. Terraform ACR Module | ✅ Complete | ACR module, AcrPull RBAC, provider registration |
| 4. App CI Pipeline | ✅ Complete | Dockerfile, sample app, build+push pipeline |
| 5. GitOps Update Automation | ⬜ Not Started | CI step to update image tag in gitops repo after push |
| 6. ArgoCD Installation | ⬜ Not Started | Install ArgoCD on AKS cluster |
| 7. ApplicationSet YAML | ⬜ Not Started | Wire ArgoCD ApplicationSet to gitops repo |

---

### Step 1 — GitOps Repository Structure ✅

Created a dedicated `securefin-gitops` repository with the full Helm chart and ArgoCD configuration.

**Repository:** `TashdidAlam/securefin-gitops`
**Branches:** dev, staging, production (mirroring infra repo)

**16 files created:**

```
securefin-gitops/
├── .github/workflows/
│   └── validate.yml              # Helm lint + template dry-run on PRs
├── apps/
│   └── securefin-appset.yaml     # ArgoCD ApplicationSet (3 envs)
├── base/securefin-app/
│   ├── Chart.yaml                # Helm chart metadata (v0.1.0)
│   ├── values.yaml               # Default values (image, replicas, resources)
│   └── templates/
│       ├── _helpers.tpl           # Template helpers (fullname, labels, selectors)
│       ├── deployment.yaml        # Deployment with probes, security context, WI
│       ├── hpa.yaml               # HPA (conditional on autoscaling.enabled)
│       ├── namespace.yaml         # Namespace creation
│       ├── networkpolicy.yaml     # Default deny + app ingress + DNS egress
│       ├── service.yaml           # ClusterIP service
│       └── serviceaccount.yaml    # SA with workload identity annotation
├── environments/
│   ├── dev/values.yaml            # 1 replica, debug logging, no autoscaling
│   ├── staging/values.yaml        # 2 replicas, info logging, autoscaling on
│   └── production/values.yaml     # 3 replicas, warn logging, autoscaling on
├── .gitignore
└── README.md
```

**Key design decisions:**
- Helm chart (not raw manifests) for parameterized, DRY configuration
- ArgoCD ApplicationSet with list generator for multi-env deployment
- Environment-specific values override only what changes (tag, replicas, log level, autoscaling)
- Validate pipeline runs `helm lint` + `helm template --debug` for all 3 envs on every PR

---

### Step 2 — Azure OIDC for GitOps Repo ✅

The existing App Registration (`github-oidc-app-securefin`) was extended with 7 additional Federated Identity Credentials for the `securefin-gitops` repo:

| # | Repo | Subject | Type |
|---|------|---------|------|
| 1–3 | secureFin-test | `repo:TashdidAlam/secureFin-test:ref:refs/heads/{dev,staging,production}` | Branch |
| 4 | secureFin-test | `repo:TashdidAlam/secureFin-test:pull_request` | PR |
| 5–7 | secureFin-test | `repo:TashdidAlam/secureFin-test:environment:{dev,staging,production}` | Environment |
| 8–10 | securefin-gitops | `repo:TashdidAlam/securefin-gitops:ref:refs/heads/{dev,staging,production}` | Branch |
| 11 | securefin-gitops | `repo:TashdidAlam/securefin-gitops:pull_request` | PR |
| 12–14 | securefin-gitops | `repo:TashdidAlam/securefin-gitops:environment:{dev,staging,production}` | Environment |

**GitHub Variables set on `securefin-gitops`:**
- `AZURE_CLIENT_ID` = `93ec5cf8-4518-461f-96a6-b44fccf4a456`
- `AZURE_TENANT_ID` = `63a9a134-4fad-44e4-a0cf-fd45d4185168`
- `AZURE_SUBSCRIPTION_ID` = `48eeedd2-fbbe-4c61-803d-2a8ba099bf0b`

---

### Step 3 — Terraform ACR Module ✅

Created the Azure Container Registry module and integrated it into the root Terraform configuration.

**New files:** `infra/terraform/modules/acr/` (main.tf, variables.tf, outputs.tf)

**ACR Configuration:**
- Name: `acrsecurefindev` (pattern: `acr<project><env>`, globally unique, alphanumeric)
- SKU: Basic (~$5/month, 10 GB storage)
- Admin account: **Disabled** (RBAC-only)
- Anonymous pull: **Disabled**
- Resource group: `rg-securefin-core-dev` (shared service, survives AKS rebuilds)

**Integration changes:**
- `main.tf` — Added `module "acr"` in rg_core + `azurerm_role_assignment.securefin_aks_acr_pull` (AcrPull for kubelet identity with `skip_service_principal_aad_check = true`)
- `providers.tf` — Added `Microsoft.ContainerRegistry` to `resource_providers_to_register`
- `outputs.tf` — Added `acr_name` and `acr_login_server` root outputs

**AcrPull RBAC:**
- Kubelet managed identity (not cluster identity) gets AcrPull on the ACR
- This is the identity that actually runs on nodes and pulls images
- Separation of duties: cluster identity manages Azure resources, kubelet identity pulls images

**GitOps update:** Replaced `<ACR_NAME>` placeholder in `securefin-gitops/base/securefin-app/values.yaml` with `acrsecurefindev`

---

### Step 4 — App CI Pipeline ✅

Created the sample application, multi-stage Dockerfile, and CI pipeline for building and pushing Docker images to ACR.

**Sample Application (`app/`):**

| File | Purpose |
|------|---------|
| `package.json` | Node.js app with Express 4.21 |
| `src/index.js` | Health endpoint (`/healthz`) + root endpoint with version/env metadata |
| `Dockerfile` | Multi-stage: `node:20-alpine` builder → `distroless/nodejs20` runtime |
| `.dockerignore` | Excludes node_modules, .git, docs |

**Dockerfile security hardening:**
- Multi-stage build (no build tools in final image)
- Distroless base (`gcr.io/distroless/nodejs20-debian12:nonroot`) — no shell, no package manager
- Non-root user (UID 1000)
- Production dependencies only (`npm ci --omit=dev`)
- Final image ~120 MB (vs ~900 MB for `node:20` full)

**CI Pipeline (`.github/workflows/app-ci.yml`):**

| Feature | Detail |
|---------|--------|
| Trigger | Push/PR to dev, staging, production when `app/**` changes |
| Auth | OIDC (same vars as Terraform pipeline) |
| PR behavior | Build only (validates Dockerfile) — no push |
| Push behavior | Build + push to ACR |
| Image tags | `<branch>-<sha7>` (unique) + `<branch>-latest` (convenience) |
| ACR naming | Dynamic: `acrsecurefin<branch>` matching Terraform pattern |
| Login method | `az acr login` (OIDC token, no admin password) |
| Labels | OCI labels for source URL and git revision |
| Summary | Job summary table with image metadata |

**Consistency verified across all components:**

| Property | App (`index.js`) | Dockerfile | Helm (`values.yaml`) | Deployment template |
|----------|-------------------|------------|----------------------|---------------------|
| Port | 8080 | EXPOSE 8080 | containerPort: 8080 | containerPort: {{ .Values.containerPort }} |
| Health | `/healthz` | — | — | readiness/liveness probe: `/healthz` |
| User | — | nonroot (UID 1000) | — | runAsUser: 1000 |
| Read-only FS | — | distroless (inherent) | — | readOnlyRootFilesystem: true |

---

## 5. Repository Structure

### secureFin-test (Infrastructure Repo) — 58 files

```
secureFin-test/
├── .github/workflows/
│   ├── terraform.yml                    # Terraform CI/CD (Plan → Apply → Validate)
│   └── app-ci.yml                       # App CI (Build → Push to ACR)       ← NEW (M3)
├── app/                                                                       ← NEW (M3)
│   ├── Dockerfile                       # Multi-stage distroless build
│   ├── .dockerignore
│   ├── package.json
│   └── src/index.js                     # Express app with /healthz
├── docs/
│   ├── ARCHITECTURE.md
│   ├── ERRORS_AND_SOLUTIONS.md          # 22 errors documented
│   ├── MODULE_1_REPORT.md
│   ├── MODULE_2_REPORT.md
│   └── secureFin-project.code-workspace
├── infra/terraform/
│   ├── main.tf                          # 7 modules + 2 RBAC assignments
│   ├── variables.tf / outputs.tf / providers.tf / versions.tf / backend.tf
│   ├── .terraform.lock.hcl
│   ├── environments/
│   │   ├── dev/ (backend.hcl, dev.tfvars)
│   │   ├── staging/ (backend.hcl, staging.tfvars)
│   │   └── production/ (backend.hcl, production.tfvars)
│   └── modules/
│       ├── acr/      (main.tf, variables.tf, outputs.tf)                ← NEW (M3)
│       ├── aks/      (main.tf, variables.tf, outputs.tf)
│       ├── identity/ (main.tf, variables.tf, outputs.tf)
│       ├── network/  (main.tf, variables.tf, outputs.tf)
│       ├── policy/   (main.tf, variables.tf, outputs.tf)
│       ├── resource-group/ (main.tf, variables.tf, outputs.tf)
│       └── tags/     (main.tf, outputs.tf)
├── k8s/
│   ├── gatekeeper/ (3 constraint templates + 3 constraints)
│   ├── network-policies/ (default-deny + allow-app-traffic)
│   └── workload-identity/ (service-account.yaml)
├── scripts/
│   └── Post-Deployment-Validation.ps1   # 52 automated checks
├── .gitignore
├── .tflint.hcl
└── README.md
```

### securefin-gitops (GitOps Repo) — 16 files ← NEW (M3)

```
securefin-gitops/
├── .github/workflows/
│   └── validate.yml                     # Helm lint + template validation
├── apps/
│   └── securefin-appset.yaml            # ArgoCD ApplicationSet
├── base/securefin-app/
│   ├── Chart.yaml
│   ├── values.yaml                      # Default Helm values
│   └── templates/ (7 templates)
├── environments/
│   ├── dev/values.yaml
│   ├── staging/values.yaml
│   └── production/values.yaml
├── .gitignore
└── README.md
```

---

## 6. Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         GitHub (Source of Truth)                          │
│                                                                          │
│  secureFin-test (infra repo)         securefin-gitops (app manifests)    │
│  ┌──────────────────────────┐       ┌──────────────────────────┐        │
│  │ infra/terraform/         │       │ base/securefin-app/      │        │
│  │ app/ (source + Dockerfile│       │   Helm chart + values    │        │
│  │ .github/workflows/       │       │ environments/            │        │
│  │   terraform.yml          │       │   dev/staging/production │        │
│  │   app-ci.yml ────────────┼──┐    │ apps/                    │        │
│  └──────────────────────────┘  │    │   securefin-appset.yaml  │        │
│                                │    └──────────┬───────────────┘        │
│                                │               │                         │
│                     ┌──────────▼───────────┐   │                         │
│                     │ Step 5 (upcoming):   │   │                         │
│                     │ Update image tag in  │───┘                         │
│                     │ gitops repo          │                             │
│                     └──────────────────────┘                             │
└──────────────────────────────────────────────────────────────────────────┘
                              │ OIDC
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        Azure (westus3)                                   │
│                                                                          │
│  rg-securefin-core-dev                rg-securefin-aks-dev               │
│  ┌──────────────────────┐            ┌──────────────────────┐           │
│  │ VNet 10.0.0.0/16     │            │ AKS (Private Cluster)│           │
│  │  ├─ aks-subnet /24   │◄──────────►│  K8s 1.33            │           │
│  │  └─ pep-subnet /24   │            │  Azure CNI           │           │
│  │                       │            │  1x Standard_D2s_v3  │           │
│  │ ACR (acrsecurefindev) │◄─ AcrPull ─│  Kubelet Identity    │           │
│  │  Basic SKU, ~$5/mo   │            │  Key Vault CSI       │           │
│  │                       │            │  Azure Policy/GK     │           │
│  │ Managed Identity      │            │  OMS → LAW           │           │
│  │ Log Analytics (LAW)   │            │  Workload Identity   │           │
│  └──────────────────────┘            └──────────────────────┘           │
│                                                                          │
│  rg-securefin-data-dev                Azure Policy (3 assignments)       │
│  ┌──────────────────────┐            ┌──────────────────────┐           │
│  │ (Future: databases,  │            │ Required Tags         │           │
│  │  caches, storage)    │            │ Deny Public IPs       │           │
│  └──────────────────────┘            │ Allowed Locations     │           │
│                                      └──────────────────────┘           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Infrastructure Inventory

### Azure Resources (dev environment)

| Resource | Name | Resource Group | Details |
|----------|------|----------------|---------|
| Resource Group (core) | `rg-securefin-core-dev` | — | Networking, ACR, Identity, LAW |
| Resource Group (aks) | `rg-securefin-aks-dev` | — | AKS cluster parent |
| Resource Group (data) | `rg-securefin-data-dev` | — | Future data services |
| Virtual Network | `vnet-securefin-dev` | core | 10.0.0.0/16 |
| Subnet (AKS) | `snet-aks-securefin-dev` | core | 10.0.1.0/24 |
| Subnet (PEP) | `snet-pep-securefin-dev` | core | 10.0.2.0/24 |
| NSG | `nsg-securefin-dev` | core | 4 rules (deny-all-inbound default) |
| AKS Cluster | `aks-securefin-dev` | aks | Private, K8s 1.33, SystemAssigned MI |
| LAW | `law-securefin-dev` | aks | ContainerInsights |
| ACR | `acrsecurefindev` | core | Basic SKU, admin disabled |
| Managed Identity | `id-securefin-dev` | core | Workload Identity for pods |
| Federated Credential | `fc-securefin-dev` | core | Links K8s SA → Azure MI |
| Azure Policy | 3 assignments | core/aks/data | Tags, Public IPs, Locations |

### Terraform Modules (7)

| Module | Source | Called From | Key Outputs |
|--------|--------|-------------|-------------|
| `tags` | `./modules/tags` | root | `tags` (map) |
| `rg_core` | `./modules/resource-group` | root | `name`, `id`, `location` |
| `rg_aks` | `./modules/resource-group` | root | `name`, `id`, `location` |
| `rg_data` | `./modules/resource-group` | root | `name`, `id`, `location` |
| `network` | `./modules/network` | root | `aks_subnet_id` |
| `aks` | `./modules/aks` | root | `cluster_id`, `cluster_name`, `oidc_issuer_url`, `cluster_fqdn`, `node_resource_group`, `cluster_identity_principal_id`, `kubelet_identity_object_id` |
| `workload_identity` | `./modules/identity` | root | MI client_id, principal_id |
| `acr` | `./modules/acr` | root | `acr_id`, `acr_name`, `acr_login_server` |

### CI/CD Pipelines (3 total)

| Pipeline | Repo | File | Trigger | Jobs |
|----------|------|------|---------|------|
| Terraform CI/CD | secureFin-test | `terraform.yml` | Push/PR to dev/staging/production (infra changes) | Plan → Apply → Validate |
| App CI | secureFin-test | `app-ci.yml` | Push/PR to dev/staging/production (app changes) | Build → Push to ACR |
| Helm Validate | securefin-gitops | `validate.yml` | PR to dev/staging/production | Lint → Template dry-run |

---

## 8. Security Posture

### Zero-Secret Architecture

| Component | Auth Method | Secret Required? |
|-----------|------------|-----------------|
| GitHub → Azure (CI/CD) | OIDC Workload Identity Federation | ❌ No |
| AKS → ACR (image pull) | Kubelet Managed Identity + AcrPull | ❌ No |
| Pods → Azure (Key Vault, Storage, etc.) | Workload Identity (K8s SA → Azure MI) | ❌ No |
| kubectl → AKS | Azure AD RBAC (`az aks get-credentials`) | ❌ No |
| Docker push (CI) | OIDC → `az acr login` | ❌ No |

### Defense Layers

| Layer | Controls |
|-------|----------|
| Network | Private AKS (no public API), VNet isolation, NSG deny-all-inbound, K8s NetworkPolicies (default-deny + allow-app) |
| Identity | No local accounts, Azure AD RBAC, Workload Identity, no admin passwords anywhere |
| Supply Chain | Gatekeeper: ACR-only images, no `:latest` tag, require resource limits |
| Compliance | Azure Policy: required tags, deny public IPs, allowed locations |
| Container | Distroless base, non-root, read-only filesystem, capabilities dropped |
| Observability | ContainerInsights → LAW, OMS Agent, Azure Policy audit |
| CI/CD | Checkov scanning, TFLint, `terraform fmt`, Helm lint, environment approvals |

### Compliance Checks

- **Post-deployment validation:** 52/52 passing ✅
- **Checkov:** 5/9 fixed (4 accepted: free-tier limitations — no AZ, single pool, no Defender, no disk encryption set)

---

## 9. Cost Analysis

| Resource | Monthly Cost | Notes |
|----------|-------------|-------|
| AKS Control Plane | $0 | Free tier |
| Standard_D2s_v3 (1 node) | ~$28 | 2 vCPU, 8 GB RAM |
| ACR Basic | ~$5 | 10 GB storage |
| Log Analytics | ~$0 | < 1 GB/day (free ingest up to 5 GB/day) |
| Azure Policy | $0 | Included |
| Managed Identity | $0 | Included |
| VNet / NSG | $0 | Included |
| **Total** | **~$33/month** | $200 credit ≈ 6 months |

---

## 10. What's Next — Remaining Steps

### Step 5 — GitOps Update Automation
Add a step to the App CI pipeline that, after pushing an image to ACR, opens a PR (or commits directly) to `securefin-gitops` updating the `image.tag` in the appropriate environment's `values.yaml`. This closes the loop: code commit → image build → manifest update → ArgoCD deploy.

### Step 6 — ArgoCD Installation
Install ArgoCD on the AKS cluster (Helm chart or `kubectl apply`). Configure it to watch the `securefin-gitops` repository. Set up ArgoCD RBAC and ingress (if needed via private endpoint).

### Step 7 — ApplicationSet YAML
The ApplicationSet file already exists (`apps/securefin-appset.yaml`). This step will apply it to ArgoCD, verify the 3 Application resources are created (dev, staging, production), and confirm the full GitOps loop: push to `securefin-gitops` → ArgoCD syncs → AKS deploys.

---

## Appendix: Error Log Summary

22 errors documented across Modules 1–2 in `docs/ERRORS_AND_SOLUTIONS.md`:

| Category | Count | Examples |
|----------|-------|---------|
| Authentication (OIDC) | 4 | Wrong tenant, wrong audience, FIC subject mismatch |
| State Backend | 2 | 403 forbidden, container not found |
| Provider | 3 | Registration 404s, AzureRM 4.x breaking changes |
| AKS | 5 | Quota exceeded, MC_ orphan, ContainerInsights tags |
| CI/CD | 3 | Node.js 20 deprecation, artifact action errors |
| Policy | 2 | Assignment scope, tag enforcement conflicts |
| Other | 3 | Lock file drift, variable validation, format check |

---

*Report generated from the current state of both repositories as of April 6, 2026.*
