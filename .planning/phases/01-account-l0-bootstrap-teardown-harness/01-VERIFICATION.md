---
phase: 01-account-l0-bootstrap-teardown-harness
verified: 2026-10-13T08:35:40Z
status: human_needed
score: 1/5 must-haves verified
covered_files:
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-01-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-01-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-02-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-02-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-03-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-03-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-04-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-04-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-05-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-05-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-06-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-06-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-07-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-07-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-08-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-08-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-09-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-09-SUMMARY.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-10-PLAN.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-10-SUMMARY.md
  - Makefile
  - .gitignore
  - .terraform-version
  - VERSIONS.md
  - backend.hcl.example
  - COSTS.md
  - docs/RUNBOOK-account-setup.md
  - docs/CONVENTIONS.md
  - layers/00-bootstrap/backend.tf
  - layers/00-bootstrap/main.tf
  - layers/00-bootstrap/outputs.tf
  - layers/00-bootstrap/variables.tf
  - layers/00-bootstrap/versions.tf
  - layers/00-bootstrap/cost-guardrails.tf
  - layers/00-bootstrap/oidc.tf
  - layers/00-bootstrap/README.md
  - layers/00-bootstrap/.terraform.lock.hcl
  - layers/10-infra/versions.tf
  - layers/10-infra/variables.tf
  - layers/10-infra/.terraform.lock.hcl
  - layers/20-data/versions.tf
  - layers/20-data/variables.tf
  - layers/20-data/.terraform.lock.hcl
  - layers/30-gitops/versions.tf
  - layers/30-gitops/variables.tf
  - layers/30-gitops/.terraform.lock.hcl
  - sh/doctor.sh
  - sh/verify-teardown.sh
  - sh/teardown-allowlist.txt
  - sh/test-verify-teardown.sh
  - sh/verify-no-access-keys.sh
  - sh/empty-versioned-bucket.sh
  - tests/oidc_trust.bats
  - tests/static_contracts.bats
  - .github/workflows/oidc-plan-role-smoke.yml
  - .github/workflows/oidc-apply-role-smoke.yml
  - .github/workflows/scheduled-teardown-sweep.yml
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 0/5
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 1: Account, L0 Bootstrap & Teardown Harness Verification Report

**Phase Goal:** The operator has an isolated, cost-guardrailed AWS account with an immortal bootstrap layer, and can prove teardown correctness before there is anything to tear down.
**Verified:** 2026-10-13T08:35:40Z
**Status:** human_needed
**Re-verification:** Yes — read-only evidence refresh, separately authorized single-policy reconciliation, and successful published OIDC smoke runs; phase status remains human-needed.

## Goal Achievement

The five ROADMAP Success Criteria remain the non-negotiable truths. This refresh adds read-only AWS and GitHub evidence from 2026-10-13. `AWS_PROFILE=microservices-demo make validate` passed all four layers, and `make verify-teardown` reported account `072842666153` clean for wired classes. An explicitly authorized saved plan applied one IAM policy update (0 add, 1 change, 0 destroy); no other apply, resource provisioning, cost event, or valid `make nuke-bootstrap` was run. The post-apply read-back confirmed the deny. Both published OIDC smoke workflows subsequently passed, including their AWS role assumptions. The evidence improves current-state confidence but does not establish every required lifecycle or external outcome.

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | `sh/verify-teardown.sh` exits zero on the empty account and non-zero for an untagged EBS orphan, checking all listed resource classes. | ? UNCERTAIN | Live `make verify-teardown` returned clean for the wired classes in account `072842666153`; fixture tests cover clean/orphan/error outcomes and per-class parsing. The required real untagged-EBS failure observation was not run, so the full criterion is not proven. |
| 2 | Applying `layers/00-bootstrap` stores state in a versioned S3 bucket, exposes then removes `.tflock`, and uses no DynamoDB table. | ? UNCERTAIN | Read-only inspection found versioning `Enabled`, current `bootstrap/terraform.tfstate` present, no currently listed `bootstrap/terraform.tfstate.tflock`, and no DynamoDB tables in `us-east-1`. The read-only plan and authorized IAM-policy apply both released their locks, but no in-flight observation captured lock appearance. |
| 3 | A deliberate $1 resource yields a Cost Anomaly Detection alert within one day, and a zero-spend Budget alarm is configured. | ? UNCERTAIN | Terraform source configures the $5 monthly budget, $1 daily actual-spend tripwire, and $1 service-dimension anomaly subscription. No live alert event was triggered and delivery/timing remains unverified. |
| 4 | Bootstrap spend is attributable by layer via `default_tags`, and idle cost is at most $5/month over a real billing period. | ? UNCERTAIN | Four `default_tags` keys are configured; the operator manually confirmed all four Active on 2026-10-09. Billing-period attribution is not complete, so neither per-layer actual attribution nor the real-period $5 ceiling is established. |
| 5 | GitHub Actions assumes a repository/branch-scoped AWS role through OIDC, with no long-lived access key in AWS or GitHub secrets. | VERIFIED | Live plan/apply/sweep trust subjects and audiences match their intended PR/develop claims. Root access-key count and IAM-user count are both zero; Actions, Dependabot, and Codespaces secret stores each contain zero secrets, no environments exist, and all four required repository variables exist. Plan-role PR run `38370179861` and apply-role `develop` push run `38370037745` both succeeded. The live apply guardrail also denies `iam:CreateServiceSpecificCredential`. |

