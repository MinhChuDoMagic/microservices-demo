---
phase: 01-account-l0-bootstrap-teardown-harness
verified: 2026-10-27T06:48:11Z
status: passed
score: 3/3 active roadmap truths verified
covered_files:
  - .github/workflows/oidc-apply-role-smoke.yml
  - .github/workflows/oidc-plan-role-smoke.yml
  - .github/workflows/scheduled-teardown-sweep.yml
  - .gitignore
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
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
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md
  - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-UAT.md
  - .terraform-version
  - COSTS.md
  - Makefile
  - VERSIONS.md
  - backend.hcl.example
  - docs/CONVENTIONS.md
  - docs/RUNBOOK-account-setup.md
  - layers/00-bootstrap/.terraform.lock.hcl
  - layers/00-bootstrap/README.md
  - layers/00-bootstrap/backend.tf
  - layers/00-bootstrap/cost-guardrails.tf
  - layers/00-bootstrap/main.tf
  - layers/00-bootstrap/oidc.tf
  - layers/00-bootstrap/outputs.tf
  - layers/00-bootstrap/terraform.tfvars.example
  - layers/00-bootstrap/variables.tf
  - layers/00-bootstrap/versions.tf
  - layers/10-infra/.terraform.lock.hcl
  - layers/10-infra/versions.tf
  - layers/20-data/.terraform.lock.hcl
  - layers/20-data/versions.tf
  - layers/30-gitops/.terraform.lock.hcl
  - layers/30-gitops/versions.tf
  - sh/doctor.sh
  - sh/empty-versioned-bucket.sh
  - sh/teardown-allowlist.txt
  - sh/test-verify-teardown.sh
  - sh/verify-no-access-keys.sh
  - sh/verify-teardown.sh
  - tests/fixtures/aws/README.md
  - tests/fixtures/aws/cloudfront-list-distributions.json
  - tests/fixtures/aws/ec2-describe-addresses-eu-west-1.json
  - tests/fixtures/aws/ec2-describe-addresses.json
  - tests/fixtures/aws/ec2-describe-images.json
  - tests/fixtures/aws/ec2-describe-instances-eu-west-1.json
  - tests/fixtures/aws/ec2-describe-instances.json
  - tests/fixtures/aws/ec2-describe-network-interfaces.json
  - tests/fixtures/aws/ec2-describe-regions.json
  - tests/fixtures/aws/ec2-describe-security-groups.json
  - tests/fixtures/aws/ec2-describe-snapshots.json
  - tests/fixtures/aws/ec2-describe-volumes.json
  - tests/fixtures/aws/eks-describe-cluster-eu-west-1.json
  - tests/fixtures/aws/eks-list-clusters-eu-west-1.json
  - tests/fixtures/aws/eks-list-clusters.json
  - tests/fixtures/aws/elb-describe-load-balancers-eu-west-1.json
  - tests/fixtures/aws/elb-describe-load-balancers.json
  - tests/fixtures/aws/elbv2-describe-load-balancers-eu-west-1.json
  - tests/fixtures/aws/elbv2-describe-load-balancers.json
  - tests/fixtures/aws/elbv2-describe-target-groups.json
  - tests/fixtures/aws/iam-list-role-tags-gha-terraform-apply.json
  - tests/fixtures/aws/iam-list-role-tags-gha-terraform-plan.json
  - tests/fixtures/aws/iam-list-role-tags.json
  - tests/fixtures/aws/iam-list-roles.json
  - tests/fixtures/aws/logs-describe-log-groups.json
  - tests/fixtures/aws/logs-list-tags-for-resource-_aws_eks_demo_bootstrap-immortal.json
  - tests/fixtures/aws/logs-list-tags-for-resource.json
  - tests/fixtures/aws/phase2-lifecycle-sequences.json
  - tests/fixtures/aws/rds-describe-db-instances-eu-west-1.json
  - tests/fixtures/aws/rds-describe-db-instances.json
  - tests/fixtures/aws/resourcegroupstaggingapi-get-resources-expired-page.err
  - tests/fixtures/aws/resourcegroupstaggingapi-get-resources-page-two.json
  - tests/fixtures/aws/resourcegroupstaggingapi-get-resources.json
  - tests/fixtures/aws/s3api-get-bucket-location-practice-unexpected-bucket.json
  - tests/fixtures/aws/s3api-get-bucket-location-tfstate-123456789012-us-east-1.json
  - tests/fixtures/aws/s3api-get-bucket-tagging-practice-unexpected-bucket.err
  - tests/fixtures/aws/s3api-get-bucket-tagging-tfstate-123456789012-us-east-1.json
  - tests/fixtures/aws/s3api-list-buckets.json
  - tests/fixtures/aws/sts-get-caller-identity-expired.err
  - tests/fixtures/aws/sts-get-caller-identity.json
  - tests/helpers/load.bash
  - tests/helpers/stub-aws.bash
  - tests/harness_selftest.bats
  - tests/oidc_trust.bats
  - tests/static_contracts.bats
  - tests/verify_teardown_exclusions.bats
  - tests/verify_teardown_exit_codes.bats
covered_digest: "v1:sha256:3c2747414d80816d3a12f8b95e8742889f657f118e44f03483caaac4a3141a2f"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 2/3
  gaps_closed:
    - OIDC workflow Terraform versions now match the repository pin and all four layer constraints.
    - The accepted read-only plan lock observation satisfies the updated S3 lock criterion; apply-time observation is deferred.
  gaps_remaining: []
  regressions: []
---

# Phase 1: Account, L0 Bootstrap & Teardown Harness Verification Report

**Phase Goal:** The operator has an isolated, cost-guardrailed AWS account with an immortal bootstrap layer, and can prove teardown correctness before there is anything to tear down.
**Verified:** 2026-10-27T06:48:11Z
**Status:** passed
**Re-verification:** Yes, after closing the Terraform version mismatch and applying the updated acceptance contract.

