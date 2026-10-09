---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 06
subsystem: cost-control
tags: [terraform, aws-budgets, cost-anomaly-detection, sns, cost-allocation]

requires:
  - phase: 01
    provides: Bootstrap layer, shared default tags, and remote state
provides:
  - Confirmed SNS email path with Budgets and Cost Anomaly Detection publish permissions
  - $5 monthly ceiling and $1 daily actual-spend tripwire
  - Immediate $1 service-dimension Cost Anomaly Detection subscription
  - Cost-alert resource tagging and documented alert cold-start behavior
affects: [bootstrap-layer, cost-guardrails, cost-allocation, plan-01-10]

actuals:
  tokens: 2961
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - Keep SNS publisher permissions and account-owner administration together in the replacement topic policy.
    - Use a deterministic daily actual-spend budget while anomaly detection learns per-service history.
    - Verify budget notification details through the dedicated notifications API, not describe-budgets.

key-files:
  created:
    - layers/00-bootstrap/cost-guardrails.tf
    - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-06-USER-SETUP.md
  modified:
    - COSTS.md
    - tests/static_contracts.bats

key-decisions:
  - "Use an unencrypted SNS topic with the two service publishers and the mandatory account-owner statement; topic-level KMS encryption breaks the budget alert path."
  - "Retain forecast alerts for later use, but rely on a daily actual $1 budget during the five-week budget forecast and ten-day anomaly detection cold starts."
  - "Use an immediate DIMENSIONAL/SERVICE anomaly monitor and SNS subscription; the account preflight found no existing managed monitor to import."
  - "Use strict GREATER_THAN thresholds and preserve the $1/$5 boundary semantics in comments and static tests."

patterns-established:
  - "All taggable L0 resources inherit Project, Layer, ManagedBy, and Environment from provider default_tags."
  - "Check Budget notifications with describe-notifications-for-budget and subscribers with describe-subscribers-for-notification."

requirements-completed: [COST-01, COST-04, COST-05]

coverage:
  - id: D1
    description: The unencrypted cost-alert topic preserves account-owner administration, allows both AWS alert publishers, and has a confirmed email subscription.
    requirement: COST-04
    verification:
      - kind: integration
        ref: AWS SNS get-topic-attributes policy check and KMS key check
        status: pass
      - kind: manual_procedural
        ref: AWS SNS list-subscriptions-by-topic confirmed-email check
        status: pass
    human_judgment: false
  - id: D2
    description: The $5 monthly ceiling excludes credits/refunds and has three forecast thresholds plus one actual threshold; the $1 daily tripwire uses a strict actual absolute-value threshold.
    requirement: COST-01
    verification:
      - kind: integration
        ref: AWS Budgets describe-budgets, describe-notifications-for-budget, and describe-subscribers-for-notification checks
        status: pass
      - kind: unit
        ref: tests/static_contracts.bats cost guardrail boundary contract
        status: pass
    human_judgment: false
  - id: D3
    description: Immediate anomaly alerts use a dimensional service monitor, one SNS subscriber, and a $1 absolute-impact threshold.
    requirement: COST-04
    verification:
      - kind: integration
        ref: AWS Cost Explorer get-anomaly-monitors and get-anomaly-subscriptions checks
        status: pass
    human_judgment: false
  - id: D4
    description: The topic, budgets, anomaly monitor, and anomaly subscription carry the four non-empty cost-allocation tag keys.
    requirement: COST-05
    verification:
      - kind: integration
        ref: AWS Resource Groups Tagging API topic check and Terraform state tag-map checks
        status: pass
    human_judgment: false

duration: 16h 21m
completed: 2026-10-09
status: complete
---

# Phase 1 Plan 06: Cost Guardrails Summary

**SNS-backed cost alerts with confirmed delivery, a $5 monthly ceiling, a $1 daily tripwire, and immediate service-level anomaly detection**

## Performance