**Score:** 1/5 truths fully verified. The other four criteria still lack at least one required observation. No roadmap truth is marked FAILED because the remaining evidence is unavailable or prohibited; status remains `human_needed`.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `sh/verify-teardown.sh` | Account sweep and three-way verdict | PRESENT, substantive, wired | AWS responses flow into per-class findings/errors and JSON report. Fixture cases cover clean, orphan, credential error, pagination error, and regional unavailability. The 2026-10-13 live sweep returned clean for wired classes. |
| `sh/test-verify-teardown.sh` | Repeatable live clean/orphan/error proof | PRESENT, substantive, wired | The orphan arm creates a real EBS volume. It was not run; no AWS resource was provisioned. |
| `layers/00-bootstrap/main.tf`, `backend.tf` | Immortal, versioned S3 state backend | PRESENT, substantive, wired; live state observed | Source configures versioning, encryption, public access block, retention, `prevent_destroy`, and S3 backend. Live bucket `tfstate-072842666153-us-east-1` reports versioning Enabled and contains the current bootstrap state object. No current lock object was listed; apply lock lifecycle remains unobserved. |
| `layers/00-bootstrap/cost-guardrails.tf` | Budget, anomaly monitor, SNS alert path | PRESENT, substantive, wired | Dependencies and thresholds are implemented and statically tested; no cost event was triggered. |
| `layers/00-bootstrap/oidc.tf` and workflows | Repository-scoped OIDC roles and smoke checks | PRESENT, substantive, published and live-tested | Live plan trust is `repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:pull_request`; apply and sweep trust are `repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:ref:refs/heads/develop`; all require audience `sts.amazonaws.com`. Plan-role PR run `38370179861` and apply-role push run `38370037745` both passed. The live apply guardrail matches source after the authorized update and read-back. CD-06 remains open and out of Phase 1. |
| Four Terraform layers and version inventory | Layer split and exact pins | PRESENT, substantive, wired | Exact pins/native locking are present; isolated credential-free validation passed. |
| `sh/verify-no-access-keys.sh` | Current AWS/GitHub credential audit | PRESENT, substantive, wired | Read-only checks observed root access-key count 0, IAM-user count 0, three GitHub secret stores with 0 secrets each, and no repository environments. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Teardown sweep | AWS APIs | `aws_json` and service `describe`/`list` calls | WIRED; live observed | Read-only sweep returned clean for wired classes in account `072842666153`; fixture replay covers call shapes and parsing. |
| Teardown sweep | `.teardown-report.json` and exit status | Findings/error aggregation and serialization | WIRED | Bats proves clean=0, orphan=1, error=2, and no false clean verdict on errors. |
| `make bootstrap` | S3 remote state/lock | Local apply, output, generated backend, migration | WIRED in source; partial live evidence | Current S3 state and versioning are observed. The read-only plan acquired and released the native lock; apply-time lifecycle remains unobserved. |
| Provider `default_tags` | Bootstrap resources and Cost Explorer | AWS provider tags followed by billing allocation | PARTIAL | Configuration and manual Active status are evidenced; real period attribution is not. |
| OIDC workflow | AWS role | Repository variable → `role-to-assume` → STS | PASS | Published plan-role PR run `38370179861` and apply-role `develop` run `38370037745` both assumed their scoped AWS roles successfully. |
| Budget/CAD resources | SNS email endpoint | Terraform references and topic policy | WIRED in source; delivery not exercised | No real event or delivery test was triggered. |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Produces Real Data | Status |
|---|---|---|---|---|
| Teardown sweep | Service response JSON | AWS CLI APIs in script | Yes, with valid AWS credentials | FLOWING; current live sweep completed clean for wired classes |
| Teardown tests | Fixture JSON | Hand-authored AWS response fixtures through `stub-aws.bash` | Fixture data | FLOWING for local behavior, not a substitute for live proof |
| State backend | State and lock objects | S3 backend with `use_lockfile` | Yes, after Terraform operations | State object/versioning observed; the authorized plan acquired and released the native lock, but apply-time lifecycle remains unobserved |
| Cost alerts | Budget/CAD notifications | AWS services → SNS | Yes, on qualifying spend | WIRED; no event triggered |
| OIDC smoke checks | Caller identity | GitHub OIDC token → STS | Yes, on workflow run | FLOWING; PR plan-role run `38370179861` and `develop` apply-role run `38370037745` both succeeded. Temporary PR #4 was closed without merging and its branch deleted. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Fixture-backed sweep, OIDC, tags, lock, version, decommission contracts | `bats tests/` | 56 passed, 0 skipped, 0 failed | PASS |
| Terraform validation, format, ShellCheck | `AWS_PROFILE=microservices-demo make validate` | All four layers validated; command completed successfully | PASS |
| Current account sweep | `AWS_PROFILE=microservices-demo make verify-teardown` | Account `072842666153`; clean for wired classes | PASS (point-in-time) |
| AWS identity and credential inventory | STS caller identity; IAM account summary and `list-users` | Expected account `072842666153`; root access-key count 0; IAM-user count 0 | PASS (current state) |
| GitHub credential configuration | Secret-store, environment, and repository-variable queries | Actions/Dependabot/Codespaces each 0 secrets; 0 environments; all four required variables exist | PASS (configuration state) |
| Remote state and current lock | S3 versioning, `head-object`, lock-prefix listing; DynamoDB `list-tables` in `us-east-1` | Versioning Enabled; bootstrap state object present; no current `.tflock`; no regional DynamoDB tables | PASS (snapshot only; lock lifecycle unverified) |
| Live OIDC trust and apply guardrail | IAM `get-role` / `get-role-policy`; saved Terraform plan/apply | Three trust subjects match intended claims; deployed deny policy includes `iam:CreateServiceSpecificCredential` | PASS (current IAM state) |
| Published OIDC smoke workflow runs | GitHub Actions run IDs `38370179861` and `38370037745` | PR plan-role and `develop` apply-role runs both completed successfully, including Terraform validation and AWS role assumption | PASS |
| Bootstrap Terraform plan | Explicitly authorized read-only operation | 0 add, 1 in-place change, 0 destroy; state lock released | PASS (inspection only; no apply) |
| Targeted bootstrap Terraform apply | Explicitly authorized saved-plan operation | 0 added, 1 changed, 0 destroyed; live IAM policy read-back confirmed the deny | PASS (single authorized policy update) |
| Valid `make nuke-bootstrap` | Not authorized | Not run | SKIPPED BY CONSTRAINT |
| Real $1 spend/anomaly event | Prohibited by request | Not triggered | SKIPPED BY CONSTRAINT |

