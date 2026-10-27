---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 08
type: execute
status: complete
completed_tasks: [02-08-01, 02-08-02]
blocked_tasks: []
requirements: [LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-06, NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02]
provides:
  - Mutation-free local acceptance preflight results
  - Explicit blank timing columns for all eight teardown actions
  - Recorded blocking Phase 1 human-needed precondition
affects: [phase-02-acceptance, cost-ledger, operator-runbook]
key-files:
  modified:
    - COSTS.md
  created:
    - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-08-SUMMARY.md
key-decisions:
  - "Phase 1 remains human_needed; only the explicitly authorized isolated Cloud Nuke fixture proof was performed, not lifecycle acceptance."
  - "Keep all live lifecycle measurements blank; local tests and validation are not AWS acceptance evidence."
  - "Cloud Nuke resource types remain report-only because the isolated proof required an extra marker and did not establish the committed Project-only scope or all cascade behavior."
verification:
  local:
    - "bats tests/phase2_lifecycle.bats: 48 passed, 0 failed"
    - "make test: 118 passed, 0 failed, 0 skipped"
    - "bats tests/static_contracts.bats: 26 passed, 0 failed after timing table update"
    - "AWS_PROFILE=microservices-demo make validate: all four Terraform layers, formatting, and ShellCheck passed"
    - "shellcheck sh/*.sh: passed"
  human_gate:
    phase_1_status: human_needed
    phase_1_score: 3/5
    live_acceptance: blocked
    cloud_nuke_fixture_proof: partial
    aws_mutation_performed: true
    partial_apply: true
    credential_status: reauthenticated
    lifecycle_or_cluster_operation_performed: false
duration: multi-session
completed: 2026-10-14
---

# Phase 02 Plan 08 Status

Plan 02-08 is **blocked at its human acceptance checkpoint**, not complete. The mutation-free preflight has been completed. The Phase 1 verification artifact and current project state both retain `human_needed` status (3/5 roadmap truths verified), so the plan's explicit precondition prohibits any live Phase 2 AWS operation.

## Task 1: Local Preflight

- `bats tests/phase2_lifecycle.bats`: 48 passed, 0 failed.
- `make test`: 118 passed, 0 failed, 0 skipped.
- `AWS_PROFILE=microservices-demo make validate`: all four Terraform layers passed; formatting and ShellCheck passed. No plan, apply, destroy, or lifecycle target was run.
- Read-only `AWS_PROFILE=microservices-demo AWS_REGION=us-east-1 make doctor` was run during the live-access preflight. It first blocked on the wrong kubectl pin and missing GNU timeout; after staging the verified kubectl and installing coreutils temporarily, it passed for account `072842666153` and region `us-east-1`.
- Repeated public-IP observations changed between requests (`101.99.12.77`, `104.28.254.73`, and user-observed nearby WARP egress addresses), so no single `/32` was accepted for the EKS endpoint.
- `bats tests/static_contracts.bats` after the ledger update: 26 passed, 0 failed.
- `shellcheck sh/*.sh`: passed.
- The repository file search found no application source files.
- `COSTS.md` has blank successful-run tables and now names the duration column for each of the eight teardown actions. No measurements were fabricated.
- `layers/10-infra/README.md` already documents the eight-versus-seven reconciliation and the two consecutive clean empty-cluster round-trip gate.

## Task 2: Live Acceptance

**Blocked.** `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-VERIFICATION.md` records `status: human_needed`, score 3/5. Remaining Phase 1 evidence includes live cost-alert delivery, complete billing-period attribution, and the fork pull-request fallback observation. Phase 1 status was not changed.

Three `make up` attempts were made with the approved two-entry `/32` allowlist. The first stopped during Terraform planning on an overlong generated IAM role prefix; the second stopped during planning on an invalid EKS module output reference. Neither began apply. The third passed planning and began apply, created multiple AWS resources, then failed because `module.karpenter.aws_iam_policy.controller[0]` exceeded AWS's 6,144-byte policy-size quota. No successful cluster readiness or lifecycle round was reached, and no duration was entered in `COSTS.md`.

At the time of the initial halt, the read-only remote-state listing could not complete because the AWS SSO token expired (`InvalidGrantException`), leaving the exact resource inventory and lock status unknown. The recovery update below records the subsequent reauthenticated, read-only inspection. Plan 02-07's unproven Cloud Nuke types remain report-only.

## Resume Condition

The state and AWS inventory inspection is complete, and the Karpenter policy-size failure has a locally validated fix. Phase 2 live acceptance remains blocked by Phase 1's `human_needed` status and the halted Plan 02-07 dependency. The approved operator CIDRs remain `113.190.44.94/32` and `101.99.12.77/32`; do not widen the endpoint boundary to accommodate rotating WARP egress. Record only successful complete lifecycle runs in `COSTS.md`. Do not proceed to application code until the two consecutive verifier-clean round-trips pass.

## Recovery Update (2026-10-15)

