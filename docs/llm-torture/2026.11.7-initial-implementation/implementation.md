# Implementation plan

One Helm chart for the Shyft hydrology stack, tested on kind in GitHub Actions, with profiles for Sigma2 NIRD,
AWS EKS and Azure AKS. Background, requirements and assumptions: [task.md](task.md).

Status, 2026-11-18: the chart, its tests, the tasks and the workflows exist. The kind tests pass on local
clusters with Kubernetes 1.34 and 1.37, the two CI lanes: with `make e2e` on 2026-11-12, and with
`mise run e2e` after the switch to mise tasks on 2026-11-18. Nothing is pushed, so the workflows have not run
on GitHub yet, and no profile has been tried on a real platform.

## Decisions

| Topic | Decision |
|---|---|
| Repo | Public GitHub `lazyoldbear/shyft-deployment`, default branch `master` |
| Chart | `charts/shyft-hydrology`. Version: the chart's own SemVer, starting at 0.0.1 (until 2026-11-18 the plan was `<Shyft major>.<Shyft minor>.<n>`, i.e. 37.3.0). `appVersion` = the exact Shyft image tag (`37.3.0-1.1`); `image.tag` is empty and overrides it (until 2026-11-19 `appVersion` was the line, `37.3`, and the tag was pinned in `values.yaml`) |
| Shyft | One line at a time, now 37.3 (`fedora44-shyft-app:37.3.0-1.1`). Shyft 28 is not supported: upstream removed its image |
| Workloads | `core`: StatefulSet, 1 replica; task, rmd, parameter, state, dtss, dstm, stm, goal_function as containers on localhost, as in upstream's podman pod. `drms`: Deployment, N replicas, one per node preferred. One ClusterIP Service, NetworkPolicy on, no Ingress |
| Configuration | Shyft's own environment variables. `enableServiceLinks: false`, so Kubernetes cannot inject a `SHYFT_SERVICE_HOST` |
| Volumes | `var`: service DBs at `/shyft-var` (`SHYFT_SERVICE_ROOT`), volumeClaimTemplate, `existingClaim` or emptyDir. `data`: inputs at `/shyft-data`, optional `existingClaim`, in core and optionally in drms |
| Exposure | ClusterIP by default. `LoadBalancer` renders only when every known exposure annotation says internal and at least one is present; `NodePort` is rejected by the schema |
| Tasks | mise tasks in `mise.toml`, next to the tools (a Makefile until 2026-11-18). `mise run` always puts the pinned tools first on PATH; Make used whatever was installed |
| Tools | All pinned in `mise.toml`: helm 4, ct (with yamllint and yamale), kind, kubectl, helm-docs, helm-values-schema-json, helm-unittest, kubeconform, actionlint, zizmor, shellcheck, yq. No Helm plugins: the two that are plugins upstream run as plain binaries |
| Generated files | Chart `README.md` by helm-docs from `README.md.gotmpl` + `values.yaml`; `values.schema.json` by helm-values-schema-json, strict. `mise run check-generated` in CI |
| CI Kubernetes | kind `v1.34.11` (on `master`) and `v1.37.0` (every pull request), with Calico: kindnet's NetworkPolicy engine breaks pods under a policy on hosts without conntrack labels (OrbStack) |
| Workflows | `lint-test.yaml` on pull requests; `release.yaml` on `master`, which reuses it. No scheduled run: everything is pinned, and Renovate's pull requests test each bump |
| Required checks | `Workflows`, `Chart`, `kind (newest)`. Pull requests run the 1.37 lane only (about 10 minutes); `master`, and so every release, runs 1.34 too. Skipping kind on docs-only changes was dropped on 2026-11-18 |
| Release | `release.yaml` on `master` reruns `lint-test.yaml` on that commit, then releases in the `release` environment (master only) with chart-releaser, as PSPDFKit's helm-charts does: GitHub release `<chart>-<version>`, and `index.yaml` on `gh-pages`, served by Pages as the Helm repo `https://lazyoldbear.github.io/shyft-deployment`. Each package gets a GitHub build-provenance attestation before it is published. chart-releaser skips versions that already have a release. A half-finished release is repaired by a human (automatic repair, and with it `hack/release-prepare.sh`, was dropped on 2026-11-18: too much code for a rare event) |
| Upgrades | Chart upgrades keep data. Database migration between Shyft majors is not the chart's job |

## 1. Skeleton

