# Argo CD GitOps Configuration for IQGeo Platform

This directory contains the Argo CD configuration for deploying the IQGeo Platform 7.5 to OpenShift using a GitOps workflow.

## Architecture

```
argocd/
├── README.md                          # This file
├── install/                           # Argo CD installation on OpenShift
│   ├── namespace.yaml                 # argocd namespace
│   ├── argocd-install.yaml            # Argo CD server + components
│   └── argocd-route.yaml              # OpenShift Route for Argo CD UI
├── projects/
│   └── iqgeo-project.yaml             # AppProject defining RBAC boundaries
├── applications/
│   ├── root-app.yaml                  # Root "App of Apps" bootstrap
│   ├── iqgeo-platform.yaml            # IQGeo Platform (Helm chart)
│   ├── postgis.yaml                   # PostGIS database
│   ├── keycloak.yaml                  # Keycloak identity provider
│   ├── pgadmin.yaml                   # pgAdmin database admin
│   └── openshift-route.yaml           # OpenShift Routes
└── environments/
    ├── dev/
    │   ├── values-iqgeo-platform.yaml  # Dev-specific Helm values
    │   ├── kustomization.yaml          # Dev overlay
    │   └── namespace.yaml              # Dev namespace config
    ├── qa/
    │   ├── values-iqgeo-platform.yaml  # QA-specific Helm values
    │   ├── kustomization.yaml          # QA overlay
    │   └── namespace.yaml              # QA namespace config
    └── prod/
        ├── values-iqgeo-platform.yaml  # Prod-specific Helm values
        ├── kustomization.yaml          # Prod overlay
        └── namespace.yaml              # Prod namespace config
```

## Design Principles

1. **App of Apps Pattern**: A single root Application bootstraps all child Applications
2. **Environment Separation**: Dev/QA/Prod each have their own values overlays
3. **Helm + Raw Manifests**: IQGeo Platform uses Helm chart; supporting services (PostGIS, Keycloak, pgAdmin) use raw Kubernetes manifests managed by Argo CD
4. **OpenShift Native**: All manifests comply with restricted SCC, non-root, no privilege escalation
5. **Image Promotion Ready**: Supports future Artifactory-based image promotion pipeline

## Quick Start

### 1. Install Argo CD on OpenShift
```bash
oc apply -f argocd/install/namespace.yaml
oc apply -f argocd/install/argocd-install.yaml
oc apply -f argocd/install/argocd-route.yaml

# Get the initial admin password
oc get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### 2. Create the Argo CD Project
```bash
oc apply -f argocd/projects/iqgeo-project.yaml
```

### 3. Create Secrets (Not stored in Git)
```bash
# Database credentials
oc create secret generic db-credentials -n <namespace> \
  --from-literal=username=iqgeo \
  --from-literal=password=iqgeo

# OIDC client secret
oc create secret generic oidc-client-secret -n <namespace> \
  --from-literal=oidc-client-secret=qpyu1mCm8zvvKTXRnKxwap1A6xMChuY6

# Container registry pull secret (if needed)
oc create secret docker-registry container-registry -n <namespace> \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token>
```

### 4. Deploy via Root App
```bash
# Deploy the dev environment
oc apply -f argocd/applications/root-app.yaml
```

## GitOps Workflow

### Day-to-Day Changes
1. Edit values in `argocd/environments/<env>/values-iqgeo-platform.yaml`
2. Commit and push to the repo
3. Argo CD detects the change and syncs automatically (or manually via UI)

### Version Upgrades
1. Update `image.tag` in the environment-specific values file
2. Update `spec.source.targetRevision` in `iqgeo-platform.yaml` if Helm chart version changes
3. Commit, push, sync

### Promoting Between Environments
1. Test in dev → merge values changes to qa branch/overlay
2. Test in qa → merge values changes to prod branch/overlay
3. Each environment has independent sync policies

## Secrets Management

Secrets are **NOT stored in Git**. They must be created manually or via:
- **Sealed Secrets**: Encrypt secrets and store in Git
- **External Secrets Operator**: Pull from HashiCorp Vault, AWS SSM, etc.
- **OpenBao**: Already supported by the IQGeo chart (see `iqgeo-platform-openbao-standalone.yaml`)

## Monitoring

Access Argo CD UI:
```
https://argocd-<namespace>.apps.<cluster-domain>
```

CLI:
```bash
argocd app list
argocd app get iqgeo-platform-dev
argocd app sync iqgeo-platform-dev
argocd app diff iqgeo-platform-dev
```
