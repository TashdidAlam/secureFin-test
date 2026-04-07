# SecureFin Platform — Comprehensive Progress Report

**Date:** April 7, 2026
**Author:** DevOps Team
**Scope:** All 3 repositories — Infrastructure, Application, GitOps
**Branch:** `feature/network-dns-rework` (pending merge to `dev`)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Repository Overview](#2-repository-overview)
3. [Module 1 — Foundation & CI/CD (Complete)](#3-module-1--foundation--cicd)
4. [Module 2 — Security & Compliance (Complete)](#4-module-2--security--compliance)
5. [Module 3 — CI/CD & GitOps (Steps 1–4 Complete)](#5-module-3--cicd--gitops)
6. [Bastion Infrastructure (Complete)](#6-bastion-infrastructure)
7. [Network & DNS Rework (Current Branch)](#7-network--dns-rework)
8. [App Exposure Plan](#8-app-exposure-plan)
9. [Updated Architecture](#9-updated-architecture)
10. [Full Infrastructure Inventory](#10-full-infrastructure-inventory)
11. [Security Posture](#11-security-posture)
12. [Cost Analysis](#12-cost-analysis)
13. [Issues Resolved](#13-issues-resolved)
14. [What's Next](#14-whats-next)

---

## 1. Executive Summary

The SecureFin platform is a **production-grade fintech infrastructure** on Azure, built with Terraform, GitHub Actions, and GitOps (ArgoCD + Helm). The project follows a modular approach across **3 repositories**:

| Phase | Status | Key Deliverables |
|-------|--------|------------------|
| Module 1 — Foundation & CI/CD | ✅ Complete | Terraform root, 6 modules, 3-job pipeline, OIDC auth |
| Module 2 — Security & Compliance | ✅ Complete | Private AKS, VNet, NSG, Workload Identity, Azure Policy, 52-check validation |
| Module 3 — CI/CD & GitOps (Steps 1-4) | ✅ Complete | GitOps repo, ACR module, App CI pipeline, Helm charts |
| Module 3 — GitOps (Steps 5-7) | ⬜ Pending | GitOps update automation, ArgoCD install, ApplicationSet |
| Bastion Infrastructure | ✅ Deployed | Bastion + Jump Box in hub VNet, VNet peering |
| Network & DNS Rework | ⏳ In Progress | Custom DNS zones, CIDR fix, UserAssigned identity (on feature branch) |

**Zero-secret architecture throughout** — every authentication flow uses OIDC Workload Identity Federation.

---

## 2. Repository Overview

### 2.1 secureFin-test (Infrastructure)

**Repository:** `TashdidAlam/secureFin-test`
**Branches:** `main`, `dev`, `staging`, `feature/network-dns-rework`
**Purpose:** Terraform IaC, CI/CD pipelines, Kubernetes manifests, documentation

```
secureFin-test/
├── .github/workflows/
│   ├── terraform.yml              # Terraform CI/CD (Plan → Apply → Validate)
│   └── app-ci.yml                 # App CI (Build → Push to ACR)
├── app/                           # Sample Node.js app + Dockerfile
├── docs/                          # All documentation (this file)
├── infra/terraform/
│   ├── main.tf                    # Root orchestration (9 modules + RBAC)
│   ├── variables.tf / outputs.tf / providers.tf / versions.tf / backend.tf
│   ├── environments/{dev,staging,production}/
│   └── modules/
│       ├── acr/                   # Azure Container Registry
│       ├── aks/                   # Private AKS cluster
│       ├── bastion/               # Bastion + Jump Box (hub VNet)
│       ├── dns/                   # Private DNS zones      ← NEW (this branch)
│       ├── identity/              # Workload Identity federation
│       ├── network/               # VNet, subnets, NSG
│       ├── policy/                # Azure Policy assignments
│       ├── resource-group/        # Reusable RG module
│       └── tags/                  # Compliance tagging
├── k8s/                           # Gatekeeper, NetworkPolicies, ServiceAccount
└── scripts/                       # Post-deployment validation (52 checks)
```

### 2.2 secureFin-app (Application)

**Repository:** `TashdidAlam/secureFin-app`
**Branches:** `dev`, `staging`, `production`
**Purpose:** Application source code and CI pipeline

```
secureFin-app/
├── .github/workflows/
│   └── app-ci.yml                 # Build + Trivy scan + Push to ACR
├── src/
│   └── index.js                   # Express app with /healthz endpoint
├── Dockerfile                     # Multi-stage (node:20-alpine → distroless)
├── package.json / package-lock.json
├── .dockerignore
└── .trivy.yaml                    # Trivy security scanner config
```

**CI Pipeline Features:**
- OIDC authentication (zero secrets)
- Multi-stage Docker build
- Trivy vulnerability scanning (CRITICAL/HIGH)
- Image tags: `<branch>-<sha7>` + `<branch>-latest`
- ACR push via `az acr login` (OIDC, no admin password)

### 2.3 securefin-gitops (GitOps)

**Repository:** `TashdidAlam/securefin-gitops`
**Branches:** `dev`, `staging`, `production`
**Purpose:** Helm charts and ArgoCD ApplicationSet for GitOps deployment

```
securefin-gitops/
├── .github/workflows/
│   └── validate.yml               # Helm lint + template dry-run
├── apps/
│   └── securefin-appset.yaml      # ArgoCD ApplicationSet (3 envs)
├── base/securefin-app/
│   ├── Chart.yaml                 # Helm chart v0.1.0
│   ├── values.yaml                # Default values
│   └── templates/                 # 7 Helm templates
│       ├── deployment.yaml        # With probes, security context, WI
│       ├── service.yaml           # ClusterIP service
│       ├── networkpolicy.yaml     # Default deny + app allow
│       ├── serviceaccount.yaml    # With workload identity annotation
│       ├── hpa.yaml               # Horizontal Pod Autoscaler
│       ├── namespace.yaml
│       └── _helpers.tpl
├── environments/
│   ├── dev/values.yaml            # 1 replica, debug logging
│   ├── staging/values.yaml        # 2 replicas, autoscaling on
│   └── production/values.yaml     # 3 replicas, autoscaling on
└── README.md
```

---

## 3. Module 1 — Foundation & CI/CD

**Status:** ✅ Complete | **Report:** `docs/MODULE_1_REPORT.md`

### Deliverables

- Terraform root configuration with environment-specific tfvars
- 3 reusable modules: `tags`, `resource-group` (initial set)
- Remote state backend: Azure Storage Account (`tashdidstatebackup68`)
- 3-job CI/CD pipeline: Plan → Apply → Validate
- OIDC authentication via Azure App Registration
- 4 Federated Identity Credentials (dev, staging, production, pull_request)
- Quality gates: `terraform fmt`, TFLint, Checkov (CIS/PCI/SOC2)

### Azure Identity

| Property | Value |
|---|---|
| App Registration | `github-oidc-app-securefin` |
| Client ID | `93ec5cf8-4518-461f-96a6-b44fccf4a456` |
| Tenant ID | `63a9a134-4fad-44e4-a0cf-fd45d4185168` |
| Subscription ID | `48eeedd2-fbbe-4c61-803d-2a8ba099bf0b` |

---

## 4. Module 2 — Security & Compliance

**Status:** ✅ Complete | **Report:** `docs/MODULE_2_REPORT.md`

### Deliverables

| Module | Purpose |
|--------|---------|
| `network` | VNet 10.0.0.0/16, AKS subnet /24, PEP subnet /24, NSG |
| `aks` | Private cluster, K8s 1.33, Azure CNI, OIDC, Workload Identity |
| `identity` | User-Assigned MI with federated credential for pod auth |
| `policy` | Required tags, deny public IPs, allowed locations |

- Kubernetes manifests: Gatekeeper constraints, NetworkPolicies, ServiceAccount
- Post-deployment validation: **52/52 checks passing**
- AzureRM provider upgraded from ~3.80 to ~4.0

---

## 5. Module 3 — CI/CD & GitOps

**Status:** Steps 1–4 ✅ Complete, Steps 5–7 ⬜ Pending | **Report:** `docs/MODULE_3_REPORT.md`

| Step | Status | Description |
|------|--------|-------------|
| 1. GitOps Repo Structure | ✅ | Helm chart + ArgoCD ApplicationSet in `securefin-gitops` |
| 2. OIDC for GitOps Repo | ✅ | 14 total FICs across both repos |
| 3. ACR Module | ✅ | `acrsecurefindev`, Basic SKU, AcrPull RBAC |
| 4. App CI Pipeline | ✅ | Dockerfile, Trivy scan, build+push pipeline |
| 5. GitOps Update Automation | ⬜ | CI step to update image tag in gitops repo |
| 6. ArgoCD Installation | ⬜ | Install ArgoCD on AKS |
| 7. ApplicationSet YAML | ⬜ | Apply ApplicationSet, verify GitOps loop |

---

## 6. Bastion Infrastructure

**Status:** ✅ Deployed on `dev` branch

### Why Bastion?

AKS is a **private cluster** — the API server has no public endpoint. To run `kubectl` commands, we need a jump box inside a peered VNet. Azure Bastion provides secure, browser-based SSH to the jump box without exposing any public ports.

### Architecture

```
Internet
    │
    ▼
Azure Bastion (pip-bastion-securefin)
    │ SSH over HTTPS (port 443)
    ▼
┌─────────────────────────────────────────────────┐
│ Bastion VNet (10.2.0.0/16)                      │
│  ├── AzureBastionSubnet (10.2.0.0/26)           │
│  └── snet-jumpbox (10.2.1.0/27)                 │
│       └── Jump Box VM (Standard_D2s_v3)         │
│           Ubuntu 24.04, cloud-init:             │
│           kubectl, helm, az-cli, kubelogin      │
└────────────── VNet Peering ─────────────────────┘
                    ↕
┌─────────────────────────────────────────────────┐
│ Env VNet (10.0.0.0/16)                          │
│  ├── snet-aks (10.0.1.0/24) → AKS nodes        │
│  └── snet-pep (10.0.2.0/24) → Private endpoints│
└─────────────────────────────────────────────────┘
```

### Resources Created

| Resource | Name | Details |
|----------|------|---------|
| Resource Group | `rg-securefin-bastion` | Isolated lifecycle, separate from workloads |
| VNet | Bastion VNet | 10.2.0.0/16 (separate from env VNet) |
| Subnet | AzureBastionSubnet | 10.2.0.0/26 (required name for Bastion) |
| Subnet | snet-jumpbox | 10.2.1.0/27 |
| NSG | jumpbox-nsg | SSH from VNet only, deny internet |
| VNet Peering | Bidirectional | Bastion VNet ↔ Env VNet |
| Public IP | pip-bastion-securefin | Required by Azure Bastion (exempt from deny-public-IP policy) |
| Bastion Host | Standard SKU | Browser-based SSH, no public ports on VM |
| Jump Box VM | Standard_D2s_v3 | 2 vCPU, 8 GB RAM, Ubuntu 24.04 LTS |
| SSH Key | TLS-generated | Private key in Terraform output (sensitive) |

### Design Decisions

- **Separate VNet (hub-spoke):** Bastion is a shared admin tool — one Bastion serves all environments via VNet peering
- **Separate RG:** Independent lifecycle; destroy/recreate without affecting workloads
- **Cloud-init provisioning:** kubectl, helm, az-cli, kubelogin installed automatically on first boot
- **No public IP on VM:** All access through Azure Bastion tunnel only

---

## 7. Network & DNS Rework

**Status:** ⏳ On feature branch `feature/network-dns-rework` (not yet deployed)
**Impact:** AKS cluster will be **destroyed and recreated** (ForceNew from identity type + DNS zone changes)

### Problems Fixed

#### 7.1 CIDR Overlap (Critical)

**Problem:** Bastion VNet CIDR (`10.1.0.0/16`) overlapped with AKS `service_cidr` (`10.1.0.0/16`). This would cause routing conflicts — Kubernetes ClusterIP traffic could collide with Bastion VNet traffic.

**Fix:** Changed Bastion VNet from `10.1.0.0/16` to `10.2.0.0/16`.

| Network | Before | After |
|---------|--------|-------|
| Env VNet | 10.0.0.0/16 | 10.0.0.0/16 (unchanged) |
| AKS service_cidr | 10.1.0.0/16 | 10.1.0.0/16 (unchanged) |
| Bastion VNet | 10.1.0.0/16 ⚠️ | **10.2.0.0/16** ✅ |
| AzureBastionSubnet | 10.1.0.0/26 | **10.2.0.0/26** |
| snet-jumpbox | 10.1.1.0/27 | **10.2.1.0/27** |

#### 7.2 DNS Zone Discovery Hack (Maintenance Risk)

**Problem:** AKS in "System" DNS mode creates a private DNS zone with a randomly-generated GUID prefix (e.g., `a1b2c3d4-xxxx.privatelink.westus3.azmk8s.io`). The Terraform code used a fragile `data.azurerm_resources` lookup with string filtering to discover this zone name — this would break if AKS changed naming conventions.

**Fix:** Created a dedicated `dns` module that provisions our own predictable DNS zone (`privatelink.westus3.azmk8s.io`) and passes it to AKS via `private_dns_zone_id`.

#### 7.3 Identity Circular Dependency

**Problem:** Custom private DNS zones require the AKS identity to have "Private DNS Zone Contributor" role **before** the cluster is created. With `SystemAssigned` identity, the identity doesn't exist until the cluster is created → circular dependency.

**Fix:**
1. Changed AKS from `SystemAssigned` to `UserAssigned` identity
2. Created the managed identity at root level (`azurerm_user_assigned_identity.aks_identity`)
3. Granted RBAC roles (Network Contributor + DNS Contributor) on the identity
4. Passed the identity to the AKS module
5. AKS module uses `depends_on` to wait for RBAC before provisioning

### New DNS Module (`modules/dns/`)

```
modules/dns/
├── main.tf         # DNS zone + 2 VNet links
├── variables.tf    # resource_group_name, location, env_vnet_id, bastion_vnet_id
└── outputs.tf      # aks_dns_zone_id, aks_dns_zone_name
```

**Resources:**

| Resource | Name | Purpose |
|----------|------|---------|
| Private DNS Zone | `privatelink.westus3.azmk8s.io` | AKS API server name resolution |
| VNet Link | `dnslink-aks-to-env-dev` | Env VNet can resolve AKS API | 
| VNet Link | `dnslink-aks-to-bastion-dev` | Bastion VNet can resolve AKS API (kubectl from jump box) |

### Files Changed (6 modified, 3 created)

| File | Change |
|------|--------|
| `main.tf` | +99 lines: Added UserAssigned identity, DNS module, DNS Contributor RBAC, removed data source hack, removed bastion DNS params, updated CIDR comments |
| `modules/aks/main.tf` | Changed identity to UserAssigned, added `private_dns_zone_id`, removed internal identity resource |
| `modules/aks/variables.tf` | Added `private_dns_zone_id`, `aks_identity_id` variables |
| `modules/aks/outputs.tf` | Removed `cluster_identity_principal_id` (now at root level) |
| `modules/bastion/main.tf` | Removed DNS zone link resource (now in dns module), updated CIDR comments |
| `modules/bastion/variables.tf` | Changed CIDRs to 10.2.x, removed 3 DNS variables |
| `modules/dns/main.tf` | **NEW** — DNS zone + VNet links |
| `modules/dns/variables.tf` | **NEW** — 6 input variables |
| `modules/dns/outputs.tf` | **NEW** — 2 outputs |

### Dependency Chain (Updated)

```
tags ──→ RGs (core, aks, data) ──→ network ──→ bastion
                                       │            │
                                       │            ▼
                                       │         dns module
                                       │            │
                                       ▼            ▼
                                  aks_identity ──→ RBAC (Network + DNS Contributor)
                                                     │
                                                     ▼
                                                    AKS (depends_on RBAC)
                                                     │
                                                     ▼
                                              workload_identity
                                                     │
                                       ┌─────────────┤
                                       ▼             ▼
                                      ACR        AcrPull RBAC
                                                     │
                                                     ▼
                                                   Policy
```

### Best Practices Applied (from Microsoft AKS Baseline Architecture)

| Practice | Status | Notes |
|----------|--------|-------|
| Hub-spoke VNet topology | ✅ Implemented | Bastion VNet (hub) peered with Env VNet (spoke) |
| Custom private DNS zones | ✅ This branch | Predictable zone names, full VNet link control |
| UserAssigned managed identity | ✅ This branch | Required for custom DNS, better lifecycle management |
| Bidirectional VNet peering | ✅ Implemented | Traffic flows both directions |
| Private cluster (no public API) | ✅ Module 2 | API server private endpoint only |
| Azure CNI networking | ✅ Module 2 | Real VNet IPs for pods |
| Workload Identity (zero-secret) | ✅ Module 2 | OIDC federated credentials |
| NGINX Ingress + Internal LB | ⬜ Planned | See App Exposure Plan below |
| Application Gateway (WAF) | ⬜ Future | For production environments |
| Azure Firewall (egress control) | ⬜ Future | For production environments |

---

## 8. App Exposure Plan

### Current State

The application is deployed inside a **private AKS cluster** with:
- `ClusterIP` service (internal only)
- No ingress controller
- No load balancer
- No public IP

**The app is NOT currently accessible from outside the cluster.**

### Recommended Architecture (from AKS Baseline)

```
Internet
    │
    ▼
┌──────────────────────┐
│ Application Gateway  │  ← WAF (Web Application Firewall)
│ (or Azure Front Door)│  ← SSL termination
└──────────┬───────────┘
           │ Internal LB IP
           ▼
┌──────────────────────┐
│ NGINX Ingress        │  ← Ingress Controller (in AKS)
│ Controller           │  ← Route rules, path-based routing
└──────────┬───────────┘
           │ ClusterIP
           ▼
┌──────────────────────┐
│ Application Pods     │  ← SecureFin app
└──────────────────────┘
```

### Implementation Options

| Option | Pros | Cons | Cost |
|--------|------|------|------|
| **A. NGINX Ingress + Internal LB** | Standard K8s pattern, flexible routing, free ingress controller | Requires App Gateway or public LB for external access | ~$20/mo (LB) |
| **B. NGINX Ingress + Public LB** | Simple, direct external access | No WAF, public IP on cluster | ~$20/mo (LB) |
| **C. Application Gateway Ingress Controller (AGIC)** | Native Azure, WAF v2, SSL offloading, auto-scaling | More complex setup, higher cost | ~$200/mo |
| **D. Azure Front Door + Internal LB** | Global load balancing, CDN, WAF | Highest cost, most complex | ~$300/mo |

### Recommended Path (Dev Environment)

**Option A** for dev — NGINX Ingress with internal Azure Load Balancer:

1. Install NGINX Ingress Controller via Helm (with `controller.service.loadBalancerIP` annotation for internal LB)
2. Create Ingress resource in Helm chart for the SecureFin app
3. Access via jump box (internal LB IP) for dev/testing
4. Add Application Gateway in front for staging/production (Option C)

This will be implemented in Module 3 Steps 5-7 alongside ArgoCD.

---

## 9. Updated Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GitHub (Source of Truth)                              │
│                                                                             │
│  secureFin-test          secureFin-app           securefin-gitops           │
│  ┌────────────┐         ┌────────────┐          ┌────────────┐             │
│  │ Terraform  │         │ Node.js    │          │ Helm Chart │             │
│  │ Pipelines  │         │ Dockerfile │──build──▶│ values/env │             │
│  │ K8s YAML   │         │ CI Pipeline│          │ AppSet     │             │
│  └──────┬─────┘         └──────┬─────┘          └──────┬─────┘             │
│         │ OIDC                 │ OIDC                   │ (ArgoCD)          │
└─────────┼──────────────────────┼───────────────────────┼────────────────────┘
          │                      │                       │
          ▼                      ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure (westus3)                                     │
│                                                                             │
│  ┌─ rg-securefin-bastion ─────────────────────────────────────────────┐     │
│  │                                                                     │     │
│  │  Bastion VNet (10.2.0.0/16)    Azure Bastion ◄── Browser SSH       │     │
│  │  ├── AzureBastionSubnet           │                                 │     │
│  │  └── snet-jumpbox ────────────── Jump Box VM                       │     │
│  │                                   (kubectl, helm, az-cli)          │     │
│  └───────────────── VNet Peering ─────────────────────────────────────┘     │
│                          ↕                                                   │
│  ┌─ rg-securefin-core-dev ────────────────────────────────────────────┐     │
│  │                                                                     │     │
│  │  Env VNet (10.0.0.0/16)                                            │     │
│  │  ├── snet-aks (10.0.1.0/24)                                        │     │
│  │  └── snet-pep (10.0.2.0/24)                                        │     │
│  │                                                                     │     │
│  │  Private DNS Zone: privatelink.westus3.azmk8s.io                   │     │
│  │  ├── VNet Link → Env VNet                                          │     │
│  │  └── VNet Link → Bastion VNet                                      │     │
│  │                                                                     │     │
│  │  ACR: acrsecurefindev (Basic, RBAC-only)                           │     │
│  │  Managed Identity: id-securefin-workload-dev (Workload Identity)   │     │
│  │  Managed Identity: id-aks-securefin-dev (Cluster Identity)         │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  ┌─ rg-securefin-aks-dev ─────────────────────────────────────────────┐     │
│  │                                                                     │     │
│  │  AKS: aks-securefin-dev (Private Cluster)                          │     │
│  │  ├── K8s 1.33, Azure CNI, 1x Standard_D2s_v3                      │     │
│  │  ├── UserAssigned Identity (id-aks-securefin-dev)                  │     │
│  │  ├── Custom DNS Zone (privatelink.westus3.azmk8s.io)               │     │
│  │  ├── OIDC + Workload Identity enabled                              │     │
│  │  ├── Azure Policy (Gatekeeper) addon                               │     │
│  │  ├── Key Vault CSI + Secrets Store CSI                             │     │
│  │  ├── OMS Agent → Log Analytics                                     │     │
│  │  └── ContainerInsights solution                                    │     │
│  │                                                                     │     │
│  │  RBAC:                                                              │     │
│  │  ├── AKS identity → Network Contributor (AKS subnet)              │     │
│  │  ├── AKS identity → Private DNS Zone Contributor (DNS zone)       │     │
│  │  └── Kubelet identity → AcrPull (ACR)                              │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  ┌─ rg-securefin-data-dev ────────────────────────────────────────────┐     │
│  │  (Reserved for future databases, caches, storage)                   │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  Azure Policy (applied to core, aks, data RGs):                            │
│  ├── Required Tags (Project, Environment, Owner, CostCenter, ManagedBy)    │
│  ├── Deny Public IPs (except pip-bastion-*)                                │
│  └── Allowed Locations (westus3, westus)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Network Topology

```
┌─────────────────────────────────────┐
│          10.0.0.0/16                │
│      Env VNet (spoke)               │
│  ┌─────────────────────────┐        │
│  │ snet-aks  10.0.1.0/24   │◄───── AKS nodes + pods    │
│  │ snet-pep  10.0.2.0/24   │◄───── Private endpoints   │
│  └─────────────────────────┘        │
└────────────┬────────────────────────┘
             │ VNet Peering (bidirectional)
             │
┌────────────┴────────────────────────┐
│          10.2.0.0/16                │
│      Bastion VNet (hub)             │
│  ┌─────────────────────────┐        │
│  │ Bastion    10.2.0.0/26  │◄───── Azure Bastion        │
│  │ Jumpbox    10.2.1.0/27  │◄───── Jump Box VM          │
│  └─────────────────────────┘        │
└─────────────────────────────────────┘

AKS service_cidr: 10.1.0.0/16 (internal Kubernetes ClusterIPs)
AKS dns_service_ip: 10.1.0.10

Private DNS Zone: privatelink.westus3.azmk8s.io
  └── Linked to both VNets (env + bastion)
```

---

## 10. Full Infrastructure Inventory

### Azure Resources (dev environment)

| Resource | Name | Resource Group | Details |
|----------|------|----------------|---------|
| RG (core) | `rg-securefin-core-dev` | — | Networking, DNS, ACR, Identity |
| RG (aks) | `rg-securefin-aks-dev` | — | AKS cluster |
| RG (data) | `rg-securefin-data-dev` | — | Future data services |
| RG (bastion) | `rg-securefin-bastion` | — | Bastion + Jump Box |
| VNet (env) | `vnet-securefin-dev` | core | 10.0.0.0/16 |
| Subnet (aks) | `snet-aks-securefin-dev` | core | 10.0.1.0/24 |
| Subnet (pep) | `snet-pep-securefin-dev` | core | 10.0.2.0/24 |
| NSG | `nsg-securefin-dev` | core | 4 rules |
| VNet (bastion) | Bastion VNet | bastion | 10.2.0.0/16 |
| Subnet (bastion) | AzureBastionSubnet | bastion | 10.2.0.0/26 |
| Subnet (jumpbox) | snet-jumpbox | bastion | 10.2.1.0/27 |
| VNet Peering | Bidirectional | core ↔ bastion | |
| DNS Zone | `privatelink.westus3.azmk8s.io` | core | **NEW** (feature branch) |
| DNS VNet Link | → Env VNet | core | **NEW** (feature branch) |
| DNS VNet Link | → Bastion VNet | core | **NEW** (feature branch) |
| AKS | `aks-securefin-dev` | aks | Private, K8s 1.33, UserAssigned |
| LAW | `law-securefin-dev` | aks | ContainerInsights |
| ACR | `acrsecurefindev` | core | Basic, admin disabled |
| MI (AKS identity) | `id-aks-securefin-dev` | aks | **NEW** (feature branch) |
| MI (workload) | `id-securefin-workload-dev` | core | Federated credential |
| Bastion Host | Standard | bastion | Browser SSH |
| Jump Box VM | Standard_D2s_v3 | bastion | Ubuntu 24.04 |
| Public IP | pip-bastion-securefin | bastion | Bastion requires this |
| Policy (tags) | Required Tags | core/aks/data | |
| Policy (IPs) | Deny Public IPs | core/aks/data | Except `pip-bastion-*` |
| Policy (locations) | Allowed Locations | core/aks/data | westus3, westus |

### Terraform Modules (9 total)

| Module | Source | Instances | Key Outputs |
|--------|--------|-----------|-------------|
| `tags` | `./modules/tags` | 1 | `tags` map |
| `resource-group` | `./modules/resource-group` | 4 | `name`, `id`, `location` |
| `network` | `./modules/network` | 1 | `vnet_id`, `vnet_name`, `aks_subnet_id` |
| `aks` | `./modules/aks` | 1 | `cluster_id`, `oidc_issuer_url`, `kubelet_identity_object_id` |
| `identity` | `./modules/identity` | 1 | MI `client_id`, `principal_id` |
| `acr` | `./modules/acr` | 1 | `acr_id`, `acr_name`, `acr_login_server` |
| `bastion` | `./modules/bastion` | 1 | `bastion_vnet_id`, `jumpbox_private_ip` |
| `dns` | `./modules/dns` | 1 | `aks_dns_zone_id`, `aks_dns_zone_name` |
| `policy` | `./modules/policy` | 1 | Policy assignment IDs |

### CI/CD Pipelines (4 total)

| Pipeline | Repo | Trigger | Jobs |
|----------|------|---------|------|
| Terraform CI/CD | secureFin-test | Push/PR on infra changes | Plan → Apply → Validate |
| App CI (infra repo) | secureFin-test | Push/PR on app/ changes | Build → Push ACR |
| App CI (app repo) | secureFin-app | Push/PR on src changes | Build → Trivy → Push ACR |
| Helm Validate | securefin-gitops | PR | Lint → Template dry-run |

---

## 11. Security Posture

### Zero-Secret Architecture

| Component | Auth Method |
|-----------|------------|
| GitHub → Azure (CI/CD) | OIDC Workload Identity Federation |
| AKS → ACR (image pull) | Kubelet Managed Identity + AcrPull |
| Pods → Azure (Key Vault, etc.) | Workload Identity (K8s SA → Azure MI) |
| kubectl → AKS | Azure AD RBAC |
| Docker push (CI) | OIDC → `az acr login` |
| Jump Box → AKS | Azure AD + kubelogin |

### Defense Layers

| Layer | Controls |
|-------|----------|
| Network | Private AKS, VNet isolation, NSG deny-all-inbound, K8s NetworkPolicies, hub-spoke peering |
| DNS | Custom private DNS zones with controlled VNet links |
| Identity | No local accounts, Azure AD RBAC, UserAssigned MI, Workload Identity |
| Supply Chain | Gatekeeper: ACR-only images, no `:latest`, require resource limits, Trivy scanning |
| Compliance | Azure Policy: required tags, deny public IPs, allowed locations |
| Container | Distroless base, non-root (UID 1000), read-only FS, capabilities dropped |
| Access | Azure Bastion (no public SSH), jump box NSG, browser-based tunnel |
| Observability | ContainerInsights → LAW, OMS Agent, Azure Policy audit |
| CI/CD | Checkov, TFLint, `terraform fmt`, Helm lint, Trivy CVE scan, environment approvals |

---

## 12. Cost Analysis

| Resource | Monthly Cost | Notes |
|----------|-------------|-------|
| AKS Control Plane | $0 | Free tier |
| Standard_D2s_v3 (AKS node) | ~$28 | 2 vCPU, 8 GB RAM |
| ACR Basic | ~$5 | 10 GB storage |
| Log Analytics | ~$0 | < 1 GB/day (5 GB/day free) |
| Azure Bastion | ~$140 | Standard SKU |
| Jump Box VM (D2s_v3) | ~$28 | 2 vCPU, 8 GB RAM |
| Public IP (Bastion) | ~$4 | Static IP |
| VNet / NSG / Peering | $0 | Included |
| Private DNS Zone | ~$0.50 | Per zone + queries |
| Azure Policy | $0 | Included |
| Managed Identities | $0 | Included |
| **Total** | **~$206/month** | |

> **Note:** Bastion + Jump Box cost ($172/mo) is amortized across all environments. For dev-only testing, consider deallocating Bastion when not in use.

---

## 13. Issues Resolved

### This Session (Network & DNS Rework)

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | CIDR overlap between Bastion VNet and AKS service_cidr | Both used 10.1.0.0/16 | Changed Bastion VNet to 10.2.0.0/16 |
| 2 | Fragile DNS zone discovery | System-mode GUID prefix required data source hack | Created dedicated dns module with predictable zone name |
| 3 | Circular dependency with custom DNS | SystemAssigned identity can't get RBAC before creation | Changed to UserAssigned, created identity at root level |
| 4 | DNS link in wrong module | Bastion module managed AKS DNS link | Moved to dns module for centralized DNS management |

### Previous Sessions (22 issues documented in `ERRORS_AND_SOLUTIONS.md`)

Categories: Authentication (4), State Backend (2), Provider (3), AKS (5), CI/CD (3), Policy (2), Other (3)

Notable fixes:
- `terraform fmt` failure in CI (pre-commit hook added)
- DNS zone not found (System-mode GUID zone discovery)
- `parent_id` deprecation (AzureRM 4.x)
- VM SKU unavailability (changed to Standard_D2s_v3)
- Trivy CVEs (Alpine base + apk upgrade)

---

## 14. What's Next

### Immediate (After merging `feature/network-dns-rework`)

1. **Deploy the DNS rework** — Merge to dev, run pipeline (AKS will be recreated)
2. **Re-validate** — Run Post-Deployment-Validation.ps1 after AKS rebuild
3. **Update MODULE_3_REPORT.md** — Add bastion and DNS module to inventory

### Module 3 Completion (Steps 5-7)

4. **GitOps Update Automation** — Add CI step to update image tag in securefin-gitops after ACR push
5. **ArgoCD Installation** — Install ArgoCD on AKS via Helm, configure repo access
6. **ApplicationSet** — Apply ApplicationSet, verify full GitOps loop

### App Exposure (After ArgoCD)

7. **NGINX Ingress Controller** — Install via Helm with internal Azure Load Balancer
8. **Ingress Resource** — Add to Helm chart for path-based routing
9. **Application Gateway** — Add for staging/production (WAF, SSL termination)

### Future Enhancements

- Azure Key Vault integration (secrets for app)
- Azure Firewall for egress control
- Monitoring dashboards (Workbooks)
- Multi-environment deployment (staging, production)
- Disaster recovery planning

---

*Report generated from the current state of all 3 repositories as of April 7, 2026.*