- **Duration:** 16h 21m, including the overnight AWS authentication checkpoint
- **Started:** 2026-10-08T10:25:25Z
- **Completed:** 2026-10-09T02:46:25Z
- **Tasks:** 3/3
- **Files modified:** 4

## Accomplishments

- Created the `cost-alerts` SNS topic, three-statement policy, email subscription, and ARN output. The live policy contains both AWS publishers and the default account-owner statement; the topic has no KMS key.
- Added a $5 monthly budget with 50/80/100% forecast alerts and a 100% actual alert, plus a daily $1 actual-spend tripwire. Both route only through the SNS topic.
- Added an immediate Cost Anomaly Detection subscription over a dimensional service monitor with an absolute-impact threshold of `$1`.
- Documented strict threshold semantics and detector cold starts in `COSTS.md`, and added a static Bats contract for exact string thresholds and their boundaries.
- Confirmed the email subscription manually and verified the SNS and budget resources carry the expected tags.

## Task Commits

1. **Task 1: SNS topic, policy, and email subscription** - `07f9a16` (`feat`)
2. **Task 2: Budgets and anomaly monitor** - `9ae288c` (`feat`), `de846f5` (`test`)
3. **Task 3: Confirm the alert subscription** - human confirmation completed; evidence verified through AWS SNS and Resource Groups Tagging APIs.

## Files Created/Modified

- `layers/00-bootstrap/cost-guardrails.tf` - SNS alert path, two budgets, anomaly monitor/subscription, and topic output.
- `COSTS.md` - Updated the L0 budget model and documented the daily tripwire boundary and cold-start behavior.
- `tests/static_contracts.bats` - Pins exact string thresholds, strict `GREATER_THAN` comparisons, and boundary comments.
- `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-06-USER-SETUP.md` - Records the email confirmation setup and verification; status is complete.

## Decisions Made

- Preserve the SNS account-owner statement because `aws_sns_topic_policy` replaces the full policy; leave the topic unencrypted because KMS breaks AWS Budgets delivery.
- Keep forecast notifications despite their roughly five-week cold start, and use the daily actual budget as deterministic early coverage while Cost Anomaly Detection warms up.
- Use `DIMENSIONAL`/`SERVICE` with `IMMEDIATE` frequency for a single SNS subscriber. The read-only preflight found no existing AWS-managed service monitor, so no import was needed.
- Keep all limits and scalar thresholds as decimal strings in Terraform and state that `GREATER_THAN` excludes spend exactly at `$1.00` or `$5.00`.

## Deviations from Plan

None - the implementation follows the planned resource shapes and human checkpoint. A static Bats assertion was added to cover the plan's explicit threshold-boundary verification criterion.

## Authentication Gates

The initial default shell had no AWS credentials. No apply was attempted until the `microservices-demo` profile was authenticated and verified against the gitignored pinned account ID. All later Terraform and AWS CLI operations used that explicit profile.

## Issues Encountered

- `describe-budgets` does not return notification blocks; threshold and subscriber assertions therefore used `describe-notifications-for-budget` and `describe-subscribers-for-notification`.
- The Budget API omits `ThresholdType` for percentage notifications, so live checks asserted their type, operator, and numeric thresholds while the daily notification also asserted `ABSOLUTE_VALUE`.
- The actual Cost Anomaly Detection alert was not triggered; its ten-day per-service history requirement remains a deferred observation documented in `COSTS.md`.

## User Setup Required

Completed. The operator confirmed the SNS email subscription, and the live subscription list reports a confirmed endpoint. See [01-06-USER-SETUP.md](./01-06-USER-SETUP.md).

## Next Phase Readiness

Plan 01-07 can proceed. Its blocking task is to determine the repository's GitHub OIDC subject format before writing role trust policies. Cost-allocation key activation remains sequenced for Plan 01-10; the first real anomaly alert remains deferred until there is sufficient per-service history.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-09*
