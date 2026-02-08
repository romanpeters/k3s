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
