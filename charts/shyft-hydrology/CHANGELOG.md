# Changelog

All notable changes to this chart. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The version is the chart's own SemVer. The Shyft line it deploys is `appVersion` in `Chart.yaml`.

## [0.0.5] - 2026-11-19

### Added

* MIT licence: `LICENSE` in the chart package, and the `artifacthub.io/license` annotation.
* `maintainers` in `Chart.yaml`: Bevisera AS.

## [0.0.4] - 2026-11-19

### Changed

* The repository moved from personal `lazyoldbear/shyft-deployment` to `Bevisera-AS/shyft-deployment`, and the Helm repository to
  `https://bevisera-as.github.io/shyft-deployment`: `helm repo add` it again. `home` and `sources` follow.

## [0.0.3] - 2026-11-19

### Nothing

* Just dummy release to test the rig.

## [0.0.2] - 2026-11-19

### Nothing

* Just dummy release to test the rig.

## [0.0.1] - 2026-11-12

### Added

* First release, for Shyft 37.3 (image `fedora44-shyft-app:37.3.0-1.1`).
* `core`: one StatefulSet pod with a container each for task, rmd, parameter, state, dtss, dstm, stm and
  goal_function, on one persistent volume.
* `drms`: a Deployment of compute nodes that register with task themselves. Scale with `drms.replicaCount`.
* Memory requests and limits on every container, test pods included; no CPU limits. A memory request above
  its limit fails at render time, naming the value to set.
* One ClusterIP Service for the core services. NetworkPolicies on by default. No Ingress.
* `service.type: LoadBalancer` only as an internal load balancer, on the cloud named in `service.cloud`.
* `helm test`: a read-only check of every core service, and an opt-in demo model run (`tests.modelRun.enabled`).
* Profiles for Sigma2 NIRD, AWS EKS and Azure AKS in `examples/`.
