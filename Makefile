.PHONY: validate lint smoke

validate:
	./scripts/validate.sh

lint:
	yamllint -c .yamllint.yaml .

smoke:
	./scripts/smoke.sh