The current roadmap has three active success criteria. Criteria #3 (live Cost Anomaly Detection delivery) and #4 (real billing-period attribution and idle-cost measurement) were dropped on 2026-10-26. They are excluded from this report's denominator; they are neither passed, failed, nor overridden.

| # | Observable truth | Status | Evidence |
|---|---|---|---|
| 1 | `sh/verify-teardown.sh` returns clean for the empty account and detects a manually created untagged EBS volume while checking the required resource classes. | VERIFIED | `bats tests/` passes 122/122 with no skips, including two-sided resource-class fixtures and clean/orphan/error exit tests. Historical live hard-gate evidence is retained below; no account check was made in this refresh. |
| 2 | A remote-backed plan for `layers/00-bootstrap` observes versioned S3 state and native `<key>.tflock` acquisition/release, with no DynamoDB lock table. | VERIFIED | UAT #10 and dated 2026-10-13 evidence record the lock object while held by a read-only plan and its 404 after release; state versioning and no DynamoDB table were also recorded. Current backend/configuration and static Bats checks confirm `use_lockfile`, versioning, and no lock-table argument. Apply-time observation is deferred by the updated acceptance contract and is not required. |
| 5 | GitHub Actions assumes repository/branch-scoped AWS roles through OIDC and has no long-lived AWS access key. | VERIFIED (historical runtime evidence; current static contract) | Historical PR plan-role and `develop` apply-role runs succeeded, and the historical account/GitHub credential audit found no active keys or secrets. Current workflow source pins Terraform 1.17.0 throughout; the local regression suite verifies that alignment. No post-fix GitHub run or new credential inventory was performed. |

**Score:** 3/3 active roadmap truths verified. Criteria #3 and #4 remain excluded by the recorded user decision, not passed or overridden.

## Version Fix

The previous `gaps_found` item is closed. The plan-role workflow, both jobs in its fork-validation workflow, and the apply-role workflow all set Terraform `1.17.0`. This matches `.terraform-version`, `VERSIONS.md`, and `required_version = "= 1.17.0"` in all four layers. The current Bats suite includes the workflow version contract and passes 122/122. This verifies local source consistency only; it is not a new GitHub Actions run.

## Historical Evidence

These observations come from dated phase artifacts and the superseded report. They are not live checks performed on 2026-10-27.

| Date/scope | Evidence | Limitation |
|---|---|---|
| 2026-10-09 | Plan 01-09 records the clean, untagged-volume orphan, and invalid-credential hard-gate arms passing; post-run volume inventory was zero. | Historical run; this refresh did not contact AWS or create a volume. |
| 2026-10-13 | The superseded verification records another live three-arm hard-gate: temporary volume `vol-0acc814aa94bd9019` was reported as an orphan, deleted, and followed by a clean sweep; invalid credentials returned error rather than clean. | Preserved as recorded; not independently rerun. |
| 2026-10-13 | A read-only bootstrap Terraform plan reported lock acquisition/release. A concurrent S3 watcher observed the 260-byte `bootstrap/terraform.tfstate.tflock` object at 09:18:18–09:18:32 UTC, followed by 404 responses. The report also recorded S3 versioning enabled, state present, and no DynamoDB table in `us-east-1`. | Read-only plan evidence accepted by the updated Phase 1 contract; no apply-time observation is claimed. |
| Historical runs; dates not stated in the cited phase artifact | GitHub Actions run `38370179861` (PR plan-role smoke) and `38370037745` (`develop` apply-role smoke) succeeded and reported assumed-role identities. Run `37910392741` was the negative untrusted-branch attempt and was rejected by OIDC trust. | Historical role-assumption evidence, not post-fix workflow runs. The smoke workflows do not run Terraform plan/apply. |
| Historical run; date not stated in the cited phase artifact | Scheduled teardown run `37914598359` succeeded and uploaded its report artifact. | No new scheduled run or AWS sweep was triggered. |
| 2026-10-13 | Historical AWS/GitHub credential inventory found zero root keys/users and zero secrets in the listed GitHub stores. | Point-in-time inventory only; no new credential inventory was performed. |
| 2026-10-09 | Plan 01-10 records operator confirmation that `Project`, `Layer`, `ManagedBy`, and `Environment` cost-allocation keys were active. | Does not establish billing-period attribution or idle cost. The corresponding roadmap truth was dropped on 2026-10-26. |
| 2026-10-15 | UAT #33 records the user-provided AWS Budgets email for the `$1` daily tripwire, reporting `$2.21` actual spend. | This was a Budget email, not a Cost Anomaly Detection firing. The live CAD-delivery truth was dropped on 2026-10-26. |

UAT #10 remains recorded as pass for its stated remote-backed **plan** lock check, which is sufficient under the updated acceptance contract; apply-time observation is deferred. Live teardown signal-injection cleanup testing was removed from Phase 1 UAT entirely. The cleanup trap remains implemented, but no live interruption verification is claimed. UAT #29 records the fork fallback as pass based on static coverage because no fork exists; no fork was created or tested here.

## Re-verification Evidence

| Check | Result | Scope |
|---|---|---|
| `bats tests/` | 122 passed, 0 skipped, 0 failed | Local fixtures/static contracts only; no AWS calls. |
| Updated Phase 01 UAT | 32/32 passed, 0 issues, 0 pending, 0 blocked | Current UAT state as of 2026-10-27; cited historical/runtime checks retain their dates. |
| Terraform CLI pins | All OIDC job pins, `.terraform-version`, `VERSIONS.md`, and four layer constraints match at 1.17.0 | Current repository source; no post-fix GitHub run. |
| Teardown live hard gate | Clean, orphan detection, cleanup, and invalid-credential error historically observed | Historical only; not rerun. |
| S3 lock lifecycle | Acquisition and release observed during a read-only plan | Historical dated evidence accepted by the updated contract; apply-time observation deferred. |
| OIDC role assumptions | Plan/apply success and untrusted-branch rejection recorded | Historical workflow runs; dates not stated in cited artifact. |
| Live AWS state, current credentials, billing, and apply lock | Not run | Outside scope; no AWS calls, Terraform operations, `make up`/`make down`, or resource creation. |

