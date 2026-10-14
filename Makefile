ROOT := $(shell pwd)
BACKEND_HCL := $(ROOT)/backend.hcl
BOOTSTRAP_DIR := $(ROOT)/layers/00-bootstrap
AWS_REGION ?= us-east-1

.DEFAULT_GOAL := help
.PHONY: help doctor fmt validate test bootstrap down verify-teardown test-verify-teardown verify-no-keys unlock nuke-bootstrap _write-backend-hcl _layer-state _init-layer _destroy-layer

help:
	@printf '%s\n' \
	  'doctor                 Check local tools, AWS identity, region, and inputs' \
	  'bootstrap              Create and migrate the L0 state backend' \
	  'down                   Safely tear down the ephemeral stack' \
	  'verify-teardown        Check the account for teardown orphans' \
	  'test-verify-teardown   Prove the teardown verifier catches a real orphan' \
	  'verify-no-keys         Check AWS keys and GitHub secret stores' \
	  'fmt                    Format Terraform files' \
	  'validate               Validate every Terraform layer without AWS credentials' \
	  'test                   Run the Bats test suite' \
	  'unlock                 Inspect and recover a stale S3 state lock' \
	  'nuke-bootstrap         DECOMMISSION: destroy the L0 state backend'

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
	shellcheck sh/*.sh

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

down: doctor
	@python3 sh/run-down-with-deadline.py

_layer-state:
	@set -euo pipefail; \
	case "$(LAYER)" in \
	  10-infra) STATE_KEY=infra/terraform.tfstate ;; \
	  20-data) STATE_KEY=data/terraform.tfstate ;; \
	  30-gitops) STATE_KEY=gitops/terraform.tfstate ;; \
	  *) printf 'ERROR: unsupported ephemeral layer: %s\n' "$(LAYER)" >&2; exit 2 ;; \
	esac; \
	if [[ ! -f "$(BACKEND_HCL)" ]]; then printf 'ERROR: generated backend config is missing: %s\n' "$(BACKEND_HCL)" >&2; exit 2; fi; \
	BUCKET="$$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$(BACKEND_HCL)")"; \
	if [[ -z "$$BUCKET" ]]; then printf '%s\n' 'ERROR: generated backend config has no bucket.' >&2; exit 2; fi; \
	OBJECTS_JSON="$$(aws s3api list-objects-v2 --bucket "$$BUCKET" --prefix "$$STATE_KEY" --max-keys 1 --output json)" || { printf 'ERROR: could not determine state for %s; refusing teardown.\n' "$(LAYER)" >&2; exit 2; }; \
	if ! jq -e 'type == "object" and ((has("Contents") and (.Contents | type == "array")) or .KeyCount == 0)' <<< "$$OBJECTS_JSON" >/dev/null; then printf 'ERROR: malformed S3 state listing for %s; refusing teardown.\n' "$(LAYER)" >&2; exit 2; fi; \
	if jq -e --arg key "$$STATE_KEY" 'any(.Contents[]?; .Key == $$key)' <<< "$$OBJECTS_JSON" >/dev/null; then printf '%s\n' present; else printf '%s\n' absent; fi

_init-layer:
	@set -euo pipefail; \
	case "$(LAYER)" in \
	  10-infra) LAYER_DIR=10-infra; STATE_KEY=infra/terraform.tfstate ;; \
	  20-data) LAYER_DIR=20-data; STATE_KEY=data/terraform.tfstate ;; \
	  30-gitops) LAYER_DIR=30-gitops; STATE_KEY=gitops/terraform.tfstate ;; \
	  *) printf 'ERROR: unsupported ephemeral layer: %s\n' "$(LAYER)" >&2; exit 2 ;; \
	esac; \
	terraform -chdir="$(ROOT)/layers/$$LAYER_DIR" init -input=false -reconfigure \
	  -backend-config="$(BACKEND_HCL)" -backend-config="key=$$STATE_KEY"

_destroy-layer:
	@set -euo pipefail; \
	case "$(LAYER)" in \
	  10-infra|20-data|30-gitops) ;; \
	  *) printf 'ERROR: refusing to destroy unsupported layer: %s\n' "$(LAYER)" >&2; exit 2 ;; \
	esac; \
	STATE="$$( $(MAKE) --no-print-directory -s _layer-state LAYER="$(LAYER)" )" || exit $$?; \
	case "$$STATE" in \
	  absent) printf 'Skipping %s: S3 state is confirmed absent.\n' "$(LAYER)" ;; \
	  present) $(MAKE) --no-print-directory -s _init-layer LAYER="$(LAYER)"; \
	    LAYER_DIR="$(LAYER)"; STATE_KEY="$(LAYER)"; \
	    case "$(LAYER)" in 10-infra) LAYER_DIR=10-infra; STATE_KEY=infra/terraform.tfstate ;; \
	      20-data) LAYER_DIR=20-data; STATE_KEY=data/terraform.tfstate ;; \
	      30-gitops) LAYER_DIR=30-gitops; STATE_KEY=gitops/terraform.tfstate ;; esac; \
	    terraform -chdir="$(ROOT)/layers/$$LAYER_DIR" destroy -input=false -auto-approve ;; \
	  *) printf 'ERROR: unexpected state result for %s: %s\n' "$(LAYER)" "$$STATE" >&2; exit 2 ;; \
	esac

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

verify-no-keys: doctor
	@./sh/verify-no-access-keys.sh

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

nuke-bootstrap:
	@set -euo pipefail; \
	ACCOUNT_ID="$$(aws sts get-caller-identity --query Account --output text)"; \
	if [[ ! "$$ACCOUNT_ID" =~ ^[0-9]{12}$$ ]]; then printf 'ERROR: invalid AWS account ID: %s\n' "$$ACCOUNT_ID" >&2; exit 1; fi; \
	EXPECTED="DESTROY BOOTSTRAP $$ACCOUNT_ID"; \
	printf 'DECOMMISSIONING: this destroys the L0 state bucket and bootstrap resources for AWS account %s.\n' "$$ACCOUNT_ID"; \
	printf 'All other Terraform layers must already be destroyed.\nType exactly: %s\n> ' "$$EXPECTED"; \
	IFS= read -r CONFIRM || { printf '%s\n' 'ERROR: confirmation was not provided. Aborted.' >&2; exit 1; }; \
	if [[ "$$CONFIRM" != "$$EXPECTED" ]]; then printf '%s\n' 'ERROR: confirmation mismatch. Aborted.' >&2; exit 1; fi; \
	GUARD_FILE="$(BOOTSTRAP_DIR)/main.tf"; \
	GUARD_BACKUP="$$GUARD_FILE.bak"; \
	if [[ -e "$$GUARD_BACKUP" ]]; then printf 'ERROR: guard backup already exists: %s\n' "$$GUARD_BACKUP" >&2; exit 1; fi; \
	BACKEND_FILE="$(BOOTSTRAP_DIR)/backend.tf"; \
	BACKEND_BACKUP="$$BACKEND_FILE.bak"; \
	if [[ -e "$$BACKEND_BACKUP" ]]; then printf 'ERROR: backend backup already exists: %s\n' "$$BACKEND_BACKUP" >&2; exit 1; fi; \
	GUARD_COUNT="$$(grep -Ec '^[[:space:]]*prevent_destroy = true[[:space:]]*$$' "$$GUARD_FILE" || true)"; \
	if [[ "$$GUARD_COUNT" -ne 1 ]]; then printf 'ERROR: expected exactly one destroy guard in %s.\n' "$$GUARD_FILE" >&2; exit 1; fi; \
	BUCKET="$$(terraform -chdir="$(BOOTSTRAP_DIR)" output -raw state_bucket_name)"; \
	if [[ "$$BUCKET" != "tfstate-$$ACCOUNT_ID-"* ]]; then printf 'ERROR: state bucket %s does not belong to caller account %s.\n' "$$BUCKET" "$$ACCOUNT_ID" >&2; exit 1; fi; \
	for LAYER in infra data gitops; do \
	  STATE_KEY="$$LAYER/terraform.tfstate"; \
	  OBJECTS_JSON="$$(aws s3api list-objects-v2 --bucket "$$BUCKET" --prefix "$$STATE_KEY" --max-keys 1 --output json)"; \
	  if jq -e --arg key "$$STATE_KEY" 'any(.Contents[]?; .Key == $$key)' <<< "$$OBJECTS_JSON" >/dev/null; then \
	    printf 'ERROR: %s still exists in the state bucket. Destroy that layer first.\n' "$$STATE_KEY" >&2; exit 1; \
	  fi; \
	done; \
	printf '%s\n' '==> Migrating bootstrap state to the local backend.'; \
	restore_nuke_files() { \
	  if [[ -f "$$BACKEND_BACKUP" ]]; then mv "$$BACKEND_BACKUP" "$$BACKEND_FILE"; fi; \
	  if [[ -f "$$GUARD_BACKUP" ]]; then mv "$$GUARD_BACKUP" "$$GUARD_FILE"; fi; \
	}; \
	trap 'restore_nuke_files' EXIT; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	mv "$$BACKEND_FILE" "$$BACKEND_BACKUP"; \
	printf 'terraform {\n  backend "local" {}\n}\n' > "$$BACKEND_FILE"; \
	terraform -chdir="$(BOOTSTRAP_DIR)" init -input=false -migrate-state -force-copy; \
	LOCAL_STATE="$$(terraform -chdir="$(BOOTSTRAP_DIR)" state list)"; \
	if [[ -z "$$LOCAL_STATE" ]] || ! grep -Fxq 'aws_s3_bucket.tfstate' <<< "$$LOCAL_STATE"; then printf '%s\n' 'ERROR: migrated local state does not contain aws_s3_bucket.tfstate; refusing to empty the remote state bucket.' >&2; exit 1; fi; \
	sed -i.bak 's/^[[:space:]]*prevent_destroy = true[[:space:]]*$$/    prevent_destroy = false/' "$$GUARD_FILE"; \
	if grep -Eq '^[[:space:]]*prevent_destroy = true[[:space:]]*$$' "$$GUARD_FILE"; then printf '%s\n' 'ERROR: failed to lift the destroy guard.' >&2; exit 1; fi; \
	printf '==> Emptying all versions and delete markers from %s.\n' "$$BUCKET"; \
	"$(ROOT)/sh/empty-versioned-bucket.sh" "$$BUCKET"; \
	printf '%s\n' '==> Destroying 00-bootstrap.'; \
	terraform -chdir="$(BOOTSTRAP_DIR)" destroy -input=false -auto-approve; \
	rm -f "$(BOOTSTRAP_DIR)/terraform.tfstate" "$(BOOTSTRAP_DIR)/terraform.tfstate.backup"; \
	restore_nuke_files; \
	trap - EXIT INT TERM; \
	printf '%s\n' '==> L0 decommissioned. The account no longer has Terraform state.'