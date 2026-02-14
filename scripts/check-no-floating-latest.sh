#!/usr/bin/env bash
set -euo pipefail

# Disallow floating :latest tags in manifests.
# We allow a digest-pinned variant (e.g. image: repo:latest@sha256:...),
# but plain :latest is blocked.
pattern='^\s*image:\s*["'"'"']?[^"'"'"'"'"'"'\s]+:latest(?!@sha256:[a-f0-9]{64})["'"'"']?\s*$'

if rg -n --pcre2 "$pattern" apps clusters --glob '*.yaml' --glob '*.yml' \
  --glob '!clusters/prod/flux-system/**'; then
  echo
  echo "Error: floating :latest image tags are not allowed."
  echo "Use an explicit version tag (preferred) or digest pin."
  exit 1
fi

echo "OK: no floating :latest image tags found."
