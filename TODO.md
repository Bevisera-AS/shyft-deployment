# TODO

## Actual testing

Needs be done.

## Ingress

Needs be done.

## Spec-driven harness

Not started. A larger attempt (requirement syntax, JSON export, audit) was removed on 2026-11-12. This is
the small replacement: write the requirements once, in Lean, and have CI hold every rendered chart against
them.

### The spec

One file, plain Lean 4: `ShyftDeployment.lean` at the repository root, with `lakefile.lean` and
`lean-toolchain` beside it. No dependencies, no custom syntax, nothing generated. About 80 lines.

The spec is a predicate on a deployment. A small record says what a rendered release looks like, with only
the fields the requirements mention. Each requirement is a `Prop` over that record, with task.md's sentence
as its doc comment.

```lean
/-- What a rendered release looks like, as far as the requirements care. -/
structure Deployment where
  basePort  : Nat
  listens   : Service → List Nat    -- every port a container of that service listens on
  exposures : List Exposure         -- one per rendered Service, Ingress, Gateway or route: all of them

/-- R1. All nine services run, each once, on base + 2·rel. -/
def R1 (d : Deployment) : Prop := ∀ s ∈ Service.all, d.listens s = [d.basePort + 2 * s.rel]

/-- R4. Nothing is exposed to the internet. -/
def R4 (d : Deployment) : Prop := ∀ e ∈ d.exposures, e = .clusterIP ∨ e = .internalLoadBalancer
```

Two examples are the only proofs: one deployment that meets the spec, so it is not contradictory, and one
that does not (today's Sigma2 setup: an Ingress, and the drms Service on 20008), so it is not empty.

Start with three requirements, the ones that are static facts about the rendered output:

- R1: nine services, each once, on base + 2·rel.
- R4: nothing internet-facing.
- R3, the static half: one `core` replica on persistent storage; drms is what scales and mounts no database.

R2 (profiles), R5 (CI) and R6 (pinning) stay prose in task.md. So does anything about behaviour over time:
surviving a restart, drms registration. Those belong to the helm tests and `hack/*-test.sh`.

Corrections from a review on 2026-11-12, all folded into the sketch above or the list below:

- `listens` is a list, not an `Option`: an `Option` cannot see a service rendered twice, so it could not
  state "each once".
- `exposures` is a list over every rendered resource that can expose something. One field would let a safe
  Service hide an Ingress or a second, public Service next to it.
- The requirements do not hold for every values file, on purpose. `ci/01-core-only-values.yaml` has no drms
  and no persistent volume. Each scenario and profile must say which requirements it is held to (a small
  table next to the check), and the exceptions must be few and named. Without that, level 1 is either red
  on a supported configuration or quietly skips it.

### With GitHub Actions

Three levels, each usable without the next.

| Level | CI does | A red check means | Needs |
|---|---|---|---|
| 0 | `lake build` | the spec itself is broken | Lean on the runner |
| 1 | renders every `ci/` and `examples/` file and checks each render against the spec | the chart violates a requirement, named in the log | the chart; a render-to-`Deployment` step |
| 2 | the same check on live objects in the kind lanes | the cluster differs from the render | probably not worth it |

**How level 1 can work with the least machinery.** A script in `hack/` turns one `helm template` output into
a Lean file: `def rendered : Deployment := { … }` followed by `example : R1 rendered := by decide`, one line
per requirement. `lean` checks that file. A failure points at the line of the requirement that does not
hold. No JSON parser in Lean and no executable. The alternative, a Lean program that reads the manifests as
JSON, gives better messages and costs about a hundred lines more; start without it.

**Where it runs.** Workflows only orchestrate, so the logic is two mise tasks: `mise run spec` (level 0) and
`mise run spec-check` (level 1). They go in a new job `Spec` in `lint-test.yaml`:

- `lint-test.yaml` runs on every pull request with no path filter, so `Spec` always reports and can be a
  required check beside `Workflows`, `Chart` and the two kind lanes.
- `release.yaml` calls `lint-test.yaml`, so the job gates releases without further wiring.
- Its own job, not steps in `Chart`: a failed Lean download then does not hide the chart lint result, and the
  failing check is named after what failed.
- It needs `contents: read` and no secrets, so it is safe on pull requests from forks.

**Installing Lean.** `leanprover/lean-action`, pinned by SHA like every other action; it reads
`lean-toolchain` and caches the toolchain. Olga's repositories use it (v1.6.0). Locally, contributors need
elan; `mise run spec` should say so when `lake` is missing.

**What stays unverified.** The script that turns YAML into a `Deployment` is ordinary test code. If it
misreads a manifest, a green check means nothing. Two guards: keep it to a few `yq` expressions, and run it
in CI on a fixture that must fail (a manifest with an Ingress), the same way the NetworkPolicy test needs a
connection that is refused.

**Overlap with helm-unittest.** Level 1 checks ports and exposure on every scenario and profile. The
`ports`, `network` and `security` suites stay as they are until the spec check is shown to catch the same
breakage: run it against deliberately broken charts (the mutations those suites catch today) first. Only
then drop what is duplicated.

### Open questions

- Start with R1, R4 and static R3, or R1 alone?
- Can mise install elan? If so, `mise install` covers Lean and the action is not needed.
- Does Renovate track `lean-toolchain`? If not, it needs a custom regex manager in `renovate.json`.
- Should a change to the spec file need the owner's review (CODEOWNERS)? It is the one file where a
  requirement can be weakened in a single line.
- Is level 1 wanted at all, or is level 0 plus helm-unittest enough for this chart?

### Steps

- [ ] Agree on the starting requirements
- [ ] `ShyftDeployment.lean`, `lakefile.lean`, `lean-toolchain`; `.lake/` in `.gitignore`
- [ ] `mise run spec`; job `Spec` in `lint-test.yaml`; add it to the required checks
- [ ] `hack/` script, `mise run spec-check` over `ci/` and `examples/`, the must-fail fixture (the chart exists
      now)
- [ ] Pin updates for `lean-toolchain`
