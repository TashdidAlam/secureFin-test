#!/usr/bin/env bash
# =============================================================================
# SecureFin Module 2 — Post-Deployment Validation Script
# =============================================================================
# Usage:
#   chmod +x scripts/validate-module2.sh
#   ./scripts/validate-module2.sh <environment>
#
# Example:
#   ./scripts/validate-module2.sh dev
#
# Prerequisites:
#   - Azure CLI (az) authenticated
#   - kubectl configured with AKS credentials
#   - jq installed
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments & Variables
# ---------------------------------------------------------------------------
ENV="${1:?Usage: $0 <environment> (dev|staging|production)}"
case "$ENV" in
  dev|staging|production)
    ;;
  *)
    echo "Error: Invalid environment '$ENV'. Expected one of: dev, staging, production." >&2
    echo "Usage: $0 <environment> (dev|staging|production)" >&2
    exit 1
    ;;
esac
PROJECT="securefin"
RG_CORE="rg-${PROJECT}-core-${ENV}"
RG_AKS="rg-${PROJECT}-aks-${ENV}"
RG_DATA="rg-${PROJECT}-data-${ENV}"
AKS_NAME="aks-${PROJECT}-${ENV}"
PASS=0
FAIL=0
WARN=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
check_pass() { echo "  ✅ PASS: $1"; ((++PASS)); }
check_fail() { echo "  ❌ FAIL: $1"; ((++FAIL)); }
check_warn() { echo "  ⚠️  WARN: $1"; ((++WARN)); }

section() { echo -e "\n══════════════════════════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════════════════════════"; }

# ---------------------------------------------------------------------------
# 1. Resource Groups
# ---------------------------------------------------------------------------
section "1. RESOURCE GROUPS"

for RG in "$RG_CORE" "$RG_AKS" "$RG_DATA"; do
  if az group show --name "$RG" --query "name" -o tsv &>/dev/null; then
    check_pass "Resource group '$RG' exists"
  else
    check_fail "Resource group '$RG' not found"
  fi
done

# ---------------------------------------------------------------------------
# 2. Network Validation
# ---------------------------------------------------------------------------
section "2. NETWORK — VNet, Subnets, NSG"

VNET_NAME="vnet-${PROJECT}-${ENV}"

# VNet exists
if az network vnet show --resource-group "$RG_CORE" --name "$VNET_NAME" &>/dev/null; then
  check_pass "VNet '$VNET_NAME' exists in $RG_CORE"

  # Address space
  ADDR=$(az network vnet show -g "$RG_CORE" -n "$VNET_NAME" --query "addressSpace.addressPrefixes[0]" -o tsv)
  if [[ "$ADDR" == "10.0.0.0/16" ]]; then
    check_pass "VNet address space is 10.0.0.0/16"
  else
    check_fail "VNet address space is '$ADDR' (expected 10.0.0.0/16)"
  fi
else
  check_fail "VNet '$VNET_NAME' not found"
fi

# AKS subnet
AKS_SUBNET="snet-aks-${ENV}"
if az network vnet subnet show -g "$RG_CORE" --vnet-name "$VNET_NAME" -n "$AKS_SUBNET" &>/dev/null; then
  check_pass "AKS subnet '$AKS_SUBNET' exists"
  SUBNET_CIDR=$(az network vnet subnet show -g "$RG_CORE" --vnet-name "$VNET_NAME" -n "$AKS_SUBNET" --query "addressPrefix" -o tsv)
  if [[ "$SUBNET_CIDR" == "10.0.1.0/24" ]]; then
    check_pass "AKS subnet CIDR is 10.0.1.0/24"
  else
    check_fail "AKS subnet CIDR is '$SUBNET_CIDR' (expected 10.0.1.0/24)"
  fi
else
  check_fail "AKS subnet '$AKS_SUBNET' not found"
fi

# Private endpoint subnet
PEP_SUBNET="snet-pep-${ENV}"
if az network vnet subnet show -g "$RG_CORE" --vnet-name "$VNET_NAME" -n "$PEP_SUBNET" &>/dev/null; then
  check_pass "Private endpoint subnet '$PEP_SUBNET' exists"
else
  check_fail "Private endpoint subnet '$PEP_SUBNET' not found"
fi

