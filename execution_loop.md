# Autonomous Execution Loop

You are operating in a fully autonomous loop. You must not stop, pause, or ask for user input unless the entire IQGeo platform is successfully deployed and accessible. 

Follow this exact loop for every task. **Phases run in dependency order** — images and secrets MUST exist before any workload is deployed, and the database/identity layers MUST be functional before the platform is considered healthy.

### Phase 0: Supply Chain — Build & Publish Images (Image Build & Registry Engineer Persona)
NOTHING can be deployed until the project images exist in a registry the cluster can pull from.
1. Authenticate to the source registry: `docker login harbor.delivery.iqgeo.cloud`.
2. Ensure `deployment/.env` exists (copy from `.env.example`) and `PROJ_PREFIX`/`PROJECT_REGISTRY`/`PROJECT_REPOSITORY` are consistent with `.iqgeorc.jsonc`.
3. Build and push: `PUSH=true ./deployment/build_images.sh` (or run on-cluster via `oc new-build`/`oc start-build` when no Docker host is available — images then land in `image-registry.openshift-image-registry.svc:5000/<ns>/...`).
4. Verify all three images (`build`, `appserver`, `tools`) exist with the tag referenced in the active values file: `oc get istag -n <ns>` or `skopeo inspect`.
5. Do NOT proceed to the Helm release until image verification passes.


### Phase 0.5: Secrets Bootstrap (Secrets & OpenBao Specialist Persona)
Secrets MUST exist in the target namespace before any workload starts, or pods fail with missing-secret / ImagePullBackOff.
1. Create the Harbor pull secret and link it: `oc create secret docker-registry container-registry ...` then `oc secrets link default container-registry --for=pull` (also `appserver`, `builder`).
2. Create `db-credentials` (keys `username`/`password` matching `global.db.auth`).
3. Reserve `oidc-client-secret` — it is finalised in Phase 6.5 once Keycloak issues the client secret (create a placeholder if the chart requires it to exist at deploy time).
4. For production, deploy/verify OpenBao and wire it via `deployment/iqgeo-platform-openbao-standalone.yaml` (`openbao-ca` Secret, k8s auth role, `openbao.url`).
5. Verify: `oc get secret -n <ns>` shows all required secrets; confirm none are committed to Git in plaintext.

### Phase 1: Plan (Orchestrator Persona)

1. Identify the current state of the deployment.

2. Define the next immediate atomic task (e.g., "Create OpenShift Project", "Deploy PostGIS", "Run DB Migrations via Tools Job").
3. State the expected outcome.

### Phase 2: Execute (Architect / Specialist Persona)
1. Write or modify the necessary code (YAML, Helm values).
2. Execute the deployment command (`helm upgrade`, `oc apply`).
3. Use `--wait` or `--timeout` flags so the CLI blocks until the rollout finishes.

### Phase 3: Verify (SRE Persona)
1. Run `oc get pods -n <project>` and check if all pods are `Running` and `Ready` (1/1 or 2/2).
2. Run `oc get rollout status` to ensure deployments succeeded.
3. Check `oc logs` for application startup errors (e.g., database connection refused).

### Phase 4: Self-Heal (If Verification Fails)
IF any pod is in `CrashLoopBackOff`, `ImagePullBackOff`, `Pending`, or `Error`:
1. **STOP** executing new tasks.
2. Switch to **SRE Persona**.
3. Run `oc describe pod <failing-pod>` and read the `Events` section.
4. Run `oc logs <failing-pod> --previous` to see why it crashed.
5. Identify the root cause (e.g., "Permission denied writing to /var/lib/postgresql/data").
6. Formulate a fix (e.g., "Update Helm values to add fsGroup 26").
7. Apply the fix and return to **Phase 2**.

### Phase 5: Supporting Services Deployment (Architect / pgAdmin Specialist Personas)
Deploy the dependencies the platform relies on, using the standalone manifests in `deployment/`.
1. Deploy PostGIS: `oc apply -f deployment/postgis-deployment.yaml -n <project>` and wait for it to be `Ready`.
2. Deploy Keycloak: `oc apply -f deployment/keycloak-deployment.yaml -n <project>`.
3. Deploy pgAdmin 4 manually via `deployment/pgadmin-deployment.yaml`.
4. Verify the pgAdmin pod starts: `oc get pods -l app=pgadmin -n <project>`.
5. Wait for readiness probe to pass (GET `/misc/ping` on port 5050).
6. Create/verify admin user via `setup.py` CLI: `oc exec <pod> -- /venv/bin/python3 /pgadmin4/setup.py get-users`.
7. If a user needs to be created or password reset, use `setup.py add-user` or `setup.py update-user` — NEVER modify the SQLite DB directly.
8. Verify the pgAdmin Route is accessible: `curl -sk https://pgadmin-<project>.apps.<cluster>/misc/ping`.

