# k3s-cluster

## Development workflow

### Bootstrap

Install the required tools locally:

```bash
./scripts/bootstrap-dev.sh
```

### Pre-commit

```bash
pre-commit install
pre-commit run --all-files
```

### Validate manifests

```bash
make validate
```

### Local smoke test

```bash
make smoke
```

Override defaults if needed:

```bash
URL=https://overseerr.prod.romanpeters.nl EXPECTED_CODES_OVERRIDE="200 302" ./scripts/smoke.sh
```