# NSG
NSG_NAME="nsg-aks-${PROJECT}-${ENV}"
if az network nsg show -g "$RG_CORE" -n "$NSG_NAME" &>/dev/null; then
  check_pass "NSG '$NSG_NAME' exists"
  RULE_COUNT=$(az network nsg rule list -g "$RG_CORE" --nsg-name "$NSG_NAME" --query "length(@)")
  if [[ "$RULE_COUNT" -ge 5 ]]; then
    check_pass "NSG has $RULE_COUNT custom rules (expected >= 5)"
  else
    check_warn "NSG has $RULE_COUNT custom rules (expected >= 5)"
  fi
else
  check_fail "NSG '$NSG_NAME' not found"
fi

# ---------------------------------------------------------------------------
# 3. AKS Cluster Validation
# ---------------------------------------------------------------------------
section "3. AKS CLUSTER — Private, OIDC, Workload Identity"

if az aks show -g "$RG_AKS" -n "$AKS_NAME" &>/dev/null; then
  check_pass "AKS cluster '$AKS_NAME' exists"

  # Private cluster
  PRIVATE=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "apiServerAccessProfile.enablePrivateCluster" -o tsv)
  if [[ "$PRIVATE" == "true" ]]; then
    check_pass "AKS API server is private (private_cluster_enabled=true)"
  else
    check_fail "AKS API server is NOT private (expected private_cluster_enabled=true)"
  fi

  # OIDC issuer
  OIDC=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "oidcIssuerProfile.enabled" -o tsv)
  if [[ "$OIDC" == "true" ]]; then
    check_pass "OIDC issuer is enabled"
    OIDC_URL=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "oidcIssuerProfile.issuerUrl" -o tsv)
    echo "         OIDC URL: $OIDC_URL"
  else
    check_fail "OIDC issuer is NOT enabled"
  fi

  # Workload identity
  WI=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "securityProfile.workloadIdentity.enabled" -o tsv)
  if [[ "$WI" == "true" ]]; then
    check_pass "Workload Identity is enabled"
  else
    check_fail "Workload Identity is NOT enabled"
  fi

  # Local accounts disabled
  LOCAL_DISABLED=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "disableLocalAccounts" -o tsv)
  if [[ "$LOCAL_DISABLED" == "true" ]]; then
    check_pass "Local accounts are disabled (Azure AD only)"
  else
    check_fail "Local accounts are NOT disabled"
  fi

  # Azure AD RBAC
  AAD_RBAC=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "aadProfile.enableAzureRbac" -o tsv)
  if [[ "$AAD_RBAC" == "true" ]]; then
    check_pass "Azure AD RBAC is enabled"
  else
    check_fail "Azure AD RBAC is NOT enabled"
  fi

  # Network plugin and policy
  NET_PLUGIN=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "networkProfile.networkPlugin" -o tsv)
  NET_POLICY=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "networkProfile.networkPolicy" -o tsv)
  if [[ "$NET_PLUGIN" == "azure" ]]; then
    check_pass "Network plugin: Azure CNI"
  else
    check_fail "Network plugin is '$NET_PLUGIN' (expected 'azure')"
  fi
  if [[ "$NET_POLICY" == "azure" ]]; then
    check_pass "Network policy: Azure Network Policy"
  else
    check_fail "Network policy is '$NET_POLICY' (expected 'azure')"
  fi

  # Node pools
  POOLS=$(az aks nodepool list -g "$RG_AKS" --cluster-name "$AKS_NAME" --query "[].name" -o tsv)
  echo "         Node pools: $POOLS"
  for EXPECTED_POOL in "system" "user" "spot"; do
    if echo "$POOLS" | grep -qw "$EXPECTED_POOL"; then
      check_pass "Node pool '$EXPECTED_POOL' exists"
    else
      check_fail "Node pool '$EXPECTED_POOL' not found"
    fi
  done

  # Spot pool taint
  SPOT_TAINTS=$(az aks nodepool show -g "$RG_AKS" --cluster-name "$AKS_NAME" -n "spot" --query "nodeTaints" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SPOT_TAINTS" ]]; then
    check_pass "Spot pool has taints: $SPOT_TAINTS"
  else
    check_warn "Spot pool has no taints (expected NoSchedule taint)"
  fi

else
  check_fail "AKS cluster '$AKS_NAME' not found"
fi

# ---------------------------------------------------------------------------
# 4. Workload Identity — Managed Identity & FIC
# ---------------------------------------------------------------------------
section "4. WORKLOAD IDENTITY — Managed Identity & Federated Credential"

MI_NAME="id-${PROJECT}-workload-${ENV}"
if az identity show -g "$RG_CORE" -n "$MI_NAME" &>/dev/null; then
  check_pass "Managed Identity '$MI_NAME' exists"

  CLIENT_ID=$(az identity show -g "$RG_CORE" -n "$MI_NAME" --query "clientId" -o tsv)
  echo "         Client ID: $CLIENT_ID"

  # Federated credential
  FIC_LIST=$(az identity federated-credential list --identity-name "$MI_NAME" -g "$RG_CORE" --query "[].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$FIC_LIST" ]]; then
    check_pass "Federated Identity Credential(s): $FIC_LIST"

    # Verify subject
    FIC_SUBJECT=$(az identity federated-credential list --identity-name "$MI_NAME" -g "$RG_CORE" --query "[0].subject" -o tsv 2>/dev/null)
    if [[ "$FIC_SUBJECT" == *"system:serviceaccount:default:app-sa"* ]]; then
      check_pass "FIC subject is 'system:serviceaccount:default:app-sa'"
    else
      check_warn "FIC subject is '$FIC_SUBJECT' (expected system:serviceaccount:default:app-sa)"
    fi
  else
    check_fail "No Federated Identity Credentials found for '$MI_NAME'"
  fi
