#!/usr/bin/env bash
# Not a test of the chart: it characterises upstream. Task never expires a drms registration (AGENTS.md,
# "Shyft invariants"), and the chart README advises against spot nodes because of it. This shows what a dead
# registration costs and that restarting task clears it. If it fails with "task never tried the dead drms",
# upstream has started to expire registrations: revisit the spot advice and docs/shyft-services.md.
#
# Six extra model runs, about two minutes. Run it after a Shyft bump: `mise run upstream-drms`.
# shellcheck source=hack/lib.sh
source "$(dirname "$0")/lib.sh"
use_namespace shyft-e2e-drms-dead

scale 1
wait_registered 1

log "a registration of a dead drms: runs still finish, task keeps retrying it"
dead=10.255.255.1:1
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
task "print('registered dead drms:', register_drms_node(tc, '$dead'))"
start=$SECONDS
for _ in 1 2 3; do model_run; done
tries=$(unreachable_since "$since")
[ "$tries" -gt 0 ] || fail "task never tried the dead drms: has upstream started to expire registrations? Update AGENTS.md"
echo "3 runs finished in $((SECONDS - start)) s; task tried the dead drms $tries times (about 2 s each)"

log "restarting task is what clears it: the live drms registers again within 5 s"
k delete pod "$(core_pod)" --wait >/dev/null
k rollout status "statefulset/${RELEASE}-core" --timeout "$HELM_TIMEOUT" >/dev/null
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for _ in 1 2 3; do model_run; done
[ "$(unreachable_since "$since")" = 0 ] || fail "task still tries the dead drms after a restart"
echo "3 runs, task tried no dead drms"

log "PASS drms dead registration"