### Probe Execution

No phase-declared probe paths were found and no `probe-*.sh` files were present in the conventional project locations. Skipped, not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| COST-01 | 01-03, 01-06 | Idle cost at most $5/month over a real billing period | NEEDS HUMAN | No complete billing-period attribution/idle-cost evidence yet. |
| COST-04 | 01-06 | Zero-spend budget and $1 anomaly alert | NEEDS HUMAN | Source thresholds are verified; no real event or alert delivery was observed. |
| COST-05 | 01-01, 01-03, 01-06, 01-10 | Default tags and per-layer spend attribution | PARTIAL / NEEDS HUMAN | Four keys were manually confirmed Active 2026-10-09; actual spend attribution remains incomplete. |
| COST-08 | 01-03, 01-04, 01-05, 01-08, 01-09 | Dedicated account keeps the account-wide sweep safe | SATISFIED (current identity/inventory) | STS identity matches account `072842666153`; live sweep is clean for wired classes. |
| COST-09 | 01-01, 01-03 | Measured up/down times and real profile costs | DEFERRED | Phase 2 SC1 measures up/down time; Phase 5 SC5 measures core-profile cost. No Phase 1 up/down session exists to measure. |
| LIFE-05 | 01-02, 01-04, 01-05, 01-08, 01-09, 01-10 | Sweep fails for all required orphan classes | PARTIAL / NEEDS HUMAN | Live empty-account sweep passed for wired classes; the real untagged-EBS failure arm was not exercised. |
| LIFE-07 | 01-01, 01-04 | Four lifetime-aligned Terraform layers | SATISFIED (repository) | Four layer directories and state-key conventions are present; static contracts pass. |
| LIFE-08 | 01-04 | Versioned S3 state, native locking, no DynamoDB table | PARTIAL / NEEDS HUMAN | Live versioning/state object and no current lock/no `us-east-1` DynamoDB table observed; apply-time lock lifecycle remains unverified. |
| LIFE-09 | 01-01, 01-04, 01-10 | Slow/near-free resources stay in bootstrap, outside daily teardown | SATISFIED (repository) | Bootstrap is outside ordinary targets; only the guarded decommission target can destroy it. Valid destructive path was not run. Future ECR/CloudFront placement is explicit in phase context. |
| LIFE-10 | 01-01, 01-02, 01-04, 01-10 | Exact pinned tool/provider/action versions | SATISFIED (repository) | Exact pins and `VERSIONS.md` entries are present; offline validation passed. |
| CD-05 | 01-02, 01-07, 01-09, 01-10 | Scoped GitHub OIDC and no long-lived keys | SATISFIED | Live trust subjects, zero root keys/users, zero GitHub secrets, required variables, and successful plan/apply smoke-run role assumptions are verified. |
| CD-06 | Phase 3 | Terraform plan on PR and apply on merge through OIDC | OPEN / OUT OF PHASE | Remains open. Renamed workflows only smoke-test OIDC and format/validate; they do not execute Terraform plan/apply. |