else
  check_fail "Managed Identity '$MI_NAME' not found"
fi

# ---------------------------------------------------------------------------
# 5. Kubernetes — Network Policies & Gatekeeper
# ---------------------------------------------------------------------------
section "5. KUBERNETES — Network Policies, ServiceAccount, Gatekeeper"

# Get credentials (private cluster — may need VNet access or command invoke)
echo "  Attempting to get AKS credentials..."
if az aks get-credentials -g "$RG_AKS" -n "$AKS_NAME" --overwrite-existing 2>/dev/null; then
  check_pass "kubectl credentials configured"

  # Network policies
  NP_COUNT=$(kubectl get networkpolicies -n default -o json 2>/dev/null | jq '.items | length' 2>/dev/null || echo "0")
  if [[ "$NP_COUNT" -ge 2 ]]; then
    check_pass "Found $NP_COUNT NetworkPolicies in 'default' namespace"
    kubectl get networkpolicies -n default -o wide 2>/dev/null || true
  else
    check_warn "Found $NP_COUNT NetworkPolicies (expected >= 2). Apply k8s/network-policies/ manifests."
  fi

  # ServiceAccount
  if kubectl get sa app-sa -n default &>/dev/null; then
    check_pass "ServiceAccount 'app-sa' exists in 'default' namespace"
    WI_LABEL=$(kubectl get sa app-sa -n default -o jsonpath='{.metadata.labels.azure\.workload\.identity/use}' 2>/dev/null || echo "")
    if [[ "$WI_LABEL" == "true" ]]; then
      check_pass "ServiceAccount has workload identity label"
    else
      check_warn "ServiceAccount missing 'azure.workload.identity/use: true' label"
    fi
  else
    check_warn "ServiceAccount 'app-sa' not found. Apply k8s/workload-identity/service-account.yaml"
  fi

  # Gatekeeper
  if kubectl get deployments -n gatekeeper-system gatekeeper-controller-manager &>/dev/null; then
    check_pass "OPA Gatekeeper is installed"

    # ConstraintTemplates
    for CT in "k8sdisallowlatesttag" "k8sallowedregistries" "k8srequireresourcelimits"; do
      if kubectl get constrainttemplate "$CT" &>/dev/null; then
        check_pass "ConstraintTemplate '$CT' exists"
      else
        check_warn "ConstraintTemplate '$CT' not found. Apply k8s/gatekeeper/constraint-templates/"
      fi
    done

    # Constraints
    for C in "no-latest-tag:K8sDisallowLatestTag" "acr-only-images:K8sAllowedRegistries" "require-resource-limits:K8sRequireResourceLimits"; do
      NAME="${C%%:*}"
      KIND="${C##*:}"
      if kubectl get "$KIND" "$NAME" &>/dev/null; then
        check_pass "Constraint '$NAME' ($KIND) is active"
      else
        check_warn "Constraint '$NAME' not found. Apply k8s/gatekeeper/constraints/"
      fi
    done
  else
    check_warn "OPA Gatekeeper not installed. Install with: helm install gatekeeper/gatekeeper"
  fi