## Human Verification Required

None. The remaining lock condition is covered by the accepted read-only plan observation; apply-time observation is deferred. Live signal-injection cleanup was removed from Phase 1 UAT, so no live interruption check is asserted.

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `sh/verify-teardown.sh` and `sh/test-verify-teardown.sh` | Account-wide sweep and repeatable clean/orphan/error hard gate | VERIFIED | Current fixture tests exercise resource-class filters and all three exit outcomes. Historical live runs are dated above; no new live run was made. |
| `layers/00-bootstrap/main.tf`, `backend.tf`, and generated-backend contract | Versioned S3 state, native lockfile backend, and protected bootstrap bucket | VERIFIED | Source configures S3 state; static tests verify `use_lockfile`, versioning, and no DynamoDB lock argument. Dated read-only plan evidence records acquisition/release and is accepted under the current contract. |
| `layers/00-bootstrap/oidc.tf` and OIDC workflows | Repository/ref-scoped roles and current smoke workflow wiring | VERIFIED (source/static; runtime evidence historical) | Trust policies use exact subject/audience conditions. Workflow pins align at 1.17.0; historical role-run scope and limitations are stated above. |
| `sh/verify-no-access-keys.sh` | Read-only AWS/GitHub credential inventory | PRESENT; current live inventory not checked | Script covers AWS root/user keys and GitHub stores. Historical inventory is dated above. |
| Terraform version inventory and four layer constraints | Exact matching Terraform CLI pin | VERIFIED | `.terraform-version`, `VERSIONS.md`, all four layer constraints, and both OIDC workflows specify 1.17.0; the Bats version-contract test passes. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Teardown sweep | AWS resource APIs | AWS CLI calls through the sweep wrapper | WIRED | Fixture stub verifies arguments and response handling; historical live sweep evidence is not a current account check. |
| Teardown sweep | Report and exit code | Findings/error aggregation | WIRED | Current tests verify clean=0, orphan=1, and error=2, including no clean result after an API error. |
| Bootstrap Terraform | S3 state and native lock | S3 backend with `use_lockfile` and bucket versioning | WIRED | Current source/static contracts and accepted dated read-only plan observation verify the current criterion; apply-time observation is deferred. |
| OIDC workflows | AWS roles | Repository role variables → credentials action → STS identity check | WIRED | Current YAML and Bats tests verify the connection; historical plan/apply runs provide runtime evidence. No post-fix GitHub run was made. |

## Data-Flow Trace

| Artifact | Data | Source | Produces real data | Status |
|---|---|---|---|---|
| Teardown verifier | Resource inventory | AWS APIs in `sh/verify-teardown.sh` | Yes with valid credentials | Fixture-flow verified; last live-account observations are historical. |
| Teardown tests | Resource response objects | Recorded JSON fixtures through the AWS stub | Fixture data | Flowing for local behavior; not a substitute for live AWS proof. |
| Bootstrap state | State and lock objects | Terraform S3 backend | Yes during Terraform operations | Configuration wired; state/versioning and read-only-plan lock evidence are historical. |
| OIDC smoke workflows | Caller identity | GitHub OIDC token → STS | Yes on a successful workflow run | Historical runs succeeded; current workflow pin alignment is locally tested, not live-rerun. |

## Behavioral Spot-Checks

| Behavior | Command/evidence | Result | Status |
|---|---|---|---|
| Fixture harness, teardown class exclusions, OIDC trust, version alignment, and static contracts | `bats tests/` | 122 tests passed, no skips | PASS (local; no AWS calls) |
| Terraform CLI consistency | Workflow assertions within `bats tests/` | Plan, fork-validation, and apply jobs plus `.terraform-version`, `VERSIONS.md`, and all layer constraints match at 1.17.0 | PASS |
| Live teardown hard gate | Phase artifacts dated 2026-10-09 and 2026-10-13 | Clean, orphan detection, cleanup, and invalid-credential error historically observed | PASS (historical; not rerun) |
| S3 lock acquisition/release | Read-only plan and concurrent S3 observation dated 2026-10-13 | Lock object observed and later absent | PASS under updated contract; apply-time observation deferred |
| GitHub OIDC role assumption and negative scope | Historical workflow run IDs listed above | Plan/apply role assumption succeeded; untrusted branch rejected | PASS (historical; no post-fix run) |
| AWS state, current credentials, billing, and apply lock | Not run | Outside scope; no AWS calls, Terraform operations, `make up`/`make down`, or resource creation | SKIPPED BY SCOPE |

## Probe Execution

No phase-declared `probe-*.sh` path was found in the Phase 01 plans or summaries. Not applicable.

## Current Requirements Coverage

| Requirement | Status | Evidence |
|---|---|---|
| COST-01 | PARTIAL; billing-period outcome dropped | Budget/cost configuration remains; real-period idle-cost and attribution evidence is not claimed. |
| COST-04 | PARTIAL; live CAD delivery dropped | Configuration is present; the 2026-10-15 Budget email is historical and is not CAD evidence. |
| COST-05 | PARTIAL; billing attribution dropped | Default tags are configured and activation was operator-confirmed 2026-10-09; no real-period attribution is claimed. |
| COST-08 | SATISFIED (historical setup) | Dedicated member-account setup and sweep safety were recorded in Phase 01 artifacts; no current AWS identity query was made. |
| COST-09 | DEFERRED | Phase 2 up/down durations are recorded; core-profile cost measurement is assigned to Phase 5. |
| LIFE-05 | SATISFIED | Current Bats tests pass; the live three-arm test evidence is historical and dated above. |
| LIFE-07 | SATISFIED | Four lifetime-aligned Terraform layers and state-key conventions exist. |
| LIFE-08 | SATISFIED under updated lock contract | S3 versioning and native `use_lockfile` are configured; the dated read-only plan lock observation meets the current acceptance criteria. |
| LIFE-09 | SATISFIED (configuration; destructive path not run) | Bootstrap is outside the daily loop; the guarded decommission target and versioned-bucket emptier are present. The valid destroy path was intentionally not executed. |
| LIFE-10 | SATISFIED (current static contract) | Exact Terraform/provider/module pins and lockfiles match the current version inventory; the Terraform CLI and workflow pins align at 1.17.0. |
| CD-05 | SATISFIED (historical runtime plus current static contract) | OIDC role runs and a negative trust test are historical; current trust/workflow wiring and no-static-credential contracts pass locally. No post-fix GitHub run or credential inventory was performed. |

