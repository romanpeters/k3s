#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import re
import sys
from pathlib import Path

roots = [Path("apps"), Path("clusters")]
skip_prefix = Path("clusters/prod/flux-system")
image_line = re.compile(r'^\s*image:\s*(["\']?)([^"\']+)\1\s*$')
valid_ref = re.compile(r'^[^@\s]+:[^@\s]+@sha256:[a-f0-9]{64}$')

failures = []
for root in roots:
    if not root.exists():
        continue
    for path in list(root.rglob("*.yaml")) + list(root.rglob("*.yml")):
        if skip_prefix in path.parents or path == skip_prefix:
            continue
        for idx, line in enumerate(path.read_text().splitlines(), start=1):
            m = image_line.match(line)
            if not m:
                continue
            ref = m.group(2).strip()
            if not valid_ref.match(ref):
                failures.append((str(path), idx, line.strip()))

if failures:
    for path, line, text in failures:
        print(f"{path}:{line}: {text}")
    print("\nError: image references must use repo:tag@sha256:digest syntax.", file=sys.stderr)
    sys.exit(1)

print("OK: all image references are immutable (tag + digest).")
PY