### Phase 6: Deploy the IQGeo Platform via Helm (Helm & IQGeo Specialist Persona)
Deploy the platform directly with Helm — there is NO GitOps/Argo CD layer in this workflow.
1. Select the correct values overlay for the target: `deployment/values-openshift-v3.yaml` (chart v3.x, PostGIS/Keycloak deployed separately) or `deployment/values-openshift.yaml`.
2. Run the release, blocking until the rollout finishes:
   - `helm upgrade --install iqgeo-platform <chart-ref> -n <project> -f deployment/values-openshift-v3.yaml --wait --timeout 15m`
   - (`<chart-ref>` is the IQGeo platform Helm chart — OCI ref `oci://harbor.delivery.iqgeo.cloud/helm/iqgeo-platform` or a local/unpacked chart directory.)
3. If the release fails or times out, switch to the SRE Persona (Phase 4), fix, then re-run `helm upgrade --install`.
4. Verify the release: `helm status iqgeo-platform -n <project>` shows `deployed`, and `oc get pods -n <project>` shows appserver/workers/Redis/Tools all `Running`/`Ready`.
5. Confirm the OpenShift Route was created: `oc get route -n <project>`.


### Phase 6.5: Identity Configuration (Identity & Access Specialist Persona)
The appserver runs with `oidc.enabled: true` — it cannot authenticate users until Keycloak is configured.
1. Verify the Keycloak pod is Running: `oc get pods -l app=keycloak -n <ns>`.
2. Ensure the `iqgeo` realm exists; create it via `kcadm.sh` if missing (use `--config /tmp/kcadm.config`).
3. Register/confirm the `iqgeo-oidc` confidential client with redirect URIs pointing at the appserver Route host.
4. Read the client secret and write it into the `oidc-client-secret` Secret; restart the appserver if the secret changed.
5. Confirm `appserver.oidc.issuer` matches `https://<keycloak-route-host>/realms/iqgeo`.
6. Bulk-provision users: `NAMESPACE=<ns> ./deployment/keycloak-add-users.sh --from-csv deployment/users.csv`.
7. Verify discovery: `curl -sk https://<kc-host>/realms/iqgeo/.well-known/openid-configuration`.

### Phase 6.6: Database Schema Init & Migration (Database & Schema Specialist Persona)
The platform DB must be initialised with the IQGeo schema and all declared modules.
1. Confirm PostGIS is healthy and `db-credentials` is consumed correctly (no connection-refused in appserver logs).
2. Run schema init via the Tools image (entrypoint `600_init_db.sh` on first boot, or a dedicated Job/`oc exec`):
   - `myw_db $MYW_DB_NAME install workflow_manager`
   - `myw_db $MYW_DB_NAME install groups`
   - plus any other module in `.iqgeorc.jsonc` (`custom`, `construction_print`).
3. After version/image bumps, run `myw_db $MYW_DB_NAME upgrade` (entrypoint `610_upgrade_db.sh`).
4. Verify: `myw_db $MYW_DB_NAME list versions --layout keys` shows `version=` for every expected schema.
5. Hand any migration/connection errors to the SRE persona (Phase 4).

### Phase 7: Completion
Only when ALL of the following are true, output the success message:
- Images for `build`/`appserver`/`tools` are published and pullable (Phase 0).
- All required Secrets exist (Phase 0.5); OpenBao wired for prod.
- All IQGeo components (Appserver, workers, PostGIS, Redis, Keycloak, pgAdmin, Tools/CronJobs) are healthy.
- Keycloak `iqgeo` realm + `iqgeo-oidc` client are configured and OIDC discovery succeeds (Phase 6.5).
- The IQGeo schema and all declared modules are installed/upgraded (Phase 6.6).
- The Helm release reports `deployed` and the OpenShift Routes are accessible.

Then output:
"DEPLOYMENT SUCCESSFUL: IQGeo Platform is fully operational on OpenShift via Helm."