All 11 Phase 01 requirement IDs from the current roadmap and plans are accounted for. COST-09 is deferred to later phase measurements. The two dropped roadmap truths are excluded rather than mapped to passed requirements.

## Anti-Patterns Found

No actionable `TODO`, `FIXME`, `XXX`, `TBD`, `HACK`, placeholder, or empty implementation was found in the reviewed Phase 01 scripts, bootstrap Terraform, or workflows. The `XXXXXX` matches are `mktemp` templates, not debt markers.

## Archived Superseded Report (Not Current Verdict)

The legacy material below is retained only as an audit trail. Its verdicts, gaps, and version-pin findings are obsolete and must not be used as the current Phase 01 result; the current verdict is passed, 3/3 above. The archival text makes no claim that live signal-injection cleanup was tested.

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `sh/verify-teardown.sh` | Account-wide sweep and clean/orphan/error outcomes | VERIFIED | Substantive API inventory, report generation, allowlist handling, and fail-closed error aggregation. Fixture tests cover result semantics and resource-class exclusions. |
| `sh/test-verify-teardown.sh` | Repeatable live clean/orphan/error proof with cleanup | PRESENT; cleanup interruption unverified | Contains the three arms and an EXIT/signal cleanup trap. Historical normal-run evidence exists; UAT says interruption after volume creation was not exercised. |
| `layers/00-bootstrap/main.tf`, `backend.tf` | Immortal versioned S3 backend | VERIFIED (configuration); live state evidence historical | Source configures versioning, encryption, public access blocking, ownership controls, retention, `prevent_destroy`, and the S3 backend. Historical state/lock observations are dated below. |
| `layers/00-bootstrap/cost-guardrails.tf` | Budget and anomaly configuration with SNS path | VERIFIED (configuration) | Thresholds, topic policy, subscriptions, and cost tags have static coverage. This is not a new live CAD-delivery result. |
| `layers/00-bootstrap/oidc.tf` and OIDC workflows | Scoped roles and working smoke workflows | PARTIAL | Trust conditions and role wiring are present and statically tested; current workflow Terraform pins disagree with all layer constraints. |
| `.terraform-version`, `VERSIONS.md`, layer `versions.tf` and lockfiles | Consistent exact tool/provider/module pins | PARTIAL | Repository/layer/provider/module pins and lockfiles agree at Terraform 1.17.0 and AWS provider 6.70.0. The OIDC workflows still install Terraform 1.16.4. |
| `sh/verify-no-access-keys.sh` | Read-only AWS/GitHub credential inventory | PRESENT; live inventory historical | Script checks root and IAM-user keys, GitHub secret stores, environments, and required repository variables. The prior report records the 2026-10-13 inventory; it was not rerun. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Teardown sweep | AWS APIs | AWS CLI describe/list calls | WIRED | Fixture stub captures arguments and supplies fixture responses; historical live sweep evidence is not represented as a current account check. |
| Teardown sweep | JSON report and exit code | Findings/error aggregation | WIRED | Current exit-code tests cover clean=0, orphan=1, and error=2, including no false-clean result after API failure. |
| Bootstrap Terraform | S3 state and native lock | Backend `use_lockfile` plus bucket versioning | WIRED; lifecycle behavior unverified | Current static contract passes; historical `.tflock` observation was from a read-only plan, not apply. |
| OIDC workflow | AWS role | Repository variable → `role-to-assume` → STS | PARTIAL | Trust policy and credential steps are connected, but the current Terraform mismatch precedes credential configuration. Prior role-assumption runs are historical. |
| Provider `default_tags` | Bootstrap resources | Provider-level tags on L0 resources | WIRED | Source and static contracts verify the four keys. Billing-period attribution is no longer a Phase 1 gate. |

## Data-Flow Trace

| Artifact | Data | Source | Produces real data | Status |
|---|---|---|---|---|
| Teardown verifier | Resource inventory | AWS APIs in the script | Yes, with valid credentials | Fixture-flow verified; latest live account state not queried. |
| Teardown tests | API response values | AWS fixture JSON through the test stub | Fixture data | Flowing for local behavior; historical live test is separate. |
| Bootstrap state | State and lock objects | Terraform S3 backend | Yes, during Terraform operations | Configuration wired; historical state and read-only-plan lock evidence only. |
| OIDC smoke workflows | STS caller identity | GitHub OIDC token and AWS credentials action | Yes, on a successful workflow run | Historical runs succeeded; current workflow CLI version is inconsistent. |
| Cost alerts | Budget/CAD notification | AWS service → SNS subscription | Yes, on qualifying events | 2026-10-15 Budget email is historical evidence; CAD delivery was dropped as a gate. |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Fixture harness, OIDC trust, static contracts, lifecycle stubs, and teardown outcomes | `bats tests/` | 122 passed, 0 skipped, 0 failed | PASS |
| Exact version inventory contract | `bats --filter 'L1 exact provider module add-on and AMI pins match VERSIONS.md' tests/static_contracts.bats` | 1 passed | PASS; test does not assert workflow `terraform_version` values |
| Current OIDC Terraform CLI consistency | Compare workflow values with `.terraform-version` and each layer's `required_version` | Workflows: 1.16.4; repository/layers: 1.17.0 | FAIL |
| Live AWS state, credential, billing, and lock checks | Not run | Prohibited by task scope; no AWS calls or resources were created | SKIPPED |

