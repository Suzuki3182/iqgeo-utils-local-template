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

## 6. Helm Deployment Operations (Direct — no GitOps)
- **No Argo CD / GitOps**: The IQGeo platform is deployed directly with the Helm CLI. There is NO Argo CD, App-of-Apps, or Git-driven reconciliation in this workflow. Ignore anything in the `argocd/` directory for deployment purposes.
- **Values overlay**: Pick the overlay that matches the chart version and target: `deployment/values-openshift-v3.yaml` (chart v3.x — PostGIS/Keycloak deployed separately) or `deployment/values-openshift.yaml`.
- **Chart source**: Pull the IQGeo platform chart from its OCI reference (`oci://harbor.delivery.iqgeo.cloud/helm/iqgeo-platform`) or use a local/unpacked chart directory. `helm registry login harbor.delivery.iqgeo.cloud` first if pulling from OCI.
- **Install / upgrade** (idempotent, blocking, self-rollback):
  - `helm upgrade --install iqgeo-platform <chart-ref> -n <project> -f deployment/values-openshift-v3.yaml --wait --timeout 15m --atomic`
- **Supporting services** (deployed as standalone manifests, not by the platform chart): `oc apply -f deployment/postgis-deployment.yaml`, `oc apply -f deployment/keycloak-deployment.yaml`, `oc apply -f deployment/pgadmin-deployment.yaml` (all `-n <project>`).
- **Validate before applying**: `helm template iqgeo-platform <chart-ref> -f deployment/values-openshift-v3.yaml | oc apply --dry-run=server -f -`.
- **Diagnostics**:
  - Release status: `helm status iqgeo-platform -n <project>`
  - Rendered/effective values: `helm get values iqgeo-platform -n <project>`
  - Release history / rollback: `helm history iqgeo-platform -n <project>`, `helm rollback iqgeo-platform <rev> -n <project>`
  - Workloads: `oc get pods,route,pvc -n <project>`
- **Rule**: Never mark deployment complete until `helm status` shows `deployed` AND all pods are `Running`/`Ready` AND the OpenShift Route responds.

## 7. Image Build & Registry Operations
- **Source Registry Auth**: `docker login harbor.delivery.iqgeo.cloud` (or `podman login`) before building — base/product images are pulled from Harbor.
- **Build**: From the project root run `./deployment/build_images.sh` to build `iqgeo-<prefix>-build`, `iqgeo-<prefix>-appserver`, and `iqgeo-<prefix>-tools`. Build args (`PRODUCT_REGISTRY`, `PROJECT_REGISTRY`, `PROJECT_REPOSITORY`, `PROJ_PREFIX`) are read from `deployment/.env` — copy it from `deployment/.env.example` first and keep it consistent with `.iqgeorc.jsonc`.
- **Push**: `PUSH=true ./deployment/build_images.sh` pushes the appserver and tools images to `<PROJECT_REGISTRY>/<PROJECT_REPOSITORY>`.
- **On-cluster builds (no Docker host)**: Use OpenShift native builds — `oc new-build --binary --name iqgeo-<prefix>-appserver`, then `oc start-build iqgeo-<prefix>-appserver --from-dir=deployment --follow`. Images land in the internal registry `image-registry.openshift-image-registry.svc:5000/<namespace>/...` (matches the `image.projectRegistry` used in `deployment/values-openshift-v3.yaml`).
- **Tag discipline**: Ensure the tag you build/push matches the tag referenced in the active values file (e.g. `latest` for Harbor overlay, `7.4-with-deps` for the internal-registry overlay). Verify with `oc get istag -n <namespace>` or `skopeo inspect`.
- **Rule**: Never deploy a Helm release until `oc get istag`/registry inspection confirms all three images exist with the expected tag.

