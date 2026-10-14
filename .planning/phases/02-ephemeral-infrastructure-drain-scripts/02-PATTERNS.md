# Phase 2: Ephemeral Infrastructure & Drain Scripts - Pattern Map

**Mapped:** 2026-10-14  
**Files analyzed:** 17 implementation/test/documentation targets (including grouped fixture files)  
**Analogs found:** 13 / 17; four have no close infrastructure implementation analog

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Makefile` | config / lifecycle entry point | request-response orchestration | `Makefile` (`bootstrap`, `verify-teardown`, `nuke-bootstrap`) | exact |
| `layers/10-infra/versions.tf` | config / provider | Terraform configuration | `layers/10-infra/versions.tf` | exact for pins/tags; module graph has no analog |
| `layers/10-infra/variables.tf` | config / inputs | Terraform configuration | `layers/10-infra/variables.tf` | exact for existing defaults |
| `layers/10-infra/README.md` | documentation | operator reference | `layers/10-infra/README.md` | exact for layer boundary/state key |
| `layers/10-infra/vpc.tf` | infrastructure module | resource graph / networking | `layers/10-infra/versions.tf`; `docs/CONVENTIONS.md` | no resource-graph analog |
| `layers/10-infra/nat.tf` | infrastructure module | resource graph / egress | `layers/10-infra/versions.tf`; `docs/CONVENTIONS.md` | no resource-graph analog |
| `layers/10-infra/eks.tf` | infrastructure module | resource graph / EKS | `layers/10-infra/versions.tf`; `docs/CONVENTIONS.md` | no resource-graph analog |
| `layers/10-infra/karpenter.tf` | infrastructure module | resource graph / IAM, queue, events | `layers/10-infra/versions.tf`; `docs/CONVENTIONS.md` | no resource-graph analog |
| `sh/drain-ingress.sh` | lifecycle script | Kubernetes request + ELBv2 polling | `sh/verify-teardown.sh` | role-match; no drain analog |
| `sh/drain-nodes.sh` | lifecycle script | Kubernetes request + EC2 polling | `sh/verify-teardown.sh` | role-match; no drain analog |
| `sh/drain-pvcs.sh` | lifecycle script | Kubernetes request + EBS polling | `sh/verify-teardown.sh` | role-match; no drain analog |
| `sh/nuke-project.sh` (candidate name) | recovery utility | preview + scoped deletion | `Makefile` `nuke-bootstrap` target | partial; Cloud Nuke behavior is new |
| `tests/phase2_lifecycle.bats` | test | request-response / orchestration | `tests/verify_teardown_exit_codes.bats` | role-match |
| `tests/static_contracts.bats` | test | source-contract checks | `tests/static_contracts.bats` | exact |
| AWS EKS/ELBv2/EC2/EBS lifecycle fixtures under `tests/fixtures/aws/` | test data | API-state transitions | `tests/fixtures/aws/eks-describe-cluster-eu-west-1.json`; `tests/helpers/stub-aws.bash` | role-match |
| `COSTS.md` | documentation / measurement ledger | batch measurement | existing `COSTS.md` cost tables and verification notes | exact |
| `VERSIONS.md` | config documentation / version ledger | version registry | existing `VERSIONS.md` | exact |

The file count above excludes unchanged shared helpers and source analogs. The recovery wrapper is a likely implementation file inferred from D-07/D-08; the research does not lock its filename or any Cloud Nuke config filename. Keep the type allowlist explicit, exclude `vpc`, and make this command independent of `make down`.

## Pattern Assignments

### `Makefile` (lifecycle orchestration, request-response)

**Analog:** `Makefile`

The existing lifecycle entry points are Make targets; preserve the generated root backend contract and use the established layer state keys. The validation/test target pattern is explicit and fail-fast:

**Validation and test pattern** (`Makefile`, lines 28-40):

```make
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
```

**Layer selection / Make-owned Terraform init** (`Makefile`, lines 139-165):

```make
case "$(LAYER)" in \
  bootstrap|00-bootstrap) LAYER_DIR=00-bootstrap; STATE_KEY=bootstrap/terraform.tfstate ;; \
  infra|10-infra) LAYER_DIR=10-infra; STATE_KEY=infra/terraform.tfstate ;; \
  data|20-data) LAYER_DIR=20-data; STATE_KEY=data/terraform.tfstate ;; \
  gitops|30-gitops) LAYER_DIR=30-gitops; STATE_KEY=gitops/terraform.tfstate ;; \
  *) printf '%s\n' 'Set LAYER to bootstrap, infra, data, or gitops.' >&2; exit 2 ;; \