## Probe Execution

No runnable `probe-*.sh` paths are declared in the phase plans or summaries, and no conventional project probe was found. Not applicable.

## Requirements Coverage

| Requirement | Source plan(s) | Status | Evidence |
|---|---|---|---|
| COST-01 | 01-03, 01-06 | SATISFIED (configuration; billing-period test dropped) | Monthly $5 budget and cost model are documented/configured. Real-period verification was dropped 2026-10-26. |
| COST-04 | 01-06 | SATISFIED (configuration) | Budget/CAD/SNS configuration is statically checked; the 2026-10-15 $2.21 Budget email is historical. Live CAD delivery was dropped as a gate. |
| COST-05 | 01-01, 01-03, 01-06, 01-10 | SATISFIED (configuration) | Four default tag keys are configured; the prior report records operator confirmation they were Active on 2026-10-09. Billing attribution was dropped. |
| COST-08 | 01-03, 01-04, 01-05, 01-08, 01-09 | SATISFIED (historical account setup) | Dedicated-account setup and safeguards are documented; no current AWS identity or inventory query was made. |
| COST-09 | 01-01, 01-03 | DEFERRED (partial) | Phase 2 up/down durations are in `COSTS.md` (908s and 1162s, recorded 2026-10-26). Core-profile observed cost is scheduled by Phase 5 success criterion 5. |
| LIFE-05 | 01-02, 01-04, 01-05, 01-08, 01-09, 01-10 | SATISFIED | Current fixture tests pass for resource classes and three-way verdicts; prior live untagged-volume hard-gate result is historical. |
| LIFE-07 | 01-01, 01-04 | SATISFIED | Four lifetime-aligned Terraform layers and state-key conventions are present. |
| LIFE-08 | 01-04 | PARTIAL (lifecycle observation historical) | Versioned S3 and native `use_lockfile` configuration are present; historical lock was observed during a plan, not apply. |
| LIFE-09 | 01-01, 01-04, 01-10 | SATISFIED (configuration) | Bootstrap is outside the daily lifecycle; the decommission path is explicit and guarded. The valid destructive path was not run. |
| LIFE-10 | 01-01, 01-02, 01-04, 01-10 | BLOCKED | Layer/repository pins agree, but all current OIDC workflow jobs select Terraform 1.16.4. |
| CD-05 | 01-02, 01-07, 01-09, 01-10 | PARTIAL / BLOCKED | Scoped trust and static workflow contracts pass; current workflow CLI mismatch invalidates the current end-to-end smoke path. Old role-assumption runs and credential inventory are historical. |

All 11 Phase 1 requirement IDs are mapped here. COST-09's remaining profile-cost measurement is deferred to Phase 5; no later phase is claimed to resolve the OIDC version mismatch.

## Anti-Patterns Found

No actionable TODO/FIXME/XXX/TBD/HACK/placeholder markers or empty implementations were found in reviewed implementation files. Temporary-file `XXXXXX` templates are not debt markers.

## Behavior Not Exercised

1. **Native lock lifecycle during apply.** The retained observation was a read-only plan, not an apply; no live transition test was run in this refresh.
2. **Interrupted hard-gate cleanup.** UAT says the post-volume-creation interruption path was not exercised. Testing it would create a billable test resource and is outside this verification's authorization.

No AWS calls, Terraform plan/apply/destroy, Make up/down, or resource creation were performed for this verification. This report does not mark Phase 1 complete in `ROADMAP.md` or `STATE.md`.

## Gaps Summary

The current OIDC plan/apply workflows pin Terraform 1.16.4 while `.terraform-version`, `VERSIONS.md`, and all four Terraform layers pin 1.17.0. This breaks the current exact-version contract and prevents treating old successful role-assumption runs as evidence for the current workflow configuration. Aligning the workflow CLI pins and verifying that current path is the blocking closure item. Separately, lock lifecycle during apply and interruption cleanup remain behavior-unverified; neither was exercised because this refresh was restricted to local/read-only checks.

## Historical Verification (Superseded)

The following prior report content is retained as historical evidence only. Its prior `passed` verdict and point-in-time account claims do not replace the current verdict above.

## Goal Achievement

