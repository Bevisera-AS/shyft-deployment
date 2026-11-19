# CI scenarios

`ct install` (`mise run e2e`) installs the chart once per `*-values.yaml` file here, on kind, and runs `helm test`.
`ct lint` (`mise run lint`) runs `helm lint` with each of them. `mise run kubeconform` validates their rendered
manifests.

| File | What it covers |
|---|---|
| `00-default-values.yaml` | The defaults, plus the demo model run |
| `01-core-only-values.yaml` | No drms, emptyDir instead of a volume, NetworkPolicy off |
| `02-non-default-values.yaml` | Two drms on two nodes with a PodDisruptionBudget, base port 22000, a Service named `shyft`, another uid/gid, memory limits, extra env and labels |

Not here, because they need more than a values file: existing claims, restarts, upgrades, drms scaling and
refused connections are in `hack/*-test.sh`. The `examples/` profiles need cloud or NIRD resources and are
only rendered and validated.
