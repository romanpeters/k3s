#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

REQUIRED_LABELS = [
    "app.kubernetes.io/name",
    "app.kubernetes.io/instance",
    "app.kubernetes.io/part-of",
    "app.kubernetes.io/managed-by",
    "exposure",
]
VALID_EXPOSURE = {"internal", "public"}

ROOTS = [Path("apps"), Path("clusters")]
SKIP_PREFIXES = [Path("clusters/prod/flux-system"), Path("rtv")]

failures = []

for root in ROOTS:
    if not root.exists():
        continue
    for path in sorted(list(root.rglob("*.yaml")) + list(root.rglob("*.yml"))):
        if path.name == "kustomization.yaml":
            continue
        if any(skip == path or skip in path.parents for skip in SKIP_PREFIXES):
            continue

        try:
            rendered = subprocess.check_output(
                ["yq", "ea", "-o=json", "-I=0", ".", str(path)],
                text=True,
                stderr=subprocess.STDOUT,
            )
        except subprocess.CalledProcessError as exc:
            failures.append(
                f"{path}:0: failed to parse YAML with yq: {exc.output.strip() or exc}"
            )
            continue

        for doc_idx, line in enumerate((l for l in rendered.splitlines() if l.strip()), 1):
            try:
                doc = json.loads(line)
            except json.JSONDecodeError as exc:
                failures.append(
                    f"{path}:{doc_idx}: invalid JSON emitted by yq: {exc.msg}"
                )
                continue

            if not isinstance(doc, dict):
                continue
            if not all(key in doc for key in ("apiVersion", "kind", "metadata")):
                continue

            metadata = doc.get("metadata") or {}
            name = metadata.get("name")
            if not name:
                continue

            labels = metadata.get("labels") or {}
            missing = [label for label in REQUIRED_LABELS if label not in labels]
            if missing:
                failures.append(
                    f"{path}:{doc_idx}: {doc.get('kind')} {name} missing labels: {', '.join(missing)}"
                )
                continue

            exposure = labels.get("exposure")
            if exposure not in VALID_EXPOSURE:
                failures.append(
                    f"{path}:{doc_idx}: {doc.get('kind')} {name} has invalid exposure={exposure!r} (expected internal|public)"
                )

if failures:
    print("\n".join(failures))
    print("\nError: required baseline labels are missing or invalid.", file=sys.stderr)
    sys.exit(1)

print("OK: required baseline labels are present.")
PY