The five ROADMAP Success Criteria remain the non-negotiable truths. This refresh adds read-only AWS and GitHub evidence from 2026-10-13 and user-provided AWS Budgets email evidence dated 2026-10-15. `AWS_PROFILE=microservices-demo make validate` passed all four layers, and the live teardown sweep returned clean before and after the authorized hard-gate test. An explicitly authorized saved plan applied one IAM policy update (0 add, 1 change, 0 destroy); a later read-only bootstrap plan found no changes and acquired/released the native S3 lock, which was observed in S3 while the plan was running. The authorized hard-gate created one temporary 1 GiB `gp3` EBS volume, verified orphan detection, and confirmed deletion and a clean post-test sweep. No deliberate cost-generating test, other apply, or valid `make nuke-bootstrap` was run. The new email evidence confirms organic delivery of the $1 daily Budget tripwire; Cost Anomaly Detection delivery remains unobserved. The post-apply read-back confirmed the deny. Both published OIDC smoke workflows passed, including their AWS role assumptions. Two roadmap truths still lack required live evidence.

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | `sh/verify-teardown.sh` exits zero on the empty account and non-zero for an untagged EBS orphan, checking all listed resource classes. | VERIFIED | The authorized `AWS_PROFILE=microservices-demo make test-verify-teardown` passed all three arms: clean baseline; the live sweep reported temporary volume `vol-0acc814aa94bd9019` as an orphan; cleanup deleted it and the sweep returned clean; invalid credentials returned an error verdict, never clean. The hard-gate reported all arms passed and the test volume removed. |
| 2 | Applying `layers/00-bootstrap` stores state in a versioned S3 bucket, exposes then removes `.tflock`, and uses no DynamoDB table. | VERIFIED | Versioning and the state object are present; no DynamoDB table was listed in `us-east-1`. During the 2026-10-13 read-only plan, Terraform reported acquiring and releasing the lock. A concurrent S3 `head-object` watcher observed the 260-byte `bootstrap/terraform.tfstate.tflock` object at 09:18:18–09:18:32 UTC and subsequent 404 responses after release. The plan reported no changes. |
| 3 | ~~A deliberate $1 resource yields a Cost Anomaly Detection alert within one day, and a zero-spend Budget alarm is configured.~~ | DROPPED 2026-10-26 | User decision; live CAD delivery not required. The $1 daily Budget email was observed 2026-10-15. | The October 15 email confirms delivery of the $1 daily actual-spend Budget alert ($2.21 actual). It does not verify a Cost Anomaly Detection event or its delivery/timing. |
| 4 | ~~Bootstrap spend is attributable by layer via `default_tags`, and idle cost is at most $5/month over a real billing period.~~ | DROPPED 2026-10-26 | User decision; billing-period evidence not required. Four `default_tags` keys were confirmed Active 2026-10-09. | Four `default_tags` keys are configured; the operator manually confirmed all four Active on 2026-10-09. Billing-period attribution is not complete, so neither per-layer actual attribution nor the real-period $5 ceiling is established. |
| 5 | GitHub Actions assumes a repository/branch-scoped AWS role through OIDC, with no long-lived access key in AWS or GitHub secrets. | VERIFIED | Live plan/apply/sweep trust subjects and audiences match their intended PR/develop claims. Root access-key count and IAM-user count are both zero; Actions, Dependabot, and Codespaces secret stores each contain zero secrets, no environments exist, and all four required repository variables exist. Plan-role PR run `38370179861` and apply-role `develop` push run `38370037745` both succeeded. The live apply guardrail also denies `iam:CreateServiceSpecificCredential`. |

**Score:** 3/3 remaining truths verified. Truths #3 and #4 were removed from the gate on 2026-10-26 at the user's direction (not passed, not overridden); status is `passed`.

### Scope Change (2026-10-26)

Truths #3 (Cost Anomaly Detection live delivery) and #4 (per-layer attribution and idle cost over a real billing period) can't be verified now and are no longer required. Cost guardrails and `default_tags` stay configured and statically tested. The fork-PR observation stays non-gating, covered by static workflow assertions only.

