# Changelog

#### Unreleased

- Agentic deployment: added 4 new agent personas (Image Build & Registry Engineer, Identity & Access Specialist, Database & Schema Specialist, Secrets & OpenBao Specialist) to `agents.md`
- Agentic deployment: added 4 new skill sets (Image Build & Registry, Keycloak/OIDC, myw_db schema ops, Secrets & OpenBao) to `skills.md`
- Agentic deployment: added execution-loop phases for image build (Phase 0), secrets bootstrap (Phase 0.5), identity configuration (Phase 6.5) and DB schema init/migration (Phase 6.6); expanded completion criteria in `execution_loop.md`
- Deployment fix: normalized `deployment/entrypoint.d/*.sh` to LF line endings (CRLF broke the `#!/bin/bash` shebang inside the Linux container, crashing the appserver on `270_adjust_oidc_conf.sh`)
- Deployment hardening: `dockerfile.appserver` now strips CR (`sed -i 's/\r$//'`) and re-applies exec bits on entrypoint scripts as a defensive measure against Windows CRLF
- Added `.gitattributes` enforcing `eol=lf` for `*.sh`, `entrypoint.d/*`, `*.bash` and Dockerfiles so scripts stay LF on Windows checkouts
- OpenShift fix: appserver group now mounts emptyDir volumes at `/var/log/apache2` and `/var/run/apache2` so Apache can start under the random non-root UID (was CrashLooping with "Permission denied: could not open transfer log file")
- OpenShift fix: added `combined-registry` to `image.pullSecrets` in `values-smartport.yaml` so pods can pull the internal-registry appserver/tools images (the chart-level pull secret list overrides SA-linked secrets)
- Deployment verification: full smartport stack (appserver 1/1, redis, postgis, keycloak, pgadmin) confirmed Running; internal `/livez` and `/healthz` return 200; edge Route `iqgeo-platform` created
- OpenShift fix (worker): pinned `workerGroups[default-worker].securityContext.runAsUser` to `1002990000` — the chart defaulted the worker to `runAsUser: 33` (www-data), which the namespace `restricted-v2` SCC rejected (valid range 1002990000–1002999999), leaving `default-worker` at 0/1 (FailedCreate)
- OpenShift fix (worker): added podAffinity co-locating the worker with the appserver (`app=iqgeo-platform-dev`) so the RWO `shared-data` PVC (ontap-nas-ssd) can attach to both pods on the same node (was Multi-Attach error)
- Deployment fix (worker): worker init container now strips `231-oidc-config.sh` and `270_adjust_oidc_conf.sh` (workers have no OIDC conf.json → crash) and rewrites `910_start_worker.sh` to `exec myw_task start` in the FOREGROUND (stock script backgrounds it, so the dedicated worker container exited 0 and CrashLooped)
- Deployment verification (worker): `default-worker` now 1/1 Running, 0 restarts; 2 RQ workers listening on `platform_db_load`, `platform_extracts`, `default` queues with scheduler active
- Deployment verification (credentials): platform login `admin` / `_mywWorld_` confirmed present in both the Keycloak `iqgeo` realm and the `myw.user` table; Keycloak admin console is `admin` / `admin`
- OpenShift fix (ingress): added `deployment/smartport/networkpolicy-allow-router.yaml` (`allow-from-openshift-router`) — every Route returned HTTP 503 "Application is not available" while pods were 1/1 Running and reachable in-cluster (pod→service: appserver 301, keycloak 200). Root cause: the namespace's default-deny NetworkPolicy set only admitted namespace-scoped ingress, but this cluster's OpenShift router runs on the node **host network**, so its traffic carries no pod/namespace identity a `namespaceSelector` can match. Proven empirically — a namespaceSelector rule (openshift-ingress / both policy-group label conventions) left routes timing out, while an any-source rule immediately served them. Final policy admits ingress from any source (`ipBlock 0.0.0.0/0` + `::/0`), safe because these are router-only HTTP/Keycloak frontends. Verified through the router: iqgeo 301, keycloak 200, pgadmin 302.





#### v1.2.0 (05/28/2026)


