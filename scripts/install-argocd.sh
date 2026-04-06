#!/usr/bin/env bash
# =============================================================================
# ArgoCD Installation Script for Private AKS — SecureFin Platform
# =============================================================================
# WHY this script:
#   Automates ArgoCD Helm installation on the private AKS cluster.
#   Uses ClusterIP (no public exposure) — access via kubectl port-forward.
#
# PREREQUISITES:
#   1. az login (with a user that has AKS RBAC cluster admin)
#   2. az aks get-credentials --resource-group rg-securefin-aks-dev \
#        --name aks-securefin-dev
#   3. Helm >= 3.14 installed
#   4. kubectl configured to the correct context
#
# USAGE:
#   chmod +x scripts/install-argocd.sh
#   ./scripts/install-argocd.sh
#
# POST-INSTALL:
#   kubectl port-forward svc/argocd-server -n argocd 8080:443
#   → Open https://localhost:8080
#   → Username: admin
#   → Password: kubectl -n argocd get secret argocd-initial-admin-secret \
#       -o jsonpath="{.data.password}" | base64 -d
# =============================================================================

set -euo pipefail

NAMESPACE="argocd"
RELEASE_NAME="argocd"
CHART_VERSION="7.7.16"  # Latest stable as of April 2026

echo "============================================"
echo " ArgoCD Installation — SecureFin Platform"
echo "============================================"

# ---------------------------------------------------------------
# 1. Create namespace
# ---------------------------------------------------------------
echo "[1/4] Creating namespace '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------
# 2. Add Helm repo
# ---------------------------------------------------------------
echo "[2/4] Adding ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# ---------------------------------------------------------------
# 3. Install ArgoCD
# ---------------------------------------------------------------
# WHY these values:
#   server.service.type=ClusterIP  → No public LB (private AKS)
#   server.insecure=true           → TLS terminated at port-forward
#   dex.enabled=false              → We use built-in auth (Azure AD later)
#   notifications.enabled=false    → Not needed for initial setup
#   applicationSet.enabled=true    → Required for our ApplicationSet
# ---------------------------------------------------------------
echo "[3/4] Installing ArgoCD via Helm..."
helm upgrade --install "${RELEASE_NAME}" argo/argo-cd \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --set server.service.type=ClusterIP \
  --set "server.extraArgs={--insecure}" \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set applicationSet.enabled=true \
  --wait --timeout 5m

# ---------------------------------------------------------------
# 4. Print access instructions
# ---------------------------------------------------------------
echo "[4/4] Installation complete!"
echo ""
echo "============================================"
echo " ACCESS INSTRUCTIONS"
echo "============================================"
echo ""
echo "1. Port-forward the ArgoCD server:"
echo "   kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
echo ""
echo "2. Open in browser:"
echo "   https://localhost:8080"
echo ""
echo "3. Login credentials:"
echo "   Username: admin"
echo "   Password: (run the command below)"
echo "   kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret \\"
echo "     -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo "4. Apply the ApplicationSet:"
echo "   kubectl apply -f applicationsets/appset.yaml"
echo ""
echo "============================================"