**Current feasibility (2026-10-15):** The daily Budget email was delivered organically and is now evidenced; do not create a cost event to test Cost Anomaly Detection, whose live delivery remains unverified. A complete billing period and management-account attribution view are not yet available, and no fork PR exists (one will not be created solely for this check). Keep Phase 1 at `human_needed` (3/5); this is a deferral, not a pass or override. The user has directed continuing Phase 2 within its explicitly authorized and plan-permitted scope; this does not clear Phase 1's gate.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `sh/verify-teardown.sh` | Account sweep and three-way verdict | PRESENT, substantive, wired | AWS responses flow into per-class findings/errors and JSON report. Fixture cases cover clean, orphan, credential error, pagination error, and regional unavailability. The 2026-10-13 live sweep returned clean for wired classes. |
| `sh/test-verify-teardown.sh` | Repeatable live clean/orphan/error proof | PRESENT, substantive, wired; live-tested | The authorized 2026-10-13 run passed clean-baseline, real untagged-EBS orphan detection, deletion/clean-after-delete, and invalid-credential error arms. Test volume `vol-0acc814aa94bd9019` was deleted and the final sweep returned clean. |
| `layers/00-bootstrap/main.tf`, `backend.tf` | Immortal, versioned S3 state backend | PRESENT, substantive, wired; live state and lock lifecycle observed | Source configures versioning, encryption, public access block, retention, `prevent_destroy`, and S3 backend. Live bucket `tfstate-072842666153-us-east-1` reports versioning Enabled and contains the current bootstrap state object. The native `.tflock` object was observed during a read-only Terraform plan and returned 404 after Terraform released the lock. |
| `layers/00-bootstrap/cost-guardrails.tf` | Budget, anomaly monitor, SNS alert path | PRESENT, substantive, wired | Dependencies and thresholds are implemented and statically tested; the daily Budget email was observed, while Cost Anomaly Detection delivery remains unverified. |
| `layers/00-bootstrap/oidc.tf` and workflows | Repository-scoped OIDC roles and smoke checks | PRESENT, substantive, published and live-tested | Live plan trust is `repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:pull_request`; apply and sweep trust are `repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:ref:refs/heads/develop`; all require audience `sts.amazonaws.com`. Plan-role PR run `38370179861` and apply-role push run `38370037745` both passed. The live apply guardrail matches source after the authorized update and read-back. CD-06 remains open and out of Phase 1. |
| Four Terraform layers and version inventory | Layer split and exact pins | PRESENT, substantive, wired | Exact pins/native locking are present; isolated credential-free validation passed. |
| `sh/verify-no-access-keys.sh` | Current AWS/GitHub credential audit | PRESENT, substantive, wired | Read-only checks observed root access-key count 0, IAM-user count 0, three GitHub secret stores with 0 secrets each, and no repository environments. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Teardown sweep | AWS APIs | `aws_json` and service `describe`/`list` calls | WIRED; live clean and orphan outcomes observed | Live baseline and post-cleanup sweeps returned clean; the authorized EBS hard-gate's live sweep reported the untagged test volume as an orphan. Fixture replay covers call shapes and parsing. |
| Teardown sweep | `.teardown-report.json` and exit status | Findings/error aggregation and serialization | WIRED | Bats proves clean=0, orphan=1, error=2, and no false clean verdict on errors. |
| `make bootstrap` | S3 remote state/lock | Local apply, output, generated backend, migration | WIRED; live state and lock lifecycle observed | Current S3 state and versioning are observed. A read-only plan acquired and released the native lock; the lock object's presence and post-release absence were observed concurrently. |
| Provider `default_tags` | Bootstrap resources and Cost Explorer | AWS provider tags followed by billing allocation | PARTIAL | Configuration and manual Active status are evidenced; real period attribution is not. |
| OIDC workflow | AWS role | Repository variable → `role-to-assume` → STS | PASS | Published plan-role PR run `38370179861` and apply-role `develop` run `38370037745` both assumed their scoped AWS roles successfully. |
| Budget/CAD resources | SNS email endpoint | Terraform references and topic policy | Budget delivery observed; CAD delivery not exercised | The October 15 email confirms daily Budget tripwire delivery; no Cost Anomaly Detection event was observed. |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Produces Real Data | Status |
|---|---|---|---|---|
| Teardown sweep | Service response JSON | AWS CLI APIs in script | Yes, with valid AWS credentials | FLOWING; current live sweep completed clean for wired classes |
| Teardown tests | Fixture JSON | Hand-authored AWS response fixtures through `stub-aws.bash` | Fixture data | FLOWING for local behavior, not a substitute for live proof |
| State backend | State and lock objects | S3 backend with `use_lockfile` | Yes, after Terraform operations | State/versioning observed; a no-change read-only plan acquired and released the native lock, with the in-flight object observed in S3. No separate in-flight observation during apply was made. |
| Cost alerts | Budget/CAD notifications | AWS services → SNS | Yes, on qualifying spend | Daily Budget email delivery observed on 2026-10-15; Cost Anomaly Detection event/delivery remains unverified. |
| OIDC smoke checks | Caller identity | GitHub OIDC token → STS | Yes, on workflow run | FLOWING; PR plan-role run `38370179861` and `develop` apply-role run `38370037745` both succeeded. Temporary PR #4 was closed without merging and its branch deleted. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Fixture-backed sweep, OIDC, tags, lock, version, decommission contracts | `bats tests/` | 56 passed, 0 skipped, 0 failed | PASS |
| Terraform validation, format, ShellCheck | `AWS_PROFILE=microservices-demo make validate` | All four layers validated; command completed successfully | PASS |
| Current account sweep | `AWS_PROFILE=microservices-demo make verify-teardown` | Account `072842666153`; clean for wired classes | PASS (point-in-time) |
| AWS identity and credential inventory | STS caller identity; IAM account summary and `list-users` | Expected account `072842666153`; root access-key count 0; IAM-user count 0 | PASS (current state) |
| GitHub credential configuration | Secret-store, environment, and repository-variable queries | Actions/Dependabot/Codespaces each 0 secrets; 0 environments; all four required variables exist | PASS (configuration state) |
| Remote state and lock lifecycle | S3 versioning, `head-object`, lock-prefix listing; DynamoDB `list-tables` in `us-east-1` | Versioning Enabled; bootstrap state object present; no DynamoDB table; in-flight `.tflock` observed, followed by 404 after release | PASS (read-only live observation) |
| Live teardown hard-gate | `AWS_PROFILE=microservices-demo make test-verify-teardown` | Clean baseline passed; `vol-0acc814aa94bd9019` detected as an orphan; volume deletion and clean recheck passed; invalid credentials returned error, never clean; final hard-gate passed | PASS (authorized; temporary test volume removed) |
| In-flight S3 lock lifecycle | `AWS_PROFILE=microservices-demo terraform -chdir=layers/00-bootstrap plan -input=false -detailed-exitcode` plus concurrent S3 `head-object` watcher | Terraform acquired/released the lock; watcher saw the 260-byte `.tflock` object at 09:18:18–09:18:32 UTC, then repeated 404 responses after release; plan reported no changes | PASS (read-only live observation) |
| Live OIDC trust and apply guardrail | IAM `get-role` / `get-role-policy`; saved Terraform plan/apply | Three trust subjects match intended claims; deployed deny policy includes `iam:CreateServiceSpecificCredential` | PASS (current IAM state) |
| Published OIDC smoke workflow runs | GitHub Actions run IDs `38370179861` and `38370037745` | PR plan-role and `develop` apply-role runs both completed successfully, including Terraform validation and AWS role assumption | PASS |
| Bootstrap Terraform plan | Explicitly authorized read-only operation | 0 add, 1 in-place change, 0 destroy; state lock released | PASS (inspection only; no apply) |
| Targeted bootstrap Terraform apply | Explicitly authorized saved-plan operation | 0 added, 1 changed, 0 destroyed; live IAM policy read-back confirmed the deny | PASS (single authorized policy update) |
| Valid `make nuke-bootstrap` | Not authorized | Not run | SKIPPED BY CONSTRAINT |
| Organic daily Budget alert | User-provided AWS Budgets email dated 2026-10-15 | `I0-daily-tripwire`; actual `$2.21` exceeded the `>$1.00` threshold | PASS (Budget delivery only; no deliberate test event) |

### Probe Execution