No Phase 1 roadmap requirement was orphaned from the plans. COST-09 is deferred to explicit later-phase measurements. CD-06 is not a Phase 1 roadmap requirement.

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|---|---|---:|---:|---:|---|---|
| `tests/verify_teardown_exclusions.bats` | LIFE-05 | Yes | 0 in run | No | Value/behavior | PASS |
| `tests/verify_teardown_exit_codes.bats` | LIFE-05 | Yes | 0 in run | No | Behavior | PASS |
| `tests/oidc_trust.bats` | CD-05 | Yes | 0 in run | No | Contract/value | PASS |
| `tests/static_contracts.bats` | LIFE-08, LIFE-09, LIFE-10, COST-04, COST-05, CD-05 | Yes | 0 in run | No | Contract/value | PASS |
| `tests/harness_selftest.bats` | Harness | Yes | 0 in run | No | Behavior | PASS |

No disabled-test patterns or circular expected-value generation were found in the prior test audit. Prior suite result: 56 passed, 0 skipped; the Bats suite was not rerun during this read-only evidence refresh.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| None | — | No implementation debt markers, empty implementations, or user-visible stubs found in the reviewed implementation files. | — | No blocker identified. |

The wrong-confirmation path and static decommission contract pass. The valid `make nuke-bootstrap` path was intentionally not run.

### Live Policy Reconciliation

