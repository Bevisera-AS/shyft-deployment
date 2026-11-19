# AGENTS.md

Helm chart for the [Shyft](https://gitlab.com/shyft-os/shyft) hydrology micro-services on Kubernetes:
Sigma2 NIRD, AWS EKS, Azure AKS; kind in CI.

> Task: [task.md](docs/llm-torture/2026.11.7-initial-implementation/task.md).
> Plan: [implementation.md](docs/llm-torture/2026.11.7-initial-implementation/implementation.md). It records past
> work: read it, never edit it, not even to tick a box.

## Ground rules

- Precedence: explicit user instruction > this file > everything else. Unsure about Shyft behaviour? Read
  [docs/shyft-services.md](docs/shyft-services.md), then upstream `examples/hydrology/service/*.py` at the tag
  in `values.yaml`. Don't guess.
- Build and test logic lives in mise tasks (`mise.toml`) and `hack/`. Workflows only orchestrate: checkout,
  tools, gating, artifacts. `release.yaml` packages, attests, then publishes with the chart-releaser action. Keep tasks to a few commands or one loop; anything with more logic goes in `hack/`, where shellcheck sees it.
- Tasks run under `bash -euo pipefail` (`[task_config] shell` in `mise.toml`). Keep it: mise's default,
  `sh -o errexit`, loses a failure in a pipeline, and mise ignores `unix_default_inline_shell_args` in a
  project file.
- A task's `depends` run in parallel; a sequence is `run = [{ task = "a" }, { task = "b" }]`. `mise run a b`
  passes `b` to task `a` as an argument.
- Only touch kind clusters (context `kind-*`). Never run `kubectl`/`helm` against any other context. The
  tasks enforce this: every one that touches a cluster runs through `hack/kind.sh`, which uses `.tmp/kubeconfig`
  (never yours) and refuses unless the context is `kind-$KIND_CLUSTER` and the cluster runs the Kubernetes
  version of `KIND_NODE_IMAGE`; a version it cannot read is a refusal too (only `dump` skips that check). Don't
  put `KUBECONFIG` in `mise.toml`'s `[env]`: it would follow everyone into an activated shell.
- Never hand-edit generated files: `charts/*/README.md`, `charts/*/values.schema.json`,
  `charts/*/tests/__snapshot__/`.

## Layout

```
charts/shyft-hydrology/  chart
  templates/             _ports.tpl (all port arithmetic), _container.tpl (the one container), workloads,
                         tests/_pod.tpl (the one helm test pod)
  files/                 Python run by the helm test pods
  tests/                 helm-unittest suites and snapshots
  ci/                    values files that `ct` installs on kind
  examples/              platform profiles: rendered and validated, never installed in CI
hack/                    scripts called by the mise tasks; kind.sh guards every cluster call; *-test.sh are the kind tests
docs/                    shyft-services.md (what the chart relies on in Shyft), platforms.md
docs/llm-torture/<date>-<slug>/  one piece of work: task.md (requirements, assumptions) + implementation.md (plan);
                         a record of the past once written: never edited
.github/                 workflows, ct/kind/yamllint config, Renovate
mise.toml                every tool, pinned, and every task (`mise tasks` lists them)
```

## Commands

`mise install` installs the tools; `mise trust` once, the first time. Then `mise run <task>`:

| Task | Does |
|---|---|
| `check` | everything without a cluster, in turn: `check-generated`, `lint`, `lint-actions`, `unittest`, `kubeconform` |
| `docs` / `schema` | regenerate the chart's README.md (helm-docs) / values.schema.json |
| `check-generated` | regenerate, fail if either was stale |
| `lint` | `ct lint` on every chart (yamllint, Chart.yaml, `helm lint` per `ci/` file), yamllint on examples and tests, changelog entry, shellcheck |
| `check-version` | charts changed against `origin/master` have a higher version (needs commits; CI runs it on PRs) |
| `lint-actions` | actionlint + zizmor |
| `unittest` / `snapshot-update` | helm-unittest |
| `kubeconform` | render `ci/` + `examples/`, validate against `K8S_VERSIONS` |
| `kind-up` / `kind-down` | 3-node kind with Calico |
| `load-image` | put the chart's Shyft image on the kind workers: each pulls it, in parallel |
| `e2e` | what CI runs on kind: `ct-install` (`ct install --upgrade` per `ci/` file, runs the helm tests), then `test` |
| `test [name]` | every `hack/*-test.sh`, or one: `mise run test drms` (also `persistence`, `networkpolicy`, `existing-claims`) |
| `upstream-drms` | not in e2e: what a dead drms registration costs upstream. Run after a Shyft bump |
| `dump` | diagnostics into `.tmp/dump/` |
| `render [profile]` | render an `examples/` profile: `mise run render sigma2-nird` |

Knobs, from the environment: `KIND_NODE_IMAGE`, `MISE_KUBECTL_VERSION` (match the cluster's minor), `K8S_VERSIONS`.

Before pushing: `mise run check`. Chart changes: also `mise run kind-up`, `mise run load-image`, `mise run e2e`
(about 10 minutes).

## Shyft invariants (do not "fix")

Read from upstream source at tag 37.3.0-1.1 and checked against the image. Details and sources:
[docs/shyft-services.md](docs/shyft-services.md).

- Port = `basePort + 2·rel`; `+1` is a web port Shyft never starts. `rel` is hard-coded upstream; only
  `basePort` is configurable. Every port comes from `_ports.tpl`.
  `task 0 · rmd 1 · parameter 2 · state 3 · drms 4 · dtss 5 · dstm 6 · stm 7 · goal_function 8`
- rmd is what Shyft 28 called gcd: its database directory is still `gcd/db` and its host variable `SHYFT_GCD_HOST`.
- Binary protocol only: no Ingress, no HTTP probes. `tcpSocket` probes; expose via `port-forward` or an internal
  load balancer. `service.yaml` refuses a load balancer unless `service.cloud` names the cloud, that cloud's
  internal annotation is present, and no exposure annotation it knows, for any cloud, says otherwise: on AWS a
  public `scheme` wins over the older `internal: "true"`. The chart cannot see the cloud; NOTES says so.
- Configuration is Shyft's own environment: `SHYFT_SERVICE_BASE_PORT`, `SHYFT_SERVICE_ROOT`,
  `SHYFT_SERVICE_INTERFACE`, `SHYFT_SERVICE_HOST`. Core containers get no host: they share a pod and use
  `localhost`.
- `enableServiceLinks: false` on every pod. Kubernetes would otherwise inject `SHYFT_SERVICE_HOST` for a
  Service named `shyft`, and Shyft reads that variable.
- Volumes: `var` is `SHYFT_SERVICE_ROOT` at `/shyft-var`, DBs in `<root>/<svc>/db`; `data` is optional input at
  `/shyft-data`. `core` is a 1-replica StatefulSet, single writer. `volumeClaimTemplates` are immutable:
  changing them breaks upgrades. Ask first.
- `drms` is a stateless Deployment. It needs `--interface $(POD_IP)` (with `0.0.0.0` it registers task's host
  instead of its own) and `--host <core service>`. Re-registers every 5 s; unregisters on SIGTERM.
- drms registrations never expire, and task has no API to list them. A drms killed without SIGTERM (OOM, node
  loss, spot reclaim) stays queued and costs about 2 s per lookup until task restarts. A run on a drms that
  dies fails and is not retried. `mise run upstream-drms` (`hack/drms-dead-registration.sh`) pins this down; it is not in CI, so run it after
  every Shyft bump. While it passes, no spot advice.
- The image runs as `ci` (1000:1000), is amd64 only, and needs a writable `/tmp`.

## Chart conventions

- `values.yaml` comments generate docs and schema. Order matters: `# @schema …` lines first, then `# --`
  description, then `# @section -- NN. Name`.
- Every default lives in `values.yaml`: Helm validates against the schema but never applies its defaults.
  No `| default` in templates, except the image tag (see "Versions and releases").
- The schema is strict (`additionalProperties: false` everywhere, from `.schema.yaml`). Free-form Kubernetes
  maps say `# @schema additionalProperties: true` and hide their default children with `# @schema hidden`;
  lists of Kubernetes objects carry no item type. `tests/schema_test.yaml` shows both directions.
- Helpers are `shyft.*`; one container definition in `_container.tpl`; ports only from `_ports.tpl`.
- Never `{{-` on the line after `---`. No `{{` inside YAML comments. No `{{- /* */}}`: explain rendered YAML
  with YAML comments, they are useful in `helm get manifest`.
- `.helmignore` patterns for top-level directories are anchored (`/tests/`): a bare `tests/` also drops
  `templates/tests/`.
- Every container has a memory request and a memory limit by default, test pods included, and no CPU limit
  (it only throttles). `shyft.checkResources` fails a memory request above its limit: Helm merges values, so
  a raised request alone keeps the default limit. A new container goes through it too.
- Pin every image, test pods included. Test and probe pods use the Shyft image: it is already on the nodes.
  Outside the templates, the image reference comes from `hack/image.sh`, which renders the chart: never
  rebuild it from `repository` and `tag`, that drops `image.digest`.
- Anything a workload pod needs in order to be scheduled, the helm test pods need too (`tests.nodeSelector`,
  `tests.tolerations`, `tests.affinity`).
- uid/gid in `securityContext` only from the verified image config (1000:1000 for 37.3.0-1.1).

## Tests

- Values/template change → helm-unittest case in `charts/*/tests/`. With a `[*]` path, `equal` compares each
  match with the value; to pin a whole list, compare the list.
- New feature → a values file in `ci/` (listed in `ci/README.md`): prefer adding to `02-non-default-values.yaml`
  over a new file, since each file is one more install per lane. If it needs more than a values file
  (existing claims, a restart, a refused connection), a `hack/*-test.sh`, plus its own step in
  `lint-test.yaml` (`mise run lint` fails without one).
- Snapshots change only via `mise run snapshot-update`; give the reason in the commit message.
- `examples/` are kubeconform-only: they need NIRD/cloud resources.
- A NetworkPolicy test needs a connection that must be refused next to each one that must work
  (`hack/networkpolicy-test.sh`): a cluster that enforces nothing passes every "it connects" test.
- kind runs Calico, not kindnet (`.github/kind-config.yaml` says why).
- `persistence-test.sh` and `existing-claims-test.sh` run in namespaces that enforce the `restricted` Pod
  Security Standard: a new pod or container must keep meeting it.
- The model-run helm test (`tests.modelRun.enabled`) writes demo data. It is on in `ci/`, off by default.

## Versions and releases

- Chart version is the chart's own SemVer, starting at `0.0.1`; it says nothing about the Shyft version. It goes
  up on every chart change (`mise run check-version`): patch for fixes and a Shyft patch bump, minor for
  features, a new Shyft line, or a change that breaks values, selectors or PVCs (0.x allows that; the
  changelog says what to do). From 1.0.0 on, breaking changes take a major.
- Chart upgrades keep data (`hack/persistence-test.sh`). Migrating databases between Shyft majors is not the
  chart's job.
- `appVersion` is the exact Shyft image tag the chart deploys and was tested with, e.g. `"37.3.0-1.1"`.
  `image.tag` is empty by default and overrides it (`| default .Chart.AppVersion`, the one exception to "no
  `| default`": it is Helm's own idiom). Renovate bumps `appVersion` (`# renovate:` comment); repository renames
  (`fedora44-shyft-app` → the next Fedora) are manual.
- One supported Shyft line at a time. Shyft 28 is not supported: upstream removed its image.
- `CHANGELOG.md` per chart, Keep a Changelog, headers `## [x.y.z] - YYYY-MM-DD`, list items with `*`
  (`mise run lint` checks both). Release notes come from it. It is packaged with the chart, so changing it is a
  chart change and needs a version bump: fold changelog-only fixes into the next real change.
- Releases are CI-only: `release.yaml` reruns `lint-test.yaml` on the pushed `master` commit, then packages every
  chart, attests the packages and publishes them with chart-releaser (`skip_existing`) in the `release`
  environment. Nothing is downloadable before it is attested. A release that failed halfway (a draft
  chart-releaser left, a release without its package or index entry) is repaired by a human, not by CI.
- Published means a GitHub release `<chart>-<version>` plus `index.yaml` on the `gh-pages` branch, which Pages
  serves as the Helm repo. Never create a release or touch `gh-pages` by hand, unless a human asks for that
  repair. 0.0.4 is the first version there: 0.0.1–0.0.3 were deleted.
- chart-releaser only adds to `index.yaml`, never removes. Deleting a GitHub release leaves its entry, and
  `helm search` then lists a version whose download is 404: remove the entry on `gh-pages` in the same repair.
- chart-releaser commits `index.yaml` straight to `gh-pages` as the GitHub Actions app, signed through GitHub's
  API (`.github/cr.yaml`). So the `gh-pages` ruleset is deletion and non-fast-forward only: a pull-request rule
  would refuse that commit and leave the release half-published.

## CI

`lint-test.yaml` (PR; jobs `Workflows`, `Chart`, then, once both passed, `kind (newest)` on 1.37; on `master` also
`kind (oldest)` on 1.34)
· `release.yaml` (master; reuses it, so both kind lanes gate every release). Required checks: `Workflows`, `Chart`,
`kind (newest)`. A failure only 1.34 shows surfaces after the merge, before the release.
Actions pinned by SHA; Renovate bumps them, the tools in `mise.toml`, the Shyft image and Calico.
