ROOT := $(shell pwd)
BACKEND_HCL := $(ROOT)/backend.hcl
BOOTSTRAP_DIR := $(ROOT)/layers/00-bootstrap
AWS_REGION ?= us-east-1

.DEFAULT_GOAL := help
.PHONY: help doctor fmt validate test bootstrap verify-teardown test-verify-teardown unlock _write-backend-hcl

help:
	@printf '%s\n' \
	  'doctor                 Check local tools, AWS identity, region, and inputs' \
	  'bootstrap              Create and migrate the L0 state backend' \
	  'verify-teardown        Check the account for teardown orphans' \
	  'test-verify-teardown   Prove the teardown verifier catches a real orphan' \
	  'fmt                    Format Terraform files' \
	  'validate               Validate every Terraform layer without AWS credentials' \
	  'test                   Run the Bats test suite' \
	  'unlock                 Inspect and recover a stale S3 state lock'

doctor:
	@bash sh/doctor.sh

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
	@set -euo pipefail; \
	ACCOUNT_ID="$$(tr -d '[:space:]' < "$(ROOT)/.aws-account-id")"; \
	REGION="$(AWS_REGION)"; \
	BUCKET="tfstate-$$ACCOUNT_ID-$$REGION"; \
	STATE_KEY="bootstrap/terraform.tfstate"; \
	LOCAL_STATE="$(BOOTSTRAP_DIR)/terraform.tfstate"; \
	BACKEND_FILE="$(BOOTSTRAP_DIR)/backend.tf"; \
	BACKEND_DISABLED="$(BOOTSTRAP_DIR)/.backend.tf.bootstrap-local"; \
	if [[ -e "$$BACKEND_DISABLED" ]]; then \
	  if [[ -e "$$BACKEND_FILE" ]]; then printf '%s\n' 'ERROR: both backend.tf and recovery copy exist; inspect manually.' >&2; exit 1; fi; \
	  mv "$$BACKEND_DISABLED" "$$BACKEND_FILE"; \
	fi; \
	BUCKETS_JSON="$$(aws s3api list-buckets --output json)"; \
	BUCKET_EXISTS=false; \
	if jq -e --arg name "$$BUCKET" 'any(.Buckets[]?; .Name == $$name)' <<< "$$BUCKETS_JSON" >/dev/null; then BUCKET_EXISTS=true; fi; \
	REMOTE_STATE_EXISTS=false; \
	if [[ "$$BUCKET_EXISTS" == true ]]; then \
	  OBJECTS_JSON="$$(aws s3api list-objects-v2 --bucket "$$BUCKET" --prefix "$$STATE_KEY" --output json)"; \
	  if jq -e --arg key "$$STATE_KEY" 'any(.Contents[]?; .Key == $$key)' <<< "$$OBJECTS_JSON" >/dev/null; then REMOTE_STATE_EXISTS=true; fi; \
	fi; \
	if [[ "$$BUCKET_EXISTS" == true && "$$REMOTE_STATE_EXISTS" == true ]]; then \
	  printf '==> 00-bootstrap already migrated to S3; reconfiguring without copying.\n'; \
	  $(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET" REGION="$$REGION"; \
	  terraform -chdir="$(BOOTSTRAP_DIR)" init -input=false -reconfigure \
	    -backend-config="$(BACKEND_HCL)" -backend-config="key=$$STATE_KEY"; \
	elif [[ "$$BUCKET_EXISTS" == true && "$$REMOTE_STATE_EXISTS" == false && -f "$$LOCAL_STATE" ]]; then \
	  printf '==> Bucket exists but remote state does not; migrating the local bootstrap state.\n'; \
	  $(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET" REGION="$$REGION"; \
	  terraform -chdir="$(BOOTSTRAP_DIR)" init -input=false -migrate-state -force-copy \
	    -backend-config="$(BACKEND_HCL)" -backend-config="key=$$STATE_KEY"; \
	elif [[ "$$BUCKET_EXISTS" == true ]]; then \
	  printf '%s\n' 'ERROR: state bucket exists without remote or local bootstrap state; refusing to initialize or overwrite it.' >&2; \
	  exit 1; \
	elif [[ -f "$$LOCAL_STATE" ]]; then \
	  printf '%s\n' 'ERROR: local bootstrap state exists but the account state bucket is absent; inspect state before proceeding.' >&2; \
	  exit 1; \
	else \
	  if [[ ! -f "$$BACKEND_FILE" ]]; then printf '%s\n' 'ERROR: layers/00-bootstrap/backend.tf is missing.' >&2; exit 1; fi; \
	  restore_backend() { if [[ -f "$$BACKEND_DISABLED" ]]; then mv "$$BACKEND_DISABLED" "$$BACKEND_FILE"; fi; }; \
	  trap 'restore_backend' EXIT; \
	  trap 'exit 130' INT; \
	  trap 'exit 143' TERM; \
	  mv "$$BACKEND_FILE" "$$BACKEND_DISABLED"; \
	  printf '%s\n' '==> Applying 00-bootstrap with a local backend.'; \
	  terraform -chdir="$(BOOTSTRAP_DIR)" init -input=false; \
	  terraform -chdir="$(BOOTSTRAP_DIR)" apply -input=false -auto-approve; \
	  restore_backend; \
	  trap - EXIT INT TERM; \
	  BUCKET="$$(terraform -chdir="$(BOOTSTRAP_DIR)" output -raw state_bucket_name)"; \
	  REGION="$$(terraform -chdir="$(BOOTSTRAP_DIR)" output -raw region)"; \
	  $(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET" REGION="$$REGION"; \
	  printf '==> Migrating local state to s3://%s/%s.\n' "$$BUCKET" "$$STATE_KEY"; \
	  terraform -chdir="$(BOOTSTRAP_DIR)" init -input=false -migrate-state -force-copy \
	    -backend-config="$(BACKEND_HCL)" -backend-config="key=$$STATE_KEY"; \
	fi; \
	printf '%s\n' '==> Verifying migrated state and lock lifecycle.'; \
	set +e; terraform -chdir="$(BOOTSTRAP_DIR)" plan -input=false -detailed-exitcode; PLAN_RC=$$?; set -e; \
	if [[ "$$PLAN_RC" -ne 0 ]]; then printf 'ERROR: bootstrap verification plan returned %s.\n' "$$PLAN_RC" >&2; exit 1; fi; \
	aws s3api head-object --bucket "$$BUCKET" --key "$$STATE_KEY" >/dev/null; \
	grep -qF 'use_lockfile = true' "$(BACKEND_HCL)"; \
	printf '%s\n' '==> Bootstrap complete; S3 state and native lockfile are configured.'

_write-backend-hcl:
	@test -n "$(BUCKET)" || { printf '%s\n' 'BUCKET is required.' >&2; exit 2; }
	@test -n "$(REGION)" || { printf '%s\n' 'REGION is required.' >&2; exit 2; }
	@printf '%s\n' \
	  '# GENERATED by make bootstrap. Do not commit or edit.' \
	  'bucket       = "$(BUCKET)"' \
	  'region       = "$(REGION)"' \
	  'encrypt      = true' \
	  'use_lockfile = true' > "$(BACKEND_HCL)"
	@grep -qF 'use_lockfile = true' "$(BACKEND_HCL)"

verify-teardown: doctor
	@set -u; \
	if ./sh/verify-teardown.sh; then RC=0; else RC=$$?; fi; \
	case "$$RC" in \
	  0) printf '%s\n' 'clean' ;; \
	  1) printf '%s\n' 'ORPHANS FOUND - see .teardown-report.json' >&2; exit 1 ;; \
	  2) printf '%s\n' 'VERIFIER ERROR - teardown state UNKNOWN. Do not assume clean.' >&2; exit 2 ;; \
	  *) printf 'unexpected exit %s\n' "$$RC" >&2; exit 2 ;; \
	esac