No phase-declared probe paths were found and no `probe-*.sh` files were present in the conventional project locations. Skipped, not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| COST-01 | 01-03, 01-06 | Idle cost at most $5/month over a real billing period | DROPPED | Real-billing-period verification dropped 2026-10-26. |
| COST-04 | 01-06 | Zero-spend budget and $1 anomaly alert | SATISFIED (configuration + Budget email) | The daily $1 Budget email was observed 2026-10-15; live Cost Anomaly Detection delivery test dropped 2026-10-26. |
| COST-05 | 01-01, 01-03, 01-06, 01-10 | Default tags and per-layer spend attribution | SATISFIED (configuration) | Four keys confirmed Active 2026-10-09; billing-period attribution check dropped 2026-10-26. |
| COST-08 | 01-03, 01-04, 01-05, 01-08, 01-09 | Dedicated account keeps the account-wide sweep safe | SATISFIED (current identity/inventory) | STS identity matches account `072842666153`; live sweep is clean for wired classes. |
| COST-09 | 01-01, 01-03 | Measured up/down times and real profile costs | DEFERRED | Phase 2 SC1 measures up/down time; Phase 5 SC5 measures core-profile cost. No Phase 1 up/down session exists to measure. |
| LIFE-05 | 01-02, 01-04, 01-05, 01-08, 01-09, 01-10 | Sweep fails for all required orphan classes | SATISFIED | The authorized live hard-gate passed clean baseline, detected test volume `vol-0acc814aa94bd9019` as an untagged EBS orphan, deleted it and confirmed a clean sweep, and proved invalid credentials return error rather than clean. |
| LIFE-07 | 01-01, 01-04 | Four lifetime-aligned Terraform layers | SATISFIED (repository) | Four layer directories and state-key conventions are present; static contracts pass. |
| LIFE-08 | 01-04 | Versioned S3 state, native locking, no DynamoDB table | SATISFIED | Live versioning/state object and no `us-east-1` DynamoDB table observed. A concurrent watcher saw the native `.tflock` object during the 2026-10-13 read-only plan and 404 responses after Terraform released it. |
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

### Human Verification

#### 1. Real orphan failure proof — completed 2026-10-13

**Evidence:** With separate authorization, `AWS_PROFILE=microservices-demo make test-verify-teardown` passed. The clean baseline passed; the live sweep identified `vol-0acc814aa94bd9019` as an available, detached, untagged 1 GiB `gp3` volume and the orphan arm passed. The script deleted the volume, waited for deletion, and the follow-up sweep returned clean. The invalid-credential arm returned exit 2 with an error verdict and never reported clean. Final output: `HARD GATE PASSED - verifier returned clean, orphan, and error outcomes.`
**Result:** LIFE-05 verified. The test volume was removed; no ongoing resource remains from this test.

#### 2. Remote state and lock lifecycle — completed 2026-10-13

**Evidence:** During `AWS_PROFILE=microservices-demo terraform -chdir=layers/00-bootstrap plan -input=false -detailed-exitcode`, Terraform printed `Acquiring state lock` and `Releasing state lock`; the plan reported no changes. A concurrent S3 `head-object` watcher returned the lock object's metadata (`LastModified: 2026-10-13T09:18:19+00:00`, `ContentLength: 260`) from 09:18:18 through 09:18:32 UTC, followed by 404 `Not Found` responses after release. This is a read-only live observation; no apply or destroy was run.
**Result:** Native lock acquisition and release observed. Together with the existing versioned-state and no-DynamoDB observations, LIFE-08 is verified.

#### 3. Cost alert delivery — DROPPED 2026-10-26 (no longer gating)

**Test:** Do not provision a $1 test resource or trigger a real cost event. Review a qualifying event only if it occurs organically or after separate authorization.
**Evidence (2026-10-15):** The user-provided AWS Budgets email identifies account `072842666153`, budget `I0-daily-tripwire`, a `>$1.00` actual threshold, and `$2.21` actual spend. This confirms delivery of the daily Budget notification through the configured email path.
**Result:** Daily Budget alert delivery verified. Cost Anomaly Detection alert delivery remains unverified; no artificial event was triggered.
**Why human:** Cost Anomaly Detection delivery and timing are external AWS behavior. Do not trigger a test event without separate authorization.

#### 4. Real billing period and tag attribution — DROPPED 2026-10-26 (no longer gating)

**Test:** Once a complete billing period and refresh are available, inspect per-layer attribution and idle cost in the management-account billing/Cost Explorer view. Do not use the member CLI for organization-level tag status.
**Expected:** Spend after activation is attributable by layer and idle cost is at most $5/month. Pre-activation resources remain unattributable because tags do not backfill.
**Why human:** A complete billing period and management-account access are required. The four keys were manually confirmed Active on 2026-10-09; this is not observed spend attribution.

#### 5. Fork pull-request fallback — non-gating (static assertions only)

**Test:** Observe the existing fallback only if an actual fork PR exists; do not create a fork solely for this check.
**Expected:** Credential-free validation runs and no AWS OIDC role assumption is attempted.
**Why human:** No fork exists. Static assertions prove workflow conditions, not a fork-triggered run.

This is an infrastructure/foundation phase; no artificial manual UI test is needed. These checks concern external AWS, billing, and OIDC behavior required by the roadmap.

### Gaps Summary

No source artifact is missing or a stub, and static workflow/sweep wiring remains present. Today's checks establish that the account is clean for wired sweep classes after the live EBS test, inspected credential/secrets stores are empty, the bootstrap state object is present in a versioned bucket, native S3 lock acquisition/release is observed, live OIDC trust conditions are scoped as intended, the live apply guardrail matches source, and both published OIDC smoke workflows passed. The daily Budget alert was delivered organically, but Cost Anomaly Detection delivery and complete billing-period attribution/idle cost still lack required evidence. Fork-PR fallback behavior also remains unobserved because no fork exists. The single-policy update was applied from the explicitly authorized saved plan; the temporary EBS test volume was deleted; valid bootstrap destruction and a deliberately triggered cost event were not performed under the user's constraints. As of 2026-10-26 the two unverifiable truths are dropped, so overall status is `passed`.

This report does not mark Phase 1 complete in `ROADMAP.md` or `STATE.md`.

---

_Historical report footer (superseded): 2026-10-13T10:03:35Z_
_Historical verifier: the agent (gsd-verifier)_

---
_Verified: 2026-10-27T04:19:31Z_
_Verifier: the agent (gsd-verifier)_
