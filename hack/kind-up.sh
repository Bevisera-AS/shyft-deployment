#!/usr/bin/env bash
# `mise run kind-up`: the kind cluster KIND_CLUSTER from KIND_NODE_IMAGE, with Calico, and its kubeconfig in
# .tmp/. A cluster of that name that already exists is reused only if it runs the same Kubernetes version
# (hack/kind.sh checks).
set -euo pipefail

cd "$(dirname "$0")/.."
cluster=${KIND_CLUSTER:?KIND_CLUSTER is not set; run this through mise run kind-up}
image=${KIND_NODE_IMAGE:?KIND_NODE_IMAGE is not set; run this through mise run kind-up}
calico=${CALICO_VERSION:?CALICO_VERSION is not set; run this through mise run kind-up}
export KUBECONFIG="$PWD/.tmp/kubeconfig"
mkdir -p .tmp

if kind get clusters 2>/dev/null | grep -qx "$cluster"; then
  kind export kubeconfig --name "$cluster"
else
  kind create cluster --name "$cluster" --image "$image" --config .github/kind-config.yaml
fi
hack/kind.sh true

# kind's own CNI is disabled in .github/kind-config.yaml, which says why.
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/$calico/manifests/calico.yaml" >/dev/null
kubectl --namespace kube-system rollout status daemonset/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl --namespace kube-system rollout status deployment/coredns --timeout=300s
