#!/usr/bin/env bash
# Shared by hack/*-test.sh: source it. Every test installs the chart into its own namespace on the kind
# cluster that `mise run kind-up` created, and removes the namespace when it passes.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART=${CHART:-charts/shyft-hydrology}
RELEASE=shyft-hydrology
HELM_TIMEOUT=${HELM_TIMEOUT:-600s}
cd "$ROOT"

log() { printf '\n--- %s\n' "$*"; }
fail() {
  printf '\nFAIL: %s\n' "$*" >&2
  exit 1
}

# The repo's kind cluster and nothing else: its kubeconfig, and hack/kind.sh's checks on the context and version.
export KUBECONFIG="$ROOT/.tmp/kubeconfig"
"$ROOT/hack/kind.sh" true

# use_namespace <name> [pod security level]: start from an empty namespace. It is deleted when the test
# passes and kept when it fails, so `mise run dump` can collect it. With a level (e.g. restricted), Kubernetes
# rejects every pod in it that does not meet that Pod Security Standard.
use_namespace() {
  NS=$1
  kubectl delete namespace "$NS" --ignore-not-found --wait >/dev/null
  kubectl create namespace "$NS" >/dev/null
  if [ -n "${2:-}" ]; then
    kubectl label namespace "$NS" "pod-security.kubernetes.io/enforce=$2" >/dev/null
  fi
  trap cleanup EXIT
}
cleanup() {
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    kubectl delete namespace "$NS" --wait=false >/dev/null
  else
    echo "namespace $NS kept for diagnostics"
  fi
}

k() { kubectl --namespace "$NS" "$@"; }

# install [chart dir] [helm args…]: install or upgrade the release and wait until it is ready.
install() {
  local chart=$1
  shift
  helm upgrade --install "$RELEASE" "$chart" --namespace "$NS" --wait --timeout "$HELM_TIMEOUT" "$@" >/dev/null
}

# The chart's own tests. The model-run test seeds the demo model and adds one case per call.
helm_test() { helm test "$RELEASE" --namespace "$NS" --timeout "$HELM_TIMEOUT" "$@" >/dev/null; }
model_run() { helm_test --filter "name=${RELEASE}-test-model-run"; }

core_pod() { echo "${RELEASE}-core-0"; }

# What the databases hold, as one line of JSON. Runs inside the core pod, against localhost.
fingerprint() { k exec -i "$(core_pod)" -c task -- python3 - <"$ROOT/hack/fingerprint.py"; }

# image: the Shyft image the chart deploys. Probe pods use it too: it is already on the nodes and has Python.
image() { "$ROOT/hack/image.sh"; }

# can_connect <pod name> <labels> <host> <port>: run a throwaway pod that opens one TCP connection.
can_connect() {
  local name=$1 labels=$2 host=$3 port=$4
  k delete pod "$name" --ignore-not-found --wait >/dev/null
  k run "$name" --image "$(image)" --image-pull-policy IfNotPresent --restart Never --labels "$labels" \
    --command -- python3 -c "
import socket, sys
s = socket.socket()
s.settimeout(5)
try:
    s.connect(('$host', $port))
except OSError as e:
    print('refused:', e)
    sys.exit(1)
print('connected')
" >/dev/null
  local phase deadline=$((SECONDS + 90))
  while :; do
    phase=$(k get pod "$name" -o jsonpath='{.status.phase}')
    case "$phase" in Succeeded | Failed) break ;; esac
    [ $SECONDS -lt $deadline ] || break
    sleep 1
  done
  k delete pod "$name" --wait=false >/dev/null
  case "$phase" in
    Succeeded) return 0 ;;
    Failed) return 1 ;;
    *) fail "probe pod $name ended in phase '$phase'" ;;
  esac
}

# --- drms helpers, for drms-test.sh and drms-dead-registration.sh

drms_pods() { k get pods -l app.kubernetes.io/component=drms -o name --field-selector=status.phase=Running; }

# Task has no API that lists its drms. A drms says so in its log, and task says so when one is unreachable.
wait_registered() {
  local want=$1 pod deadline=$((SECONDS + 120))
  while :; do
    local ok=0 n=0
    for pod in $(drms_pods); do
      n=$((n + 1))
      if k logs "$pod" | grep -q 'Successfully registered'; then ok=$((ok + 1)); fi
    done
    if [ "$n" = "$want" ] && [ "$ok" = "$want" ]; then return 0; fi
    [ $SECONDS -lt $deadline ] || fail "expected $want registered drms, saw $ok of $n"
    sleep 2
  done
}
unreachable_since() { k logs "$(core_pod)" -c task --since-time "$1" | grep -c 'Failed to connect to drms client' || true; }
scale() {
  install "$CHART" --set tests.modelRun.enabled=true --set drms.replicaCount="$1"
  k rollout status "deployment/${RELEASE}-drms" --timeout "$HELM_TIMEOUT" >/dev/null
}
# task <python>: run a few lines against task from inside the core pod.
task() {
  k exec -i "$(core_pod)" -c task -- python3 -c "
from hydrology.service.config import HydroServiceConfig
from hydrology.task.fx import register_drms_node, unregister_drms_node
tc = HydroServiceConfig().task.client()
$1"
}