The authorized saved plan contained exactly one in-place update to add `iam:CreateServiceSpecificCredential` to `phase1-broad-apply-guardrails` (0 added, 1 changed, 0 destroyed). The apply completed, and a read-only IAM policy read-back confirmed the action is present in the explicit deny. The current inventory found zero root access keys and zero IAM users.

### Decision Coverage

The checked-in decision-coverage helper could not run. The required fingerprint command also fails because `command-roster.cjs` requires missing `sh/fix-slash-commands.cjs`. This gate is non-blocking; no decision count or digest is claimed. Directly relevant decisions (dedicated member account, S3 lockfile, OIDC scopes, L0 decommission boundary, and workflow rename) are reflected in current context, plans, summaries, and source.

The GSD runtime failure prevented generating `covered_digest` with `verification.fingerprint`; no digest is fabricated. `covered_files` records the plans/summaries, mapped requirements, and implementation surfaces used here.

### Advisory (New Scope, Unevidenced)

None. The live apply-policy difference was directly observed and resolved through the explicitly authorized saved-plan apply; no unevidenced new-scope concern was identified.

### Human Verification Required

#### 1. Real orphan failure proof

**Test:** When separately authorized, create the single untagged EBS test volume and verify the sweep returns non-zero, then clean it up. Do not do this in this read-only refresh.
**Expected:** The live sweep detects the orphan; the current read-only sweep already reports clean for wired classes.
**Why human:** The failure arm requires creating a billable AWS resource; fixtures do not prove the live failure path.

#### 2. Remote state and lock lifecycle

**Test:** Observe the native `.tflock` during a Terraform state operation and confirm it disappears afterward. The read-only plan and later authorized IAM-policy apply both completed and released their locks; neither operation observed the lock while it was in flight.
**Expected:** Versioned state remains present, the lock is acquired/released, and no DynamoDB lock table is used.
**Why human:** Current state/versioning and absence of a current lock are read-only snapshots; they cannot establish the in-flight lock lifecycle.

#### 3. Cost alert delivery

**Test:** Do not provision a $1 test resource or trigger a real cost event. Review a qualifying event only if it occurs organically or after separate authorization.
**Expected:** The configured Budget/CAD path delivers to the confirmed SNS email endpoint within its service delay.
**Why human:** Delivery and anomaly timing are external AWS behavior. Triggering the event is explicitly prohibited.

#### 4. Real billing period and tag attribution

**Test:** Once a complete billing period and refresh are available, inspect per-layer attribution and idle cost in the management-account billing/Cost Explorer view. Do not use the member CLI for organization-level tag status.
**Expected:** Spend after activation is attributable by layer and idle cost is at most $5/month. Pre-activation resources remain unattributable because tags do not backfill.
**Why human:** A complete billing period and management-account access are required. The four keys were manually confirmed Active on 2026-10-09; this is not observed spend attribution.

#### 5. Fork pull-request fallback

**Test:** Observe the existing fallback only if an actual fork PR exists; do not create a fork solely for this check.
**Expected:** Credential-free validation runs and no AWS OIDC role assumption is attempted.
**Why human:** No fork exists. Static assertions prove workflow conditions, not a fork-triggered run.

This is an infrastructure/foundation phase; no artificial manual UI test is needed. These checks concern external AWS, billing, and OIDC behavior required by the roadmap.

### Gaps Summary

No source artifact is missing or a stub, and static workflow/sweep wiring remains present. Today's checks establish that the account is clean for wired sweep classes, inspected credential/secrets stores are empty, the bootstrap state object is present in a versioned bucket, live OIDC trust conditions are scoped as intended, the live apply guardrail matches source, and both published OIDC smoke workflows passed. The remaining four roadmap truths still lack evidence for the real EBS failure arm, in-flight lock lifecycle, cost-alert delivery, and complete billing-period attribution/idle cost. The single-policy update was applied from the explicitly authorized saved plan; valid bootstrap destruction, resource provisioning, and a cost event were not performed under the user's constraints. Overall status remains `human_needed`.

Phase 1 remains executing. This report does not mark Phase 1 complete in `ROADMAP.md` or `STATE.md`.

---

_Verified: 2026-10-13T08:35:40Z_
_Verifier: the agent (gsd-verifier)_