test-verify-teardown: doctor
	@set +e; ./sh/test-verify-teardown.sh; RC=$$?; set -e; \
	case "$$RC" in \
	  0) printf '%s\n' 'HARD GATE PASSED - verifier returned clean, orphan, and error outcomes.' ;; \
	  10) printf '%s\n' 'HARD GATE BASELINE FAILURE - account was not clean before the test.' >&2; exit 1 ;; \
	  11) printf '%s\n' 'HARD GATE ORPHAN FAILURE - created volume was not proven in the report.' >&2; exit 1 ;; \
	  12) printf '%s\n' 'HARD GATE CLEANUP FAILURE - volume deletion or clean recheck failed.' >&2; exit 1 ;; \
	  13) printf '%s\n' 'HARD GATE ERROR-ARM FAILURE - invalid credentials did not produce the error verdict.' >&2; exit 1 ;; \
	  *) printf 'HARD GATE TOOL FAILURE - test exited %s.\n' "$$RC" >&2; exit 2 ;; \
	esac

unlock: doctor
	@set -euo pipefail; \
	case "$(LAYER)" in \
	  bootstrap|00-bootstrap) LAYER_DIR=00-bootstrap; STATE_KEY=bootstrap/terraform.tfstate ;; \
	  infra|10-infra) LAYER_DIR=10-infra; STATE_KEY=infra/terraform.tfstate ;; \
	  data|20-data) LAYER_DIR=20-data; STATE_KEY=data/terraform.tfstate ;; \
	  gitops|30-gitops) LAYER_DIR=30-gitops; STATE_KEY=gitops/terraform.tfstate ;; \
	  *) printf '%s\n' 'Set LAYER to bootstrap, infra, data, or gitops.' >&2; exit 2 ;; \
	esac; \
	ACCOUNT_ID="$$(tr -d '[:space:]' < "$(ROOT)/.aws-account-id")"; \
	BUCKET="tfstate-$$ACCOUNT_ID-$(AWS_REGION)"; \
	LOCK_KEY="$$STATE_KEY.tflock"; \
	VERSIONS_JSON="$$(aws s3api list-object-versions --bucket "$$BUCKET" --prefix "$$LOCK_KEY" --output json)"; \
	LOCK_VERSION="$$(jq -r --arg key "$$LOCK_KEY" '[.Versions[]? | select(.Key == $$key and .IsLatest)] | first | .VersionId // empty' <<< "$$VERSIONS_JSON")"; \
	if [[ -z "$$LOCK_VERSION" ]]; then printf 'No current lock object for %s.\n' "$$LOCK_KEY"; exit 1; fi; \
	LOCK_FILE="$$(mktemp "$(ROOT)/.lock-info.XXXXXX")"; \
	trap 'rm -f "$$LOCK_FILE"' EXIT; \
	aws s3api get-object --bucket "$$BUCKET" --key "$$LOCK_KEY" --version-id "$$LOCK_VERSION" "$$LOCK_FILE" >/dev/null; \
	LOCK_ID="$$(jq -r '.ID // empty' "$$LOCK_FILE")"; \
	if [[ -z "$$LOCK_ID" ]]; then printf '%s\n' 'ERROR: current lock version has no readable Terraform lock ID; refusing to force-unlock.' >&2; exit 1; fi; \
	printf 'Current lock holder: %s\nCreated: %s\nOperation: %s\n' \
	  "$$(jq -r '.Who // "unknown"' "$$LOCK_FILE")" \
	  "$$(jq -r '.Created // "unknown"' "$$LOCK_FILE")" \
	  "$$(jq -r '.Operation // "unknown"' "$$LOCK_FILE")"; \
	$(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET" REGION="$(AWS_REGION)"; \
	terraform -chdir="$(ROOT)/layers/$$LAYER_DIR" init -input=false -reconfigure \
	  -backend-config="$(BACKEND_HCL)" -backend-config="key=$$STATE_KEY"; \
	terraform -chdir="$(ROOT)/layers/$$LAYER_DIR" force-unlock "$$LOCK_ID"