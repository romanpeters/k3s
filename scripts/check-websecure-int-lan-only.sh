#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

ROOTS = [Path("apps"), Path("clusters")]
SKIP_PREFIXES = [Path("clusters/prod/flux-system"), Path("rtv")]

TRAEFIK_CFG = Path("apps/system/traefik-helmchartconfig.yaml")
LAN_MW_FILE = Path("apps/infrastructure/lan-allow-10-8-middleware.yaml")
EXPECTED_MW_REF = "infrastructure-lan-allow-10-8@kubernetescrd"
EXPECTED_CIDR = "10.0.0.0/8"

errors = []
int_routes = []


def iter_docs(path: Path):
    rendered = subprocess.check_output(
        ["yq", "ea", "-o=json", "-I=0", ".", str(path)],
        text=True,
        stderr=subprocess.STDOUT,
    )
    for doc_idx, line in enumerate((l for l in rendered.splitlines() if l.strip()), 1):
        doc = json.loads(line)
        if isinstance(doc, dict):
            yield doc_idx, doc


for root in ROOTS:
    if not root.exists():
        continue
    for path in sorted(list(root.rglob("*.yaml")) + list(root.rglob("*.yml"))):
        if path.name == "kustomization.yaml":
            continue
        if any(skip == path or skip in path.parents for skip in SKIP_PREFIXES):
            continue

        try:
            docs = list(iter_docs(path))
        except Exception as exc:
            errors.append(f"{path}:0: failed to parse YAML: {exc}")
            continue

        for doc_idx, doc in docs:
            kind = doc.get("kind")
            meta = doc.get("metadata") or {}
            name = meta.get("name", "<noname>")
            ns = meta.get("namespace", "<cluster>")

            if kind == "Ingress":
                annotations = meta.get("annotations") or {}
                entrypoints = annotations.get(
                    "traefik.ingress.kubernetes.io/router.entrypoints", ""
                )
                eps = {ep.strip() for ep in entrypoints.split(",") if ep.strip()}
                if "websecure-int" in eps:
                    int_routes.append((str(path), doc_idx, kind, ns, name))
            elif kind in {"IngressRoute", "IngressRouteTCP"}:
                eps = set(((doc.get("spec") or {}).get("entryPoints") or []))
                if "websecure-int" in eps:
                    int_routes.append((str(path), doc_idx, kind, ns, name))

if not int_routes:
    print("OK: no websecure-int routes found.")
    sys.exit(0)

if not TRAEFIK_CFG.exists():
    errors.append(f"{TRAEFIK_CFG}: missing Traefik HelmChartConfig")
else:
    try:
        values_content = subprocess.check_output(
            ["yq", "e", ".spec.valuesContent // \"\"", str(TRAEFIK_CFG)],
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        values_content = ""
        errors.append(f"{TRAEFIK_CFG}: failed to read valuesContent: {exc}")
    needle = f"--entryPoints.websecure-int.http.middlewares={EXPECTED_MW_REF}"
    if needle not in values_content:
        errors.append(
            f"{TRAEFIK_CFG}: missing required Traefik arg '{needle}' for LAN-only enforcement."
        )

if not LAN_MW_FILE.exists():
    errors.append(f"{LAN_MW_FILE}: missing LAN allow middleware manifest")
else:
    try:
        cidrs = subprocess.check_output(
            ["yq", "e", ".spec.ipAllowList.sourceRange[]", str(LAN_MW_FILE)],
            text=True,
        ).splitlines()
    except subprocess.CalledProcessError:
        cidrs = []
        errors.append(f"{LAN_MW_FILE}: failed to read ipAllowList.sourceRange")
    if EXPECTED_CIDR not in {c.strip() for c in cidrs if c.strip()}:
        errors.append(
            f"{LAN_MW_FILE}: expected sourceRange to include {EXPECTED_CIDR}"
        )

if errors:
    print("\n".join(errors))
    print(
        f"\nError: found {len(int_routes)} websecure-int route(s) but LAN-only safeguards are not correctly configured.",
        file=sys.stderr,
    )
    sys.exit(1)

print(
    f"OK: {len(int_routes)} websecure-int route(s) protected by {EXPECTED_MW_REF} with {EXPECTED_CIDR}."
)
PY