esac
```

Extend the target's phony/help declarations, keep Terraform initialization behind Make, preserve command failure output, and make normal teardown sequence explicit. Do not route daily `up`/`down` through `00-bootstrap`. `verify-teardown` in this file is the contract for mapping verifier exits: `0` clean, `1` orphan findings, `2` verifier/credential error.

### `layers/10-infra/{versions.tf,variables.tf,README.md}` (configuration and documentation)

**Analogs:** the existing files at the same paths. They are tracked stubs and directly own the new layer's existing defaults and provider contract.

**Provider and tags pattern** (`layers/10-infra/versions.tf`, lines 1-21):

```hcl
terraform {
  required_version = "= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.66.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Layer       = "10-infra"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
```

Add exact provider constraints required by EKS v21 and mirror exact pins to `VERSIONS.md`. Keep default tags centralized; don't duplicate them in resource `tags`. L1 must remain AWS-only: no Terraform `kubernetes` or `helm` provider. Use the existing region/project/environment inputs in `variables.tf` (lines 1-17), and retain the README's `infra/terraform.tfstate` key.

**Shared Terraform convention** (`docs/CONVENTIONS.md`, lines 5-20):

- Explicit CloudWatch log groups use `retention_in_days = 1`.
- Provider default tags are `Project`, `Layer`, `ManagedBy`, `Environment`.
- Terraform, providers, and modules have exact pins mirrored in `VERSIONS.md`.
- Terraform initialization runs only through Make because backend configuration is generated at the repository root.

### `layers/10-infra/{vpc.tf,nat.tf,eks.tf,karpenter.tf}` (infrastructure modules)

**No close resource implementation analog found.** `layers/00-bootstrap` has Terraform resources, but not VPC/EKS/NAT/Karpenter patterns; copying those resources would not be meaningful. Use the shared provider/tag/backend convention above and the module/version/API contracts in `02-RESEARCH.md` and canonical architecture docs.

Concrete planning constraints to carry forward:

- VPC module `terraform-aws-modules/vpc/aws` `6.7.3`; EKS module `terraform-aws-modules/eks/aws` `21.26.0`; fck-nat `RaJiska/fck-nat/aws` `1.6.1`.
- Keep fck-nat as the owner of private route tables and target its persistent ENI; do not add duplicate `aws_route` resources.
- Put gateway endpoints in the intended route tables; interface endpoints are explicitly false by default.
- Pin Kubernetes `1.34` and managed add-on versions; v21 uses access entries and Pod Identity rather than the removed `aws-auth`/Karpenter IRSA examples.
- Keep EKS control-plane and Karpenter cloud resources in L1, without Kubernetes/Helm providers.

### `sh/drain-{ingress,nodes,pvcs}.sh` (lifecycle scripts, request-response)

**Analog:** `sh/verify-teardown.sh`; supporting shell idioms also appear in `sh/empty-versioned-bucket.sh`.

**Fail-closed constants and retry configuration** (`sh/verify-teardown.sh`, lines 3-17):

```bash
set -euo pipefail

readonly EXIT_CLEAN=0
readonly EXIT_ORPHANS=1
readonly EXIT_ERROR=2
readonly IMMORTAL_TAG_KEY="Layer"
readonly IMMORTAL_TAG_VALUE="00-bootstrap"
readonly GLOBAL_REGION="us-east-1"
readonly PROJECT_TAG_KEY="Project"
readonly MAX_TIER3_WORKERS=4
readonly ALLOWLIST="${ALLOWLIST:-sh/teardown-allowlist.txt}"
readonly REPORT="${REPORT:-.teardown-report.json}"
readonly HOME_REGION="${AWS_REGION:-us-east-1}"
export AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-8}"
```

Use Bash strict mode, quote expansions, parse AWS JSON with `jq`, and treat API errors/unknown states as errors rather than absence. Unlike the verifier's broad sweep, each drain must implement its resource-specific AWS terminal-state predicate. Keep polling under one deadline supplied by `make down`; do not reset a timeout per script. A failed drain returns nonzero so Make cannot proceed to destroy, and its diagnostics include the step, last observed Kubernetes/AWS state, and elapsed time.

`sh/empty-versioned-bucket.sh` is the closest small mutation loop: it repeats list/delete until an AWS-confirmed empty response, checks per-object errors, and reports completion only after the terminal state. Copy that fail-closed loop shape, not its S3 operations.

### `sh/nuke-project.sh` (candidate recovery utility)

**Partial analog:** `Makefile`'s `nuke-bootstrap` target (lines 174-216) demonstrates a separate, deliberately named decommission entry point, caller/account checks, and restoration traps around temporary state changes. `sh/verify-teardown.sh` demonstrates reporting unknown/error conditions.

Cloud Nuke is a new integration, not an existing project pattern. Research recommends a fixed region/resource-type allowlist, positive `Project=microservices-demo` tag include, preview of the same target set that will execute, and no `vpc` resource type. The selected decision does not require a second confirmation. Never invoke this utility automatically from `make down`; report resources outside the project-tag boundary for explicit handling.

### `tests/phase2_lifecycle.bats` and `tests/static_contracts.bats` (tests)

**Analogs:** `tests/verify_teardown_exit_codes.bats` and `tests/static_contracts.bats`.

**Bats setup / cleanup** (`tests/verify_teardown_exit_codes.bats`, lines 3-20):

```bash
load 'helpers/load'

