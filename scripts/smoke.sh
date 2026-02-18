#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  smoke.sh [URL...]

Environment:
  URL                     Single default URL when no positional URLs are passed.
                          Default: https://overseerr.romanpeters.nl
  EXPECTED_CODES_OVERRIDE Space-separated HTTP status codes to accept.
                          Default: "200 301 302 303 307 308"
  SKIP_TLS_VERIFY         Set to 1 to use curl --insecure.
  SMOKE_MAX_TIME          curl --max-time (default: 10)
  SMOKE_CONNECT_TIMEOUT   curl --connect-timeout (default: 5)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEFAULT_URL="${URL:-https://overseerr.romanpeters.nl}"
if [[ "$#" -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=("$DEFAULT_URL")
fi

EXPECTED_CODES=(200 301 302 303 307 308)
if [[ -n "${EXPECTED_CODES_OVERRIDE:-}" ]]; then
  read -r -a EXPECTED_CODES <<<"${EXPECTED_CODES_OVERRIDE}"
fi

CURL_FLAGS=(
  --silent
  --show-error
  --output /dev/null
  --write-out "%{http_code}"
  --max-time "${SMOKE_MAX_TIME:-10}"
  --connect-timeout "${SMOKE_CONNECT_TIMEOUT:-5}"
)
if [[ "${SKIP_TLS_VERIFY:-0}" == "1" ]]; then
  CURL_FLAGS+=(--insecure)
fi

failures=0

for url in "${TARGETS[@]}"; do
  code="$(curl "${CURL_FLAGS[@]}" "${url}" || true)"
  matched=0
  for ok in "${EXPECTED_CODES[@]}"; do
    if [[ "${code}" == "${ok}" ]]; then
      matched=1
      break
    fi
  done

  if [[ "${matched}" == "1" ]]; then
    echo "Smoke OK: ${url} -> HTTP ${code}"
  else
    echo "Smoke FAILED: ${url} -> HTTP ${code:-N/A} (expected one of: ${EXPECTED_CODES[*]})" >&2
    failures=$((failures + 1))
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
