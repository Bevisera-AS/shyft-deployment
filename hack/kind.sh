#!/usr/bin/env bash
# hack/kind.sh [--context-only] <command…>: run a command against the repo's kind cluster, and nothing else.
# Every mise task that touches a cluster goes through here, and hack/lib.sh calls it too.
#
# - KUBECONFIG is .tmp/kubeconfig, written by `mise run kind-up`, never yours. Only these commands get it: an
#   interactive shell in the repository keeps your own.
# - The context must be exactly kind-$KIND_CLUSTER, so a test cannot run on another kind cluster than the one
#   load-image filled.
# - The cluster must run the Kubernetes version of KIND_NODE_IMAGE, so changing the image cannot give a green
#   run on the cluster that is already there. A version that cannot be read is a refusal too.
#   --context-only skips this check, for `mise run dump` alone: diagnostics must still work when the API server
#   does not answer.
set -euo pipefail

context_only=false
if [ "${1:-}" = --context-only ]; then
  context_only=true
  shift
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cluster=${KIND_CLUSTER:?KIND_CLUSTER is not set; run this through a mise task}
image=${KIND_NODE_IMAGE:?KIND_NODE_IMAGE is not set; run this through a mise task}
export KUBECONFIG="$root/.tmp/kubeconfig"

refuse() {
  echo "Refusing: $*" >&2
  exit 1
}

ctx=$(kubectl config current-context 2>/dev/null || true)
[ "$ctx" = "kind-$cluster" ] ||
  refuse "kubectl context is '$ctx', not 'kind-$cluster'. Run 'mise run kind-up'."

if [ "$context_only" = false ]; then
  # kindest/node:v1.37.0@sha256:… -> v1.37.0
  want=${image%%@*}
  want=${want##*:}
  have=$(kubectl get --raw /version 2>/dev/null | yq -p json '.gitVersion') || have=
  [ -n "$have" ] && [ "$have" != null ] ||
    refuse "cannot read the Kubernetes version of kind cluster '$cluster'. Is it running? 'mise run kind-up'."
  [ "$have" = "$want" ] ||
    refuse "kind cluster '$cluster' runs Kubernetes $have, but KIND_NODE_IMAGE is $want." \
      "Run 'mise run kind-down' first, or set KIND_CLUSTER to another name."
fi

exec "$@"
