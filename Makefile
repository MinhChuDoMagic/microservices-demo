ROOT := $(shell pwd)
BACKEND_HCL := $(ROOT)/backend.hcl

.DEFAULT_GOAL := help
.PHONY: help doctor fmt validate test bootstrap verify-teardown test-verify-teardown

help:
	@printf '%s\n' \
	  'doctor                 Check local tools, AWS identity, region, and inputs' \
	  'bootstrap              Create and migrate the L0 state backend' \
	  'verify-teardown        Check the account for teardown orphans' \
	  'test-verify-teardown   Prove the teardown verifier catches a real orphan' \
	  'fmt                    Format Terraform files' \
	  'validate               Validate every Terraform layer without AWS credentials' \
	  'test                   Run the Bats test suite'

doctor:
	@bash scripts/doctor.sh

fmt:
	@terraform fmt -recursive

validate:
	@set -euo pipefail; \
	for d in layers/*/; do \
	  printf '==> validate %s\n' "$$d"; \
	  terraform -chdir="$$d" init -backend=false -input=false >/dev/null; \
	  terraform -chdir="$$d" validate; \
	done; \
	terraform fmt -recursive -check -diff; \
	shellcheck scripts/*.sh

test:
	@bats tests/

bootstrap: doctor
	@printf '%s\n' 'bootstrap recipe is authored by plan 01-04'; exit 1

verify-teardown: doctor
	@printf '%s\n' 'verify-teardown recipe is authored by plan 01-04'; exit 1

test-verify-teardown: doctor
	@printf '%s\n' 'test-verify-teardown recipe is authored by plan 01-09'; exit 1