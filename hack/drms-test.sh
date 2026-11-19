#!/usr/bin/env bash
# drms scales by replicas: every replica registers with task and takes work, and a replica that is scaled
# away unregisters. What a dead registration costs is upstream behaviour, not the chart's: that is
# hack/drms-dead-registration.sh, outside `mise run e2e`.
# shellcheck source=hack/lib.sh
source "$(dirname "$0")/lib.sh"
use_namespace shyft-e2e-drms

log "2 drms"
scale 2
wait_registered 2
[ "$(k get pods -l app.kubernetes.io/component=drms -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" = 2 ] ||
  fail "the 2 drms are on the same node: the spread constraint did nothing"

log "scale up to 3: task hands work to each of them in turn"
scale 3
wait_registered 3
for _ in 1 2 3; do model_run; done
for pod in $(drms_pods); do
  k logs "$pod" | grep -q 'Extract attr' || fail "$pod took no run: it is not in task's queue, or cannot reach dtss"
done
echo "all 3 drms took a run and stored statistics in dtss"

log "scale down to 1: the two that leave unregister, so task never tries them again"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
scale 1
wait_registered 1
for _ in 1 2 3; do model_run; done
[ "$(unreachable_since "$since")" = 0 ] || fail "task still tries a drms that was scaled away"
echo "3 runs on the remaining drms, task tried no dead one"

log "PASS drms"
