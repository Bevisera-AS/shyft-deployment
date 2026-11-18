#!/usr/bin/env bash
# Requirement: nothing is reachable that should not be. Every allowed path is checked next to a refused one,
# because a cluster that does not enforce NetworkPolicy passes any "it connects" test.
# shellcheck source=hack/lib.sh
source "$(dirname "$0")/lib.sh"
use_namespace shyft-e2e-netpol

log "install with clients restricted to pods labelled shyft-client=true"
install "$CHART" -f - <<'YAML'
tests:
  modelRun:
    enabled: true
networkPolicy:
  allowNamespace: false
  clientPeers:
    - podSelector:
        matchLabels:
          shyft-client: "true"
YAML

log "the chart's own tests pass: task reaches the drms, the drms reaches task and dtss"
helm_test

base=$(yq .shyft.basePort "$CHART/values.yaml")
drms_ip=$(k get pods -l app.kubernetes.io/component=drms -o jsonpath='{.items[0].status.podIP}')

expect() {
  local want=$1 what=$2
  shift 2
  if can_connect "$@"; then got=connects; else got=refused; fi
  [ "$got" = "$want" ] || fail "$what: expected '$want', got '$got'"
  echo "ok  $what: $got"
}
expect connects "labelled client -> task" probe-client shyft-client=true "$RELEASE" "$base"
expect connects "labelled client -> dtss" probe-client shyft-client=true "$RELEASE" $((base + 10))
expect refused "unlabelled pod -> task" probe-stranger app=stranger "$RELEASE" "$base"
expect refused "unlabelled pod -> dtss" probe-stranger app=stranger "$RELEASE" $((base + 10))
expect refused "unlabelled pod -> drms" probe-stranger app=stranger "$drms_ip" $((base + 8))
expect refused "labelled client -> drms (only task may)" probe-client shyft-client=true "$drms_ip" $((base + 8))

log "PASS network policy"
