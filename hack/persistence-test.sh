#!/usr/bin/env bash
# Requirement: the databases survive a pod restart, a chart upgrade, and uninstall + reinstall.
# The data is the demo model plus the results of real model runs, read back from all the stores.
# shellcheck source=hack/lib.sh
source "$(dirname "$0")/lib.sh"
# The namespace enforces the restricted Pod Security Standard: the chart's pods, test pods included, comply.
use_namespace shyft-e2e-persistence restricted

# Upgrade from the chart on origin/master when there is one, else from the working tree itself.
from=$CHART
if git cat-file -e "origin/master:$CHART/Chart.yaml" 2>/dev/null; then
  from=.tmp/chart-from-master
  rm -rf "$from" && mkdir -p "$from"
  git archive origin/master "$CHART" | tar -x -C "$from" --strip-components 2
  log "install the chart from origin/master ($(yq .version "$from/Chart.yaml"))"
else
  log "install the working tree (origin/master has no chart yet, so the upgrade below is from the same chart)"
fi
install "$from" --set tests.modelRun.enabled=true
helm_test
before=$(fingerprint)
echo "$before"

log "restart: delete the core pod"
uid=$(k get pod "$(core_pod)" -o jsonpath='{.metadata.uid}')
k delete pod "$(core_pod)" --wait >/dev/null
k rollout status "statefulset/${RELEASE}-core" --timeout "$HELM_TIMEOUT" >/dev/null
[ "$(k get pod "$(core_pod)" -o jsonpath='{.metadata.uid}')" != "$uid" ] || fail "the core pod was not replaced"
[ "$(fingerprint)" = "$before" ] || fail "data changed across a pod restart"
echo "same data after the restart"

log "the new task has an empty drms registry: the drms must register again, or this run never starts"
model_run
before=$(fingerprint)

log "upgrade to the working tree ($(yq .version "$CHART/Chart.yaml")), with a pod template change that forces a restart"
uid=$(k get pod "$(core_pod)" -o jsonpath='{.metadata.uid}')
install "$CHART" --set tests.modelRun.enabled=true --set-string core.podAnnotations.e2e=upgraded
[ "$(k get pod "$(core_pod)" -o jsonpath='{.metadata.uid}')" != "$uid" ] || fail "the upgrade did not replace the core pod"
[ "$(fingerprint)" = "$before" ] || fail "data changed across a chart upgrade"
echo "same data after the upgrade"
helm_test
before=$(fingerprint)

log "uninstall keeps the claim; reinstall finds the data"
helm uninstall "$RELEASE" --namespace "$NS" --wait >/dev/null
k get persistentvolumeclaim "var-$(core_pod)" >/dev/null || fail "helm uninstall removed the claim"
install "$CHART" --set tests.modelRun.enabled=true
[ "$(fingerprint)" = "$before" ] || fail "data changed across uninstall and reinstall"
echo "same data after the reinstall"

log "PASS persistence"
