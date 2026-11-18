#!/usr/bin/env bash
# Put the chart's Shyft image on the kind worker nodes, so that installs do not wait for a 1 GB pull.
# Called by `mise run load-image`.
#
# Each worker pulls the image itself, all at once. That is faster than pulling once and `kind load`-ing it:
# on GitHub the pull took about 30 s and copying it into two workers 75 s. It also keeps a digest pin, which
# `kind load` cannot. `--platform linux/amd64`: the image is amd64 only; on an arm64 machine (Apple Silicon)
# the node runs it under emulation.
set -euo pipefail

cd "$(dirname "$0")/.."
cluster=${KIND_CLUSTER:?KIND_CLUSTER is not set; run this through mise run load-image}
image=$(hack/image.sh)

pids=()
for node in $(kind get nodes --name "$cluster" | grep worker); do
  echo "pulling $image on $node"
  docker exec "$node" ctr --namespace k8s.io images pull --platform linux/amd64 "$image" >/dev/null &
  pids+=("$!")
done
[ "${#pids[@]}" -gt 0 ] || { echo "kind cluster '$cluster' has no worker nodes" >&2; exit 1; }
for pid in "${pids[@]}"; do wait "$pid"; done