- DX-44: deployment: add Kubernetes overlay for standalone OpenBao
- DX-40: docker-compose: added OpenBao and Centrifugo services, disabled by default
- SRE-869: deployment: add Centrifugo deployment overlays and documentation;
- Docs: add PostGIS image version guidance to devcontainer READMEs
- Docs: add guidance on building WFM dev database (#100)

#### v1.1.0 (04/02/2026)

- PLAT-13664: Cleans npm manifests from dev dependencies and removes node_modules in build
- deployment tools: use PY_VERSION for site packages copy
- docker-compose: Added .ai mount directory for use with ai-toolkit

#### v1.0.1 (02/18/2026)

- fix initial value for PROJECT_REPOSITORY in deployment/.env.example
- deployment: docker-compose: configure keycloak for local http deployment
- github action: include arg to allow product repository override
- deployment appserver: handle Python 3.12 base images by using MYW_PYTHON_SITE_DIRS env var
- build_images: remove hardcoding platform to amd64

#### v1.0.0 (02/13/2026)

- PLAT-11613: deployment: add Kubernetes related files and instructions
- deployment: added github action to automate image building
- devcontainer: added pgadmin service to list in devcontainer.json so it's now available when using the vscode extension
- update example configuration to NMT 3.5

#### v0.8.2 (10/21/2025)

- iqgeorc.jsonc updated default to platform 7.4
- PLAT-12000: Added RQ_REDIS_URL to deployments app server setup to match worker/tools setup
- PLAT-12007: Added 610_upgrade_db.sh to include module upgrade commands.

#### v0.8.1 (07/16/2025)

- .devcontainer: fixed permission issues with anywhere script.
- .devcontainer: added SSL_REQUIRED environment variable to keycloak service to fix HTTPs required issue.
- .devcontainer: Added support for developers to override the Apache port used inside the container via configuration.

#### v0.8.0 (06/16/2025)

**Fixes:**

- .devcontainer: rq-dashboard changed to trigger on container start
- .devcontainer: tsconfig: add missing myWorld path
- deployment: fix keycloak address in sed command

**Changes:**

- PLAT-10007: devcontainer: Add ROPC_ENABLE as an optional environment varialble
- PLAT-10597: enable debugging of LRT tasks
- PLAT-11630: improvements for anywhere development with running dev container.
- .devcontainer: add REDIS_PORT to .env.example
- .devcontainer: Removed the `910_start_worker.sh` entrypoint script as this is now provided by the platform denenv image.

#### v0.7.2 (04/10/2025)

**Fixes:**

- Fixed missing `PROJ_PREFIX` usage in deployment compose (#49)

**Changes:**

- Updated reference to platform from version 7.2 to 7.3 (#52)
- Removed volume in `devcontainer` to keep JavaScript bundles (#48)

#### v0.7.1 (02/26/2025)

**Changes:**

- Align files with the initial state of `.iqgeorc.jsonc` (#47)
- Added `tsconfig` (#46)

#### v0.7.0 (02/24/2025)

**Changes:**

- Updated container registry paths for new registry organization (#43)

#### v0.6.0 (01/31/2025)

**Changes:**

- Updated `docker-compose` to use PostGIS version 15-3.5

#### v0.5.0 (01/13/2025)

**Fixes:**

- Fixed incorrect `redis_url` environment variable defined for `rq-dashboard` in `docker-compose` (#39)
- Fixed `KEYCLOAK_HOST` URL in `docker-compose` for remote hosts (#34)

**Changes:**

- Added "Restart LRT task worker" task (#38)
- Added port forwarding for the `rq-dashboard` container in `devcontainer.json` for remote hosts (#40)
- Updated `devcontainer` README with a link to developing on Windows documentation (#37)
- Removed use of `COPY --link` in `dockerfile` when using `--from` (#36)
- Updated `rq-dashboard` in `docker-compose` with parameterized name (#33)
- Updated `.gitignore` to ignore new `tsconfig` files (#32)
- Improved support for `KEYCLOAK_HOST` environment variable usage in Keycloak (#29)
- Removed `memcached` from `remote_host` shared services (#31)
- Updated `iqgeorc` version to 0.5.0 (#30)
- Added long-running task configurations (#23)
