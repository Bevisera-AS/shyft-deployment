#!/usr/bin/env bash
# Print the image reference the chart deploys with its default values, exactly as the pods get it:
# repository:tag, or repository:tag@digest when image.digest is set. `mise run load-image` and the probe pods of
# hack/*-test.sh use this, so they can never run another image than the chart does.
set -euo pipefail

cd "$(dirname "$0")/.."
helm template image "${CHART:-charts/shyft-hydrology}" --show-only templates/core-statefulset.yaml "$@" |
  yq '.spec.template.spec.containers[0].image'
