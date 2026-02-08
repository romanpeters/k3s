#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    return 1
  fi
}

require yamllint
require kustomize
require kubeconform

# Lint YAML (including Kustomize and Flux manifests)
yamllint -c "$ROOT_DIR/.yamllint.yaml" "$ROOT_DIR"

# Render and validate all cluster manifests
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build "$ROOT_DIR/clusters/prod" > "$rendered"

kubeconform \
  -strict \
  -ignore-missing-schemas \
  -summary \
  "$rendered"
