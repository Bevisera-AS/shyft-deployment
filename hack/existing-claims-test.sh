#!/usr/bin/env bash
# The Sigma2 shape: the databases and the input data live on claims that exist before the chart is installed.
# The chart must use them, create no claim of its own, and leave them alone on uninstall.
# shellcheck source=hack/lib.sh
source "$(dirname "$0")/lib.sh"
use_namespace shyft-e2e-claims restricted

log "create the two claims"
for claim in shyft-var shyft-data; do
  k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $claim
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 3Gi
YAML
done

args=(
  --set tests.modelRun.enabled=true
  --set persistence.var.existingClaim=shyft-var
  --set persistence.data.enabled=true
  --set persistence.data.existingClaim=shyft-data
)
log "install on the existing claims"
install "$CHART" "${args[@]}"
helm_test
[ "$(k get persistentvolumeclaim -o name | wc -l | tr -d ' ')" = 2 ] || fail "the chart created a claim of its own"

log "the input data volume is mounted in every core container, and writable"
k exec "$(core_pod)" -c dtss -- sh -c 'echo forcing-data > /shyft-data/marker'
[ "$(k exec "$(core_pod)" -c task -- cat /shyft-data/marker)" = forcing-data ] || fail "/shyft-data is not shared"
k exec "$(core_pod)" -c task -- test -d /shyft-var/dtss/db || fail "the databases are not on the var claim"
before=$(fingerprint)
echo "$before"

log "uninstall, reinstall on the same claims"
helm uninstall "$RELEASE" --namespace "$NS" --wait >/dev/null
[ "$(k get persistentvolumeclaim -o name | wc -l | tr -d ' ')" = 2 ] || fail "helm uninstall removed a claim"
install "$CHART" "${args[@]}"
[ "$(fingerprint)" = "$before" ] || fail "data changed across uninstall and reinstall"
[ "$(k exec "$(core_pod)" -c task -- cat /shyft-data/marker)" = forcing-data ] || fail "input data lost"
echo "same data after the reinstall"

log "PASS existing claims"
