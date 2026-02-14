#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

PUB_ENTRYPOINTS = {"websecure-pub", "websecure-ext"}

ROOTS = [Path("apps"), Path("clusters")]
SKIP_PREFIXES = [Path("clusters/prod/flux-system"), Path("rtv")]


def load_default_namespaces():
    defaults = {}
    for kustomization in Path("apps").glob("*/kustomization.yaml"):
        try:
            ns = subprocess.check_output(
                ["yq", "e", ".namespace // \"\"", str(kustomization)],
                text=True,
            ).strip()
        except subprocess.CalledProcessError:
            continue
        if ns:
            defaults[kustomization.parent.resolve()] = ns
    return defaults


def inferred_namespace(path: Path, metadata: dict, defaults: dict) -> str:
    explicit = metadata.get("namespace")
    if explicit:
        return explicit
    resolved = path.resolve()
    for base, namespace in defaults.items():
        try:
            resolved.relative_to(base)
            return namespace
        except ValueError:
            continue
    return "default"


def parse_documents(path: Path):
    rendered = subprocess.check_output(
        ["yq", "ea", "-o=json", "-I=0", ".", str(path)],
        text=True,
        stderr=subprocess.STDOUT,
    )
    docs = []
    for idx, line in enumerate((line for line in rendered.splitlines() if line.strip()), 1):
        doc = json.loads(line)
        if isinstance(doc, dict) and all(key in doc for key in ("apiVersion", "kind", "metadata")):
            docs.append((idx, doc))
    return docs


def get_pod_labels(doc: dict):
    kind = doc.get("kind")
    spec = doc.get("spec") or {}
    if kind == "CronJob":
        template = (
            (((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") or {})
        )
    elif kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}:
        template = spec.get("template") or {}
    else:
        return None
    return ((template.get("metadata") or {}).get("labels") or {}) or None


def ingress_backends(doc: dict):
    spec = doc.get("spec") or {}
    backends = []
    for rule in spec.get("rules") or []:
        http = rule.get("http") or {}
        for path_item in http.get("paths") or []:
            service = ((path_item.get("backend") or {}).get("service") or {})
            name = service.get("name")
            if name:
                backends.append(name)
    default_backend = spec.get("defaultBackend") or {}
    service = default_backend.get("service") or {}
    if service.get("name"):
        backends.append(service["name"])
    return backends


def ingressroute_backends(doc: dict):
    spec = doc.get("spec") or {}
    backends = []
    for route in spec.get("routes") or []:
        for service in route.get("services") or []:
            name = service.get("name")
            namespace = service.get("namespace")
            if name:
                backends.append((name, namespace))
    return backends


defaults = load_default_namespaces()
services = {}
workloads = []
routes = []
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
            docs = parse_documents(path)
        except Exception as exc:
            failures.append(f"{path}:0: failed to parse YAML: {exc}")
            continue

        for doc_idx, doc in docs:
            metadata = doc.get("metadata") or {}
            labels = metadata.get("labels") or {}
            kind = doc.get("kind")
            name = metadata.get("name")
            if not name:
                continue
            namespace = inferred_namespace(path, metadata, defaults)
            exposure = labels.get("exposure")

            if kind == "Service":
                selector = (doc.get("spec") or {}).get("selector") or {}
                services[(namespace, name)] = {
                    "selector": selector,
                    "file": str(path),
                    "doc_idx": doc_idx,
                }
                continue

            pod_labels = get_pod_labels(doc)
            if pod_labels is not None:
                workloads.append(
                    {
                        "namespace": namespace,
                        "kind": kind,
                        "name": name,
                        "exposure": exposure,
                        "pod_labels": pod_labels,
                        "file": str(path),
                        "doc_idx": doc_idx,
                    }
                )
                continue

            if kind == "Ingress":
                annotations = metadata.get("annotations") or {}
                entrypoints = annotations.get(
                    "traefik.ingress.kubernetes.io/router.entrypoints", ""
                )
                entrypoint_set = {
                    ep.strip() for ep in entrypoints.split(",") if ep.strip()
                }
                reasons = []
                if entrypoint_set & PUB_ENTRYPOINTS:
                    reasons.append(
                        f"entrypoints={','.join(sorted(entrypoint_set & PUB_ENTRYPOINTS))}"
                    )
                if labels.get("exposure") == "public":
                    reasons.append("label exposure=public")
                if (annotations.get("external-dns") or "").strip().lower() == "external":
                    reasons.append("external-dns=external")

                if exposure == "internal" and reasons:
                    failures.append(
                        f"{path}:{doc_idx}: Ingress {namespace}/{name} is exposure=internal but looks public ({'; '.join(reasons)})."
                    )

                is_public = bool(reasons)
                for backend in ingress_backends(doc):
                    routes.append(
                        {
                            "namespace": namespace,
                            "service": backend,
                            "is_public": is_public,
                            "route_kind": kind,
                            "route_name": name,
                            "file": str(path),
                            "doc_idx": doc_idx,
                            "reasons": reasons,
                        }
                    )
                continue

            if kind in {"IngressRoute", "IngressRouteTCP"}:
                entrypoints = set(((doc.get("spec") or {}).get("entryPoints") or []))
                reasons = []
                if entrypoints & PUB_ENTRYPOINTS:
                    reasons.append(
                        f"entryPoints={','.join(sorted(entrypoints & PUB_ENTRYPOINTS))}"
                    )
                if labels.get("exposure") == "public":
                    reasons.append("label exposure=public")
                if exposure == "internal" and reasons:
                    failures.append(
                        f"{path}:{doc_idx}: {kind} {namespace}/{name} is exposure=internal but looks public ({'; '.join(reasons)})."
                    )
                is_public = bool(reasons)
                for backend_name, backend_ns in ingressroute_backends(doc):
                    routes.append(
                        {
                            "namespace": backend_ns or namespace,
                            "service": backend_name,
                            "is_public": is_public,
                            "route_kind": kind,
                            "route_name": name,
                            "file": str(path),
                            "doc_idx": doc_idx,
                            "reasons": reasons,
                        }
                    )


for route in routes:
    if not route["is_public"]:
        continue
    service = services.get((route["namespace"], route["service"]))
    if not service:
        continue
    selector = service["selector"]
    if not selector:
        continue

    def matches(workload):
        if workload["namespace"] != route["namespace"]:
            return False
        labels = workload["pod_labels"] or {}
        return all(labels.get(k) == v for k, v in selector.items())

    matching = [w for w in workloads if matches(w)]
    for workload in matching:
        if workload.get("exposure") == "internal":
            failures.append(
                f"{route['file']}:{route['doc_idx']}: {route['route_kind']} {route['namespace']}/{route['route_name']} publishes Service {route['service']} publicly ({'; '.join(route['reasons'])}), "
                f"but it selects {workload['kind']} {route['namespace']}/{workload['name']} with exposure=internal ({workload['file']}:{workload['doc_idx']})."
            )

if failures:
    print("\n".join(sorted(set(failures))))
    print("\nError: internal resources/workloads appear publicly exposed.", file=sys.stderr)
    sys.exit(1)

print("OK: no public exposure detected for exposure=internal resources/workloads.")
PY
