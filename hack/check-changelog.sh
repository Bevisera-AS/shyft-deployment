#!/usr/bin/env bash
# Every chart's CHANGELOG.md has a section for the version in its Chart.yaml. The release workflow takes the
# release notes from that section, so a missing one would fail only after the merge. List items use `*`, not
# `-`. Called by `mise run lint`.
set -euo pipefail

rc=0
for chart in charts/*/; do
  version=$(yq .version "${chart}Chart.yaml")
  if grep -q "^## \[${version}\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" "${chart}CHANGELOG.md" 2>/dev/null; then
    echo "${chart}CHANGELOG.md: has [${version}]"
  else
    echo "${chart}CHANGELOG.md: no '## [${version}] - YYYY-MM-DD' section" >&2
    rc=1
  fi
  if grep -n '^ *- ' "${chart}CHANGELOG.md" >&2; then
    echo "${chart}CHANGELOG.md: list items above use '-'; write '*'" >&2
    rc=1
  fi
done
exit $rc
