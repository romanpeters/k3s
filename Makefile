.PHONY: validate lint

validate:
	./scripts/validate.sh

lint:
	yamllint -c .yamllint.yaml .
