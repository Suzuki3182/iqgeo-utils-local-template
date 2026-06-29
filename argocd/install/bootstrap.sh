#!/bin/bash
# =============================================================================
# Argo CD Bootstrap Script for OpenShift
# =============================================================================
# One-command setup: installs Argo CD, creates the project, and deploys
# the IQGeo Platform via the App of Apps pattern.
#
# Usage:
#   ./argocd/install/bootstrap.sh [--namespace <ns>]
#
# Prerequisites:
#   - oc CLI logged in to the OpenShift cluster
#   - Container registry pull secret created in the target namespace
#   - Database credentials secret created in the target namespace
# =============================================================================
set -euo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"
TARGET_NS="${1:-suzuki3182-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================"
echo "  Argo CD Bootstrap for IQGeo Platform"
echo "============================================"
echo "Argo CD namespace: $ARGOCD_NS"
echo "Target namespace:  $TARGET_NS"
echo ""

# --- Step 1: Check login ---
echo "Step 1: Verifying OpenShift login..."
oc whoami > /dev/null 2>&1 || { echo "ERROR: Not logged in. Run 'oc login' first."; exit 1; }
echo "  Logged in as: $(oc whoami)"
echo "  Server: $(oc whoami --show-server)"
echo ""

# --- Step 2: Create Argo CD namespace ---
echo "Step 2: Creating Argo CD namespace..."
oc apply -f "$REPO_ROOT/argocd/install/namespace.yaml" 2>/dev/null || \
  echo "  Namespace already exists or cannot be created (sandbox). Will use existing."
echo ""

# --- Step 3: Install Argo CD ---
echo "Step 3: Installing Argo CD components..."
oc apply -n "$ARGOCD_NS" -f "$REPO_ROOT/argocd/install/argocd-install.yaml"
echo ""

# --- Step 4: Create Route ---
echo "Step 4: Creating OpenShift Route for Argo CD UI..."
oc apply -n "$ARGOCD_NS" -f "$REPO_ROOT/argocd/install/argocd-route.yaml"
echo ""

# --- Step 5: Wait for Argo CD to be ready ---
echo "Step 5: Waiting for Argo CD server to be ready..."
oc rollout status deployment/argocd-server -n "$ARGOCD_NS" --timeout=300s
oc rollout status deployment/argocd-repo-server -n "$ARGOCD_NS" --timeout=300s
oc rollout status deployment/argocd-application-controller -n "$ARGOCD_NS" --timeout=300s
echo "  Argo CD is ready!"
echo ""

# --- Step 6: Get initial admin password ---
echo "Step 6: Retrieving Argo CD admin password..."
ARGOCD_PASSWORD=$(oc get secret argocd-initial-admin-secret -n "$ARGOCD_NS" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "  No initial-admin-secret found. Password may have been changed."
    echo "  Default admin password is the server pod name."
    ARGOCD_PASSWORD=$(oc get pods -n "$ARGOCD_NS" -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}')
fi
echo ""

# --- Step 7: Create Argo CD Project ---
echo "Step 7: Creating IQGeo Argo CD AppProject..."
oc apply -n "$ARGOCD_NS" -f "$REPO_ROOT/argocd/projects/iqgeo-project.yaml"
echo ""

# --- Step 8: Grant Argo CD permissions on target namespace ---
echo "Step 8: Setting up RBAC for Argo CD in target namespace..."
oc policy add-role-to-user edit "system:serviceaccount:${ARGOCD_NS}:argocd-application-controller" -n "$TARGET_NS" 2>/dev/null || \
  echo "  Could not add role (may already exist or insufficient permissions)"
echo ""

# --- Step 9: Deploy Root App ---
echo "Step 9: Deploying Root Application (App of Apps)..."
oc apply -n "$ARGOCD_NS" -f "$REPO_ROOT/argocd/applications/root-app.yaml"
echo ""

# --- Step 10: Print summary ---
ARGOCD_ROUTE=$(oc get route argocd-server -n "$ARGOCD_NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "argocd-${ARGOCD_NS}.apps.rm2.thpm.p1.openshiftapps.com")
echo "============================================"
echo "  Argo CD Bootstrap Complete!"
echo "============================================"
echo ""
echo "  Argo CD UI:  https://${ARGOCD_ROUTE}"
echo "  Username:    admin"
echo "  Password:    ${ARGOCD_PASSWORD}"
echo ""
echo "  Applications deployed:"
echo "    - iqgeo-root (App of Apps bootstrap)"
echo "    - iqgeo-platform-dev (Helm chart)"
echo "    - postgis-dev (raw manifests)"
echo "    - keycloak-dev (raw manifests)"
echo "    - pgadmin-dev (raw manifests)"
echo "    - openshift-routes-dev (routes)"
echo ""
echo "  To check status:"
echo "    oc get applications -n $ARGOCD_NS"
echo ""
echo "  To sync manually:"
echo "    argocd login ${ARGOCD_ROUTE} --username admin --password '${ARGOCD_PASSWORD}' --insecure"
echo "    argocd app sync iqgeo-root"
echo "============================================"