else
  check_warn "Could not get AKS credentials (private cluster — run from VNet-connected jumpbox)"
fi

# ---------------------------------------------------------------------------
# 6. Azure Policy Assignments
# ---------------------------------------------------------------------------
section "6. AZURE POLICY — Tag Enforcement, Deny Public IP, Allowed Locations"

for RG in "$RG_CORE" "$RG_AKS" "$RG_DATA"; do
  RG_ID=$(az group show -n "$RG" --query "id" -o tsv 2>/dev/null || echo "")
  if [[ -z "$RG_ID" ]]; then
    check_fail "Cannot retrieve ID for RG '$RG'"
    continue
  fi

  ASSIGNMENTS=$(az policy assignment list --scope "$RG_ID" --query "[].displayName" -o tsv 2>/dev/null || echo "")
  if [[ -n "$ASSIGNMENTS" ]]; then
    check_pass "Policy assignments on '$RG':"
    echo "$ASSIGNMENTS" | while read -r A; do echo "         - $A"; done
  else
    check_warn "No policy assignments found on '$RG'"
  fi
done

# Check deny-public-IP effectiveness
echo ""
if [[ "${ENABLE_DENY_PUBLIC_IP_LIVE_TEST:-false}" == "true" ]]; then
  echo "  Testing deny-public-IP policy via live Public IP creation (may have side effects)..."
  DENY_TEST=$(az network public-ip create -g "$RG_AKS" -n "test-pip-validation" --sku Basic --output json 2>&1 || true)
  if echo "$DENY_TEST" | grep -qi "RequestDisallowedByPolicy\|denied by policy"; then
    check_pass "Deny public IP policy is enforced — creation was blocked"
  else
    check_warn "Policy test inconclusive. May need time for policy evaluation, or policy not yet assigned."
    # Clean up test PIP if it was accidentally created
    az network public-ip delete -g "$RG_AKS" -n "test-pip-validation" --yes 2>/dev/null || true
  fi
else
  check_warn "Skipping live deny-public-IP test (set ENABLE_DENY_PUBLIC_IP_LIVE_TEST=true to run)"
fi

# ---------------------------------------------------------------------------
# 7. RBAC — Role Assignments
# ---------------------------------------------------------------------------
section "7. RBAC — AKS Network Contributor on Subnet"

if az aks show -g "$RG_AKS" -n "$AKS_NAME" &>/dev/null; then
  AKS_PRINCIPAL=$(az aks show -g "$RG_AKS" -n "$AKS_NAME" --query "identity.principalId" -o tsv 2>/dev/null)
  if [[ -n "$AKS_PRINCIPAL" ]]; then
    AKS_SUBNET_ID=$(az network vnet subnet show -g "$RG_CORE" --vnet-name "$VNET_NAME" -n "$AKS_SUBNET" --query "id" -o tsv 2>/dev/null)
    ROLE_MATCH=$(az role assignment list --assignee "$AKS_PRINCIPAL" --scope "$AKS_SUBNET_ID" --query "[?roleDefinitionName=='Network Contributor'].roleDefinitionName" -o tsv 2>/dev/null || echo "")
    if [[ "$ROLE_MATCH" == "Network Contributor" ]]; then
      check_pass "AKS identity has 'Network Contributor' on AKS subnet"
    else
      check_fail "AKS identity missing 'Network Contributor' role on AKS subnet"
    fi
  else
    check_warn "Could not retrieve AKS identity principal ID"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "VALIDATION SUMMARY"
TOTAL=$((PASS + FAIL + WARN))
echo ""
echo "  Total checks:  $TOTAL"
echo "  ✅ Passed:     $PASS"
echo "  ❌ Failed:     $FAIL"
echo "  ⚠️  Warnings:  $WARN"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "  ❌ RESULT: VALIDATION FAILED — $FAIL issue(s) require attention"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo "  ⚠️  RESULT: VALIDATION PASSED WITH WARNINGS — $WARN item(s) to review"
  exit 0
else
  echo "  ✅ RESULT: ALL CHECKS PASSED"
  exit 0
fi
