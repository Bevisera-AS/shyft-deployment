# Task: Shyft beyond Sigma2

Plan: [implementation.md](implementation.md).

## Background

- Olga Silantyeva runs Shyft hydrology services on Sigma2 NIRD (Kubernetes) for
  [egusphere-2025-4071](https://doi.org/10.5194/egusphere-2025-4071). Setup: [Zenodo 17813414](https://doi.org/10.5281/zenodo.17813414).
- Ask: the same for AWS, maybe Azure. Sizing: [Shyft podman guide](https://gitlab.com/shyft-os/shyft/-/wikis/How-to/Run-a-complete-Shyft-micro-service-system-with-podman)
  (main ≥ 4 cores, 32 GB, 100 GB; drms 16–32 fast cores each).
- Approach: one Helm chart modelled on [PSPDFKit document-engine](https://github.com/PSPDFKit/helm-charts/tree/master/charts/document-engine), tested in GitHub Actions.

Sigma2 today (Shyft 28.0.0):

| Deployment | Runs | Replicas | Request → limit |
|---|---|---|---|
| shyftservices | task, stm, dstm, parameter, state, gcd, goal_function in one container | 1 | 2/16Gi → 4/24Gi |
| shyftdtss | dtss | 1 | 2/32Gi → 4/64Gi |
| shyftdrms | drms | 8 | 16/64Gi |

All pods mount two claims: `/shyft-var` (service DBs) and `/shyft-data`. Images are re-pushed to Sigma2's registry,
the only one its Kubernetes can pull from. Don't carry over: services backgrounded in one container, HTTP Ingresses
on a binary protocol, drms Service on 20008 (drms listens on 22008), pod IP from `/etc/hosts`.

## Requirements

1. One chart: task, rmd, parameter, state, dtss, dstm, stm, goal_function, drms.
2. Profiles: Sigma2 NIRD (today's setup: mirrored image, base port 22000, 8 × 16 CPU/64Gi drms, both claims),
   AWS EKS, Azure AKS.
3. drms scales by replicas. Databases survive restarts and chart upgrades, proven by tests.
4. Nothing exposed to the internet.
5. GitHub CI: lint, unit tests, kind install and upgrade, a tiny hydrology run,
   signed releases of validated `master` commits only.
6. Everything pinned.

Out of scope: cluster provisioning; VM + podman; migrating 28 databases to 37.

Decided 2026-11-12: Shyft 28 is dropped. The chart targets the current Shyft line (37.3). Upstream's registry
no longer has the 28.0.0-1.1 image, so CI could not have tested it. Re-running the paper on Shyft 28 means
Sigma2's own mirrored image and the Zenodo manifests, not this chart.

## Assumptions

Verified in upstream source at tag 37.3.0-1.1 and in the image (details: `docs/shyft-services.md`):

- Port = base + 2·rel; binary protocol only.
- rel 1 is `rmd.py`; it reads `SHYFT_GCD_HOST` and keeps its database in `gcd/db`.
- Config via `SHYFT_SERVICE_*` and `SHYFT_<SVC>_HOST`; data in `<root>/<svc>/db`.
- drms registers with task, re-registers every 5 s, unregisters on SIGTERM. Registrations never expire:
  a dead drms stays queued and is retried.
- Image uid/gid is 1000 (user `ci`). The image is amd64 only.
- drms reads no files: models and forcing data reach it over the protocol. It does not need `/shyft-data`.
- A run does not survive losing its drms: task returns failure and nothing retries.
- Shyft's protocol has no authentication (no credentials anywhere in the service scripts or clients).

Unverified:

- "Settings" means deployable config, not a sizing write-up.
- Sigma2 figures are reservations, not measured use.
- Sigma2 still pulls only from its own registry; NIRD can run Helm; NIRD enforces NetworkPolicy.
- Azure comes after AWS.
