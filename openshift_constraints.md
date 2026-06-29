# OpenShift Strict Constraints (CRITICAL)

The IQGeo platform MUST be deployed exclusively on OpenShift. Vanilla Kubernetes assumptions will cause failures. You MUST adhere to the following rules:

## 1. Security Context Constraints (SCC) & Root Users
- OpenShift pods run with random UIDs by default. 
- **PostGIS**: The PostgreSQL image usually expects a specific UID (e.g., 999 or 1000) and will fail if OpenShift assigns a random one. You must either:
  a) Patch the StatefulSet/Deployment to include `securityContext.fsGroup` matching the PGID.
  b) Create a custom SCC that allows the specific UID and bind it to the ServiceAccount.
- **AppServer/Tools**: Ensure containers do not attempt to run as root. If they do, they will be blocked by the `restricted` SCC.

## 2. Networking & Ingress
- Do NOT use standard Kubernetes `Ingress` objects unless the cluster is explicitly configured for it. 
- Use OpenShift `Route` objects for external access to the `appserver`.
- Ensure TLS termination is configured at the Edge or Passthrough as per enterprise standards.

## 3. Image Registry & Pull Secrets
- If pulling from Harbor, you must create an `ImagePullSecret` in the OpenShift Project and link it to the `default` and `appserver` ServiceAccounts.
- Command to link: `oc secrets link default <secret-name> --for=pull`

## 4. Persistent Storage
- Ensure `StorageClass` used for PostGIS PVCs is compatible with the OpenShift cluster's default provisioner.
- Do not hardcode `hostPath` volumes.

## 5. Resource Quotas & Limits
- OpenShift projects often have `LimitRange` and `ResourceQuota` objects. 
- You MUST define `resources.requests` and `resources.limits` for all IQGeo containers (appserver, postgis, tools) in the Helm `values.yaml`, otherwise deployments will be rejected by the admission controller.