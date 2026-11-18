#!/usr/bin/env bash
# Cluster diagnostics for a failed run. usage: dump.sh <directory>
set -uo pipefail

out=${1:?usage: dump.sh <directory>}
rm -rf "$out" && mkdir -p "$out"

kubectl get nodes -o wide >"$out/nodes.txt" 2>&1
kubectl get pods,services,endpointslices,statefulsets,deployments,persistentvolumeclaims,networkpolicies \
  --all-namespaces -o wide >"$out/resources.txt" 2>&1
kubectl get events --all-namespaces --sort-by=.lastTimestamp >"$out/events.txt" 2>&1
helm list --all-namespaces --all >"$out/helm-releases.txt" 2>&1

# Namespaces with a Shyft release: ct's (shyft-hydrology-<random>) and the hack tests' (shyft-e2e-*).
for ns in $(kubectl get namespaces -o name | cut -d/ -f2 | grep -E '^shyft'); do
  mkdir -p "$out/$ns"
  kubectl --namespace "$ns" describe pods >"$out/$ns/describe-pods.txt" 2>&1
  for pod in $(kubectl --namespace "$ns" get pods -o name | cut -d/ -f2); do
    kubectl --namespace "$ns" logs "$pod" --all-containers --prefix --tail 2000 >"$out/$ns/$pod.log" 2>&1
    kubectl --namespace "$ns" logs "$pod" --all-containers --prefix --tail 2000 --previous \
      >"$out/$ns/$pod.previous.log" 2>/dev/null || rm -f "$out/$ns/$pod.previous.log"
  done
done
echo "diagnostics written to $out"