## 8. Keycloak / OIDC Identity Operations
- **Realm & Client**: Ensure the `iqgeo` realm exists and the confidential client `iqgeo-oidc` is registered. Set valid redirect URIs to the appserver Route host (`https://<hostname>.<dnsZone>/*`) and web origins accordingly.
- **kcadm inside the pod** (default `/.keycloak` is read-only under the non-root SCC — always use `--config /tmp/kcadm.config`):
  - Authenticate: `oc exec <kc-pod> -- /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password <pw> --config /tmp/kcadm.config`
  - Create client: `kcadm.sh create clients -r iqgeo -s clientId=iqgeo-oidc -s 'redirectUris=["https://<host>/*"]' -s publicClient=false -s standardFlowEnabled=true`
  - Read client secret: `kcadm.sh get clients/<id>/client-secret -r iqgeo`
- **Client Secret Handoff**: Store the generated secret in the `oidc-client-secret` Secret (key `oidc-client-secret`) so the appserver can consume it: `oc create secret generic oidc-client-secret --from-literal=oidc-client-secret=<value> -n <ns>`.
- **Issuer Alignment**: The appserver `appserver.oidc.issuer` must equal `https://<keycloak-route-host>/realms/iqgeo`. Mismatch breaks OIDC discovery.
- **Bulk Users**: Run `NAMESPACE=<ns> ./deployment/keycloak-add-users.sh --from-csv deployment/users.csv` to provision users idempotently (skips existing).
- **Diagnostics**: Verify discovery `curl -sk https://<kc-host>/realms/iqgeo/.well-known/openid-configuration`; check appserver OIDC logs for redirect-URI / issuer mismatches.

## 9. IQGeo Database Schema Operations (myw_db via Tools image)
- **Where it runs**: Inside the Tools image (appserver/tools share the image). Either via the appserver entrypoint scripts on first boot (`deployment/entrypoint.d/600_init_db.sh`, `610_upgrade_db.sh`) or by execing into a running pod / running a dedicated OpenShift Job.
- **Create / verify DB**: confirm the database exists (the `300_ensure_database` entrypoint step) and `db-credentials` Secret is mounted.
- **Install modules** (idempotent — guarded by version check): 
  - `myw_db $MYW_DB_NAME install workflow_manager`
  - `myw_db $MYW_DB_NAME install groups`
  - plus any other module declared in `.iqgeorc.jsonc` (`custom`, `construction_print`).
- **Upgrade**: `myw_db $MYW_DB_NAME upgrade` after image/version bumps (see `610_upgrade_db.sh`).
- **Verify**: `myw_db $MYW_DB_NAME list versions --layout keys` — confirm each expected schema shows `version=`.
- **As an OpenShift Job**: `oc run iqgeo-dbinit --image=<tools-image> --restart=Never --command -- bash -c "myw_db $MYW_DB_NAME install workflow_manager"` (or template a Job manifest). Hand connection-refused/migration errors to the SRE persona.

## 10. Secrets & OpenBao Operations
- **Pull Secret (Harbor)**: 
  - `oc create secret docker-registry container-registry --docker-server=harbor.delivery.iqgeo.cloud --docker-username=<u> --docker-password=<pw> -n <ns>`
  - Link to ServiceAccounts: `oc secrets link default container-registry --for=pull` (repeat for `appserver`, `builder`).
- **DB Credentials**: `oc create secret generic db-credentials --from-literal=username=iqgeo --from-literal=password=<pw> -n <ns>` (keys must match `global.db.auth.usernameKey/passwordKey`).
- **OIDC Secret**: created by the Identity skill (`oidc-client-secret`).
- **OpenBao (standalone, prod)**: Deploy the OpenBao server chart first, then wire the platform via `deployment/iqgeo-platform-openbao-standalone.yaml`:
  - Set `openbao.url` to `https://<release>.<ns>.svc:8200`, `authType: kubernetes`, `authPath: auth/kubernetes`.
  - Create the `openbao-ca` Secret holding the server CA cert (`tlsSecret`).
  - Ensure the k8s auth role (`openbao.role`, defaults to the namespace) matches the bootstrap tenant and the namespace is in `boundNamespaces`.
- **Rule**: Secrets are created in-cluster (or via OpenBao) — NEVER commit plaintext secret values to Git. Helm values must reference `existingSecret` only.