- [x] AGENTS.md, CLAUDE.md, README.md, .gitignore
- [x] `.github/` (was `github-staging/`)
- [x] Helm repo: an empty `gh-pages` branch; Settings > Pages > branch `gh-pages`
- [x] `mise.toml`: tools and tasks (as in AGENTS.md)
- [x] uid/gid read from the image: `ci`, 1000:1000
- [x] `docs/shyft-services.md`: ports, env, scripts, drms registration, image facts
- [ ] Commit and push. Then, in the GitHub settings: branch protection on `master` with the three required
      checks; a `release` environment limited to `master`; the Renovate app; delete the stray `main` branch
- [ ] `LICENSE` (the file is a placeholder), then `license` in `Chart.yaml`
- [ ] CODEOWNERS

Dropped: `.pre-commit-config.yaml` (it would repeat the mise tasks), and a Claude Code hook that blocks
non-kind contexts (the mise tasks use their own kubeconfig; the rule in CLAUDE.md stays for hand-typed commands).

## 2. Chart

- [x] `Chart.yaml`, `values.yaml` (annotated, holds every default), `.schema.yaml`, `README.md.gotmpl`,
      `CHANGELOG.md`, generated `README.md` and `values.schema.json`
- [x] Templates: `_helpers`, `_ports`, `_container`, `core-statefulset`, `service`, `drms-deployment`, `drms-pdb`,
      `networkpolicy`, `serviceaccount`, `NOTES.txt` (prints the port-forward command)
- [x] helm-unittest, 10 suites: ports at base 20000 and 22000, core, drms, persistence (claim template /
      existing claim / emptyDir; data volume), network (Service, load balancer guard, policies), security,
      naming, helm tests, schema (bad values must fail), snapshots
- [x] helm tests: `test-connection` (read-only, every core service through the Service) and, opt-in,
      `test-model-run` (seeds upstream's demo model, runs it through task, a drms and dtss, reads results back)
- [x] `ci/` scenarios: `00-default`, `01-core-only`, `02-non-default` (merged from three on 2026-11-18)
- [x] `hack/`:
  - `persistence-test.sh`: data survives a pod restart, an upgrade (from `origin/master` once the chart is
    there) and uninstall + reinstall; drms re-registers after task restarts
  - `existing-claims-test.sh`: both volumes on claims that exist beforehand, as on Sigma2
  - both of these run under the `restricted` Pod Security Standard
  - `drms-test.sh`: scale 2 → 3 → 1, every drms takes work, leavers unregister
  - `drms-dead-registration.sh` (`mise run upstream-drms`, not in CI): what a dead registration costs upstream
  - `networkpolicy-test.sh`: labelled clients connect, everything else is refused, including direct access to drms
  - `dump.sh`, `check-changelog.sh`, `fingerprint.py`, `lib.sh`, `image.sh` (the image reference, rendered
    from the chart), `load-image.sh`, `kind-up.sh`, `kind.sh` (the guard every cluster task goes through)

## 3. Platforms and first release

- [x] `examples/sigma2-nird.yaml`: mirrored image with the `sigma2asregistry` pull secret, base 22000, both
      existing claims, 8 drms × 16 CPU/64Gi. Placeholders: registry host, claim names, uid/gid
- [x] `examples/aws-eks.yaml`, `examples/azure-aks.yaml`: storage class, drms node pool, internal load balancer.
      No spot
- [x] `docs/platforms.md`: Sigma2 migration steps (mirror with `skopeo copy`), AWS and Azure prerequisites
- [ ] Try each profile on its platform and correct it. Until then they are only schema-validated
- [ ] First CI run on GitHub: the workflows are linted (actionlint, zizmor) but have never executed
- [ ] Release 0.0.1

## 4. Later

- A client/toolbox pod for running scripts next to the services, as in upstream's "user pod"
- dtss as its own workload
- drms autoscaling; spot (needs registration expiry upstream, or a documented task-restart workaround)
- Upstream: registration expiry; an API to list registered drms; `print()` without flush in `drms.py`;
  the wiki's 37 pod still runs `gcd.py`; `SHYFT_DTSS_CACHE` has no effect
- A multi-arch or arm64 Shyft image upstream would remove the emulation on Apple Silicon
- Manual cloud smoke test on EKS/AKS via OIDC
- Spec-driven harness: [TODO.md](../../../TODO.md)

## Open questions

- Licence?
- Can NIRD run Helm? Fallback: `mise run render sigma2-nird` and apply the output.
- Does NIRD's network plugin enforce NetworkPolicy? Which Kubernetes version does it run (the chart needs 1.30+)?
- Sigma2's registry host, claim names, and the uid/gid that own the storage.
- How does Sigma2 get from Shyft 28 databases to 37: start empty, or migrate with upstream's tools?
- Real sizing: the profiles carry Sigma2's reservations, not measured use.
