#!/usr/bin/env bash
set -euo pipefail

URL="${URL:-https://overseerr.prod.romanpeters.nl}"
EXPECTED_CODES=(200 301 302 303 307 308)
if [[ -n "${EXPECTED_CODES_OVERRIDE:-}" ]]; then
  read -r -a EXPECTED_CODES <<<"$EXPECTED_CODES_OVERRIDE"
fi

CURL_FLAGS=(--silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 --connect-timeout 5)
if [[ "${SKIP_TLS_VERIFY:-0}" == "1" ]]; then
  CURL_FLAGS+=(--insecure)
fi

code=$(curl "${CURL_FLAGS[@]}" "$URL")

for ok in "${EXPECTED_CODES[@]}"; do
  if [[ "$code" == "$ok" ]]; then
    echo "Smoke OK: $URL -> HTTP $code"
    exit 0
  fi
done

echo "Smoke FAILED: $URL -> HTTP $code (expected one of: ${EXPECTED_CODES[*]})" >&2
exit 1