- AWS identity was reauthenticated for account `072842666153` in `us-east-1`.
- The remote `infra/terraform.tfstate` object is present, Terraform state lists the infrastructure resources, and no `infra/terraform.tfstate.tflock` object is present.
- The tagged L1 VPC `vpc-0dde207eb624a3151` exists. EKS cluster `microservices-demo` is `ACTIVE` at Kubernetes `1.34`; its system managed node group is `CREATE_FAILED` with `NodeCreationFailure`, while two backing `t4g.medium` instances are still running. The tracked NAT `t4g.nano` instance is also running.
- `sh/verify-teardown.sh` reports 59 outstanding findings. These include the active cluster, four security groups, six IAM roles, one log group, and three running instances; the account is not clean.
- Set `enable_inline_policy = true` on the pinned Karpenter module to address its documented managed-policy size limit. The focused Karpenter contract, all 27 `tests/static_contracts.bats` tests, and `terraform -chdir=layers/10-infra validate` pass.
- At the time of this recovery snapshot, no additional AWS resource mutation, Terraform apply/destroy, lifecycle operation, Cloud Nuke operation, or Kubernetes API operation was performed. No lifecycle timings were added.

## Isolated Cloud Nuke Proof Follow-up (2026-10-15)

- Mutation-free local preflight rerun: `bats tests/phase2_lifecycle.bats` passed 49 tests; `make test` passed 120 tests; `AWS_PROFILE=microservices-demo AWS_REGION=us-east-1 make validate` validated all four Terraform layers and passed formatting/ShellCheck. No AWS lifecycle or Terraform mutation command was run.
- The user authorized a narrowly scoped disposable EC2 tagged-target/untagged-control test despite Phase 1 remaining `human_needed`. No broader cleanup or lifecycle operation was authorized or run.
- Checksum-verified Cloud Nuke v0.52.0 used identical preview and execution filters: `--region us-east-1 --resource-type ec2 --newer-than 1h --include-tag 'Project=microservices-demo' --include-tag 'Phase2NukeProof=.+'`. Preview selected exactly `i-08ad82f3e1e6b80b5`; execution deleted only that target (1 found, 1 deleted, 0 failures). Untagged control `i-040ea9890807affbd` remained running and was then terminated by exact ID as test cleanup.
- Fresh EC2 inspection confirmed both fixtures terminated. The verifier's current `ORPHANS (63)` output lists three running EC2 resources: two EKS node-group instances and the existing NAT instance. It also lists the terminated tagged target ID in its separate `tagged` category. The reported attached EBS volume belongs to NAT; the previously reported fixture volume ID returned `InvalidVolume.NotFound`.
- The exact repository path `AWS_PROFILE=microservices-demo AWS_REGION=us-east-1 AWS_PAGER='' make nuke-project` passed account/region preflight, made no Cloud Nuke preview/deletion call, and returned exit 1 with 63 findings, including the terminated target ID in the `tagged` category. This is report-only behavior, not clean teardown acceptance.
- The fixture proof is partial: the extra `Phase2NukeProof` filter kept the live target set isolated, while the committed Project-only EC2 filter matches the existing NAT instance. The two running EKS node-group instances do not show that Project tag in their observed tags. EC2 therefore remains report-only. EKS node group remains `CREATE_FAILED` with `NodeCreationFailure`.
- No `make up`, `make down`, Terraform apply/destroy, node-group change, or Kubernetes operation was performed; lifecycle measurements remain blank and Phase 2 remains blocked. No verifier findings were cleaned up.

## Authorized Lifecycle Resume Attempt (2026-10-15)

- The user explicitly authorized full Phase 2 live acceptance despite Phase 1 remaining `human_needed`. The existing approved operator CIDRs remain `113.190.44.94/32` and `101.99.12.77/32`; neither was changed.
- `make doctor` passed when run with the previously checksum-verified kubectl v1.34.12 staged ahead of system kubectl v1.37.0. Account `072842666153`, region `us-east-1`, Terraform v1.16.4, and other doctor inputs passed.
- The current public egress reported by `checkip.amazonaws.com` was `104.28.222.76`, outside both approved CIDRs. The `make up` preflight therefore cannot pass. No CIDR was widened and no apply or lifecycle command was run.
- A read-only L1 Terraform plan with only the approved CIDRs returned `6 to add, 0 to change, 1 to destroy`: three managed add-ons, the inline Karpenter controller role policy, the system node group, and a replacement for the tainted NAT Auto Scaling Group. Terraform released the state lock. This is not an apply authorization for an unapproved egress; the NAT replacement and existing `CREATE_FAILED` node group remain pending.
- Resume condition: run from a trusted operator egress already covered by an approved CIDR, or obtain explicit approval for a stable revised CIDR before any provisioning. Do not use a rotating WARP address as an assumed stable `/32`. Phase 2 remains blocked; no timing or clean-round evidence was added.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Plan: 08 (blocked at human gate)*
*Updated: 2026-10-14*
## Live Acceptance (2026-10-26)

Task 2 passed with one round-trip; the operator reduced the gate from two consecutive round-trips to one and raised the `make down` limit to 1500s (25 minutes).

- `make up`: 908s, 88 resources added; cluster, system node group, and four add-ons ACTIVE.
- `make down`: 1162s, exit 0, verifier exit 0. Stages (s): 0 / 12 / 8 / 7 / 2 / 1 / 773 / 51. Recorded in `COSTS.md`.
- Fixes made during acceptance: `_destroy-layer` supplies a placeholder `operator_cidrs`; `make up` writes the kubeconfig; NAT moved to us-east-1b after a t4g.micro capacity failure in us-east-1a; the verifier ignores tag-index entries whose service API reports them gone; the S3 state probe uses a connect timeout with retries; destroys run with `-refresh=false`; kubectl pinned to v1.37.1.
- Teardown time is dominated by EKS managed node group deletion (494s) followed by cluster deletion (184s).
