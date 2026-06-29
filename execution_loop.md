# Autonomous Execution Loop

You are operating in a fully autonomous loop. You must not stop, pause, or ask for user input unless the entire IQGeo platform is successfully deployed and accessible. 

Follow this exact loop for every task:

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

### Phase 5: pgAdmin Deployment (pgAdmin Specialist Persona)
1. Deploy pgAdmin 4 using manifests from `argocd/environments/<env>/manifests/pgadmin/` (or manually via `deployment/pgadmin-deployment.yaml`).
2. Verify the pod starts: `oc get pods -l app=pgadmin -n <project>`.
3. Wait for readiness probe to pass (GET `/misc/ping` on port 5050).
4. Create/verify admin user via `setup.py` CLI: `oc exec <pod> -- /venv/bin/python3 /pgadmin4/setup.py get-users`.
5. If user needs to be created or password reset, use `setup.py add-user` or `setup.py update-user` — NEVER modify the SQLite DB directly.
6. Verify the pgAdmin Route is accessible: `curl -sk https://pgadmin-<project>.apps.<cluster>/misc/ping`.

### Phase 6: Argo CD Bootstrap (GitOps Engineer Persona)
1. Install Argo CD: `./argocd/install/bootstrap.sh` or apply manifests in sequence:
   - `oc apply -f argocd/install/namespace.yaml`
   - `oc apply -n argocd -f argocd/install/argocd-install.yaml`
   - `oc apply -n argocd -f argocd/install/argocd-route.yaml`
2. Wait for all Argo CD pods to be ready: `oc rollout status deployment/argocd-server -n argocd`.
3. Create the AppProject: `oc apply -n argocd -f argocd/projects/iqgeo-project.yaml`.
4. Grant Argo CD permissions on the target namespace: `oc policy add-role-to-user edit system:serviceaccount:argocd:argocd-application-controller -n <target-ns>`.
5. Deploy the root Application: `oc apply -n argocd -f argocd/applications/root-app.yaml`.
6. Verify all child Applications sync: `oc get applications -n argocd`.
7. Check Application health in the Argo CD UI: `https://argocd-argocd.apps.<cluster>`.

### Phase 7: Completion
Only when ALL IQGeo components (Appserver, PostGIS, Keycloak, pgAdmin, Tools jobs) are healthy, the OpenShift Routes are accessible, and Argo CD Applications show `Synced`/`Healthy` status, output:
"DEPLOYMENT SUCCESSFUL: IQGeo Platform is fully operational on OpenShift via Argo CD GitOps."