setup() {
  stub_aws_start
  ALLOWLIST="$BATS_TEST_TMPDIR/allowlist.txt"
  REPORT="$BATS_TEST_TMPDIR/teardown-report.json"
  : > "$ALLOWLIST"
  export ALLOWLIST REPORT
}

teardown() {
  stub_aws_stop
}
```

**Behavior assertion pattern** (`tests/verify_teardown_exit_codes.bats`, lines 50-80):

```bash
@test "an unallowlisted orphan exits 1" {
  require_sweep

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

  [ "$status" -eq 1 ]
  jq -e '.verdict == "orphans" and .exit_code == 1 and .summary.total_orphans > 0' \
    "$REPORT" >/dev/null
}
```

The neighboring credential-failure test overlays an `.err` fixture and asserts exit `2`, no clean verdict, and a nonempty error report (`tests/verify_teardown_exit_codes.bats`, lines 70-80).

Keep tests scenario-focused and verify both exit status and observable output/call ordering. The lifecycle suite should cover all eight actions, stop-before-destroy, partial cluster states, idempotent reruns, shared deadline, bounded retry, transient vs terminal vs unknown AWS responses, and verifier exits 0/1/2. Existing `tests/static_contracts.bats` uses `grep`/`awk` assertions over tracked source and loads `helpers/load`; extend it for exact pins/tags/network contracts/OWN-02 rather than creating a parallel static-test framework.

### AWS lifecycle fixtures under `tests/fixtures/aws/` (test data)

**Analogs:** `tests/fixtures/aws/eks-describe-cluster-eu-west-1.json` and the ELBv2/EC2 fixtures; `tests/helpers/stub-aws.bash` selects a fixture by AWS service/operation and optional region, then logs calls and fails if no fixture exists.

Existing EKS fixture excerpt (lines 1-8):

```json
{
  "cluster": {
    "name": "practice-stray-cluster",
    "arn": "arn:aws:eks:eu-west-1:123456789012:cluster/practice-stray-cluster",
    "status": "ACTIVE",
    "version": "1.34",
    "tags": {}
  }
}
```

Use API-shaped JSON fixtures for each terminal/transition state and `.err` fixtures for transient and permanent API failures. Keep fixture names aligned with `<service>-<operation>[-<region>].json` so the shared AWS stub resolves them without a new harness.

### `COSTS.md` and `VERSIONS.md` (documentation ledgers)

**Analogs:** the existing ledgers themselves.

For `COSTS.md`, preserve the dated source/confidence style and append only successful, measured `make up`/`make down` run durations and verifier outcomes, as the existing end note requires. Failed attempts must not enter the published timing series. For `VERSIONS.md`, add each chosen provider/module/add-on/client pin with its verbatim pin syntax and file location; the existing table is the source of truth, and `docs/CONVENTIONS.md` requires exact mirrored pins.

## Shared Patterns

### Lifecycle and Terraform ownership
**Sources:** `Makefile` lines 28-40 and 139-165; `layers/10-infra/versions.tf` lines 1-21; `docs/CONVENTIONS.md` lines 5-20.  
**Apply to:** `make up`, `make down`, and all L1 Terraform files. Keep Terraform init behind Make, preserve explicit state keys, exact pins, four default tags, and the L1 AWS-only provider boundary.

### Fail-closed AWS interpretation
**Sources:** `sh/verify-teardown.sh` lines 3-17; `tests/verify_teardown_exit_codes.bats` lines 50-80.  
**Apply to:** all drains, recovery reporting, and lifecycle tests. A command error, malformed/unknown response, or authorization failure cannot count as successful absence; preserve the verifier's 0/1/2 distinction.

### Bats/AWS fixture testing
**Sources:** `tests/helpers/load.bash` line 1; `tests/helpers/stub-aws.bash` lines 1-100; `tests/verify_teardown_exit_codes.bats` lines 3-20.  
**Apply to:** new lifecycle and static contract tests. Reuse the shared helper/stub and assert externally visible state, ordered calls, and failure boundaries.

### Destructive recovery boundary
**Sources:** `Makefile` `nuke-bootstrap` target; D-07/D-08 in `02-CONTEXT.md`; Cloud Nuke caveats in `02-RESEARCH.md`.  
**Apply to:** the separate manual recovery command only. Keep preview and execution type/region selection identical, require positive project tagging, exclude VPC deletion, and never chain recovery into ordinary teardown.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `layers/10-infra/vpc.tf` | infrastructure module | resource graph | No existing VPC layer/module configuration to copy. |
| `layers/10-infra/nat.tf` | infrastructure module | resource graph | No existing NAT instance/ENI/route implementation; use the pinned module research contract. |
| `layers/10-infra/eks.tf` | infrastructure module | resource graph | No existing EKS cluster implementation; use v21.26.0 contracts, not older examples. |
| `layers/10-infra/karpenter.tf` | infrastructure module | resource graph | No existing Karpenter AWS-side Terraform resources. |
| `sh/drain-*.sh` | lifecycle scripts | request-response with polling | No existing Kubernetes drain or AWS terminal-state poller. The verifier supplies shell/error idioms only. |

## Metadata

**Analog search scope:** `Makefile`, `sh/`, `layers/10-infra/`, `tests/`, `tests/fixtures/aws/`, `docs/`, and root cost/version ledgers.  
**Tracked-source gate:** every named code analog was confirmed by `git ls-files`; phase CONTEXT/RESEARCH inputs are planning artifacts, not analogs.  
**Pattern extraction date:** 2026-10-14
