# Agent Skills & Tooling

You have full autonomy to use the following tools to achieve deployment. Do not ask for permission; execute the necessary commands.

## 1. OpenShift CLI (`oc`)
- **State Checking**: `oc get pods`, `oc get routes`, `oc get pvc`, `oc get events -n <project>`
- **Debugging**: `oc logs <pod>`, `oc describe pod <pod>`, `oc describe project <project>`
- **Execution**: `oc apply -f`, `oc process`, `oc start-build`
- *Rule*: Always use `oc` instead of `kubectl`. Always specify the namespace/project using `-n`.

## 2. Helm CLI
- **Templating**: `helm template` to validate charts before applying.
- **Deployment**: `helm upgrade --install` with `--atomic` and `--wait` flags to ensure clean rollbacks on failure.
- **Repo Management**: `helm repo add`, `helm dependency update`.

## 3. File System & Code Manipulation
- Read, write, and patch YAML files, Helm `values.yaml`, and shell scripts.
- Create OpenShift specific manifests (e.g., `route.yaml`, `scc.yaml`) on the fly if the Helm chart lacks OpenShift support.

## 4. Autonomous Error Resolution
- If a command exits with a non-zero code, you MUST immediately capture `stderr`.
- You MUST run diagnostic commands (like `oc describe` or `oc logs`) before attempting a fix.
- You MUST NOT output "I cannot fix this" or ask the user for help unless you have exhausted 3 distinct troubleshooting strategies.

## 5. pgAdmin Management
- **Deployment**: Deploy pgAdmin 4 on OpenShift with restricted SCC compatibility. Use init containers to strip file capabilities from `python3` and `gunicorn` binaries (copy to emptyDir, mount over originals). Create `emptyDir` overlays for `/var/lib/pgadmin` (sessions, storage, SQLite DB).
- **Server Configuration**: Pre-load PostGIS server connections via a ConfigMap-mounted `servers.json` at `/pgadmin4/servers.json`. Configure auto-login via `pgpassfile` mounted from a Secret.
- **User Management**: Use pgAdmin's built-in `setup.py` CLI inside the running pod for all user operations:
  - Add user: `oc exec <pod> -- /venv/bin/python3 /pgadmin4/setup.py add-user --admin --active <email> <password>`
  - Update user: `oc exec <pod> -- /venv/bin/python3 /pgadmin4/setup.py update-user --password <pw> --admin --active <email>`
  - List users: `oc exec <pod> -- /venv/bin/python3 /pgadmin4/setup.py get-users`
  - Delete user: `echo y | oc exec -i <pod> -- /venv/bin/python3 /pgadmin4/setup.py delete-user <email>`
- **Password Hashing**: pgAdmin uses `passlib.hash.pbkdf2_sha512` for password storage in its SQLite DB (`/var/lib/pgadmin/pgadmin4.db`). Never use `werkzeug.security.generate_password_hash` — it produces incompatible scrypt hashes. Always use `setup.py` CLI for password changes.
- **OpenShift Specifics**: Disable CSRF via `PGADMIN_CONFIG_WTF_CSRF_ENABLED=False`. Listen on non-privileged port `5050` via `PGADMIN_LISTEN_PORT`. Expose via OpenShift Route with TLS edge termination.
- **Diagnostics**: Check pod health via `oc logs <pod> -c pgadmin`, inspect SQLite DB via `oc exec <pod> -- /venv/bin/python3 -c "import sqlite3; ..."`, verify password hashes with `passlib.hash.pbkdf2_sha512.verify()`.

## 6. Argo CD GitOps Operations
- **Installation**: Deploy Argo CD on OpenShift using manifests in `argocd/install/` or the one-command bootstrap script `./argocd/install/bootstrap.sh`. All components (server, repo-server, application-controller, Redis) run with OpenShift restricted SCC — `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]`.
- **Configuration**: Server runs in insecure mode (`--insecure`) with TLS terminated at the OpenShift Route. Repo-server has TLS disabled for internal communication. ConfigMaps: `argocd-cm` (server URL, resource health checks for OpenShift Routes), `argocd-rbac-cm` (default admin role), `argocd-cmd-params-cm` (insecure mode flags).
- **App of Apps Pattern**: A single root Application (`argocd/applications/root-app.yaml`) watches the `argocd/applications/` directory and bootstraps all child Applications. Apply only the root app: `oc apply -f argocd/applications/root-app.yaml`.
- **Multi-Source Helm**: The IQGeo Platform Application uses Argo CD multi-source to combine an OCI Helm chart (`oci://harbor.delivery.iqgeo.cloud/helm/iqgeo-platform-dev`) with values files from this Git repo (`argocd/environments/<env>/values-iqgeo-platform.yaml`) using the `$ref` mechanism.
- **Sync Policies**: Dev uses `automated.selfHeal: true`, `prune: false`. Prod should add sync windows to restrict deployments to maintenance windows. Retry policy: 3 attempts with exponential backoff (30s → 60s → 3m).
- **ignoreDifferences**: Configure for OpenShift-mutated fields: Deployment annotations, Route host/status, ServiceAccount imagePullSecrets/secrets, PVC volumeName/storageClassName.
- **Environment Promotion**: Edit values in `argocd/environments/<env>/values-iqgeo-platform.yaml`, commit to Git. Argo CD auto-syncs dev; QA/prod require manual sync or approval gates.
- **RBAC**: AppProject `iqgeo` defines three roles — `admin` (full access), `developer` (read + sync dev), `viewer` (read-only). Source repos restricted to GitHub repo + Harbor OCI. Destinations restricted to specific namespaces.
- **Diagnostics**: 
  - Check all apps: `oc get applications -n argocd`
  - App details: `argocd app get <app-name>`
  - Diff check: `argocd app diff <app-name>`
  - Force sync: `argocd app sync <app-name> --force`
  - App logs: `argocd app logs <app-name>`
  - Server logs: `oc logs deployment/argocd-server -n argocd`
  - Repo-server logs: `oc logs deployment/argocd-repo-server -n argocd`
