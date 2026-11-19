# shyft-deployment

Helm chart for the [Shyft](https://gitlab.com/shyft-os/shyft) hydrology micro-services on Kubernetes.

## What it deploys

- `core`: one StatefulSet pod with a container each for task, rmd, parameter, state, dtss, dstm, stm and
  goal_function. One volume holds every database; a second, optional one holds input data.
- `drms`: stateless compute nodes. Scale with `drms.replicaCount`; they register with task themselves.

Shyft uses a binary protocol without authentication, so there is no Ingress. Connect from inside the
cluster, with `kubectl port-forward` (printed after install), or through an internal load balancer.

Everything about the chart itself, including every value:
[charts/shyft-hydrology/README.md](charts/shyft-hydrology/README.md).

## Install (once released)

```sh
helm repo add shyft https://bevisera-as.github.io/shyft-deployment
helm install shyft-hydrology shyft/shyft-hydrology --version <x.y.z> -f my-values.yaml
helm test shyft-hydrology
```

Platform profiles: [charts/shyft-hydrology/examples/](charts/shyft-hydrology/examples/), with notes in
[docs/platforms.md](docs/platforms.md).

Every chart package has a build-provenance attestation. To check one you downloaded from a release:
`gh attestation verify shyft-hydrology-<x.y.z>.tgz --repo Bevisera-AS/shyft-deployment`.

The repository moved from `lazyoldbear/shyft-deployment` on 2026-11-19. The old Helm repository URL,
`https://lazyoldbear.github.io/shyft-deployment`, no longer works: add the one above instead. Packages up to 0.0.3
were attested under the old owner and verify with `--owner lazyoldbear` in place of `--repo`.

## Develop

You need Docker and [mise](https://mise.jdx.dev). Everything else is pinned in `mise.toml`.

```sh
mise trust && mise install
mise run check                                    # seconds, no cluster
mise run kind-up && mise run load-image && mise run e2e   # about 10 minutes, on a local kind cluster
mise run kind-down
```

`mise tasks` lists every task. The tasks create their own kind cluster with its own kubeconfig in `.tmp/`, and
refuse to run against anything else. The Shyft image is amd64 only; on an Apple Silicon Mac it runs under
emulation, which is slower but works.

**Why CI is more complex than usual.** Most Helm chart repositories build CI from ready-made actions
(`chart-testing-action`, `kind-action`) and test little beyond "the chart installs". This repository
deliberately does not:
- The workflows only check out the code, install the pinned tools and call mise tasks.
- The logic lives in `mise.toml` and `hack/`, so the same commands run on a laptop and in CI.
- `hack/*-test.sh` check what installing cannot show: data survives upgrades, network policies refuse
  connections, drms nodes take work.

That is more code than usual. It is affordable because most of it is written and maintained by an AI coding
agent. If you maintain this without one, the conventional setup may suit you better.

Rules for humans and agents: [AGENTS.md](AGENTS.md).
What the chart relies on in Shyft: [docs/shyft-services.md](docs/shyft-services.md).

## License

[MIT](LICENSE). The chart package carries the same text, so a downloaded chart has it too.

## References

- [Shyft with podman](https://gitlab.com/shyft-os/shyft/-/wikis/How-to/Run-a-complete-Shyft-micro-service-system-with-podman): the service layout this chart follows, and sizing
- [Sigma2 NIRD setup](https://doi.org/10.5281/zenodo.17813414) that this chart replaces
