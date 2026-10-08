---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 03
subsystem: cost-management
tags: [aws-organizations, cost-explorer, aws-budgets, pricing, runbook]
requires:
  - phase: 01
    provides: Pinned Terraform layers, account preflight, and project cost constraints
provides:
  - Member-account setup runbook with management-account billing boundaries
  - Dated us-east-1 AWS list-price table and L0 idle-cost model
  - Documented budget/CAD cold-start windows and deferred billing observations
affects: [phase-1-bootstrap, phase-1-cost-guardrails, aws-account-operations]
actuals:
  tokens: 9268
  tasks: 4
  commits: 8
tech-stack:
  added: []
  patterns: [date-stamped price provenance, management/member account separation, conditional root credential checks]
key-files:
  created:
    - docs/RUNBOOK-account-setup.md
    - COSTS.md
  modified:
    - .planning/PROJECT.md
    - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md
    - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-03-PLAN.md
key-decisions:
  - "Amend D-03 to use the user's newly created dedicated AWS Organizations member account; keep management/payer outside Terraform."
  - "Use a DIMENSIONAL SERVICE anomaly monitor in the member account; linked-account monitors remain management-account-only."
  - "Cost Explorer and organization cost-allocation tag management are management-account controls; the member sees only its own cost data."
  - "Treat absent member root credentials as compliant with centralized Organizations root management; require MFA only if root credentials exist."
patterns-established:
  - "Use a member-side Cost Explorer query to prove member data visibility; do not gate on the management-only cost-allocation-tags API."
  - "Document organization-payer list-price caveats without placing account IDs or alert addresses in tracked files."
requirements-completed: [COST-01, COST-05, COST-08, COST-09]
coverage:
  - id: D1
    description: Dated us-east-1 AWS pricing table, Phase 1 L0 idle model, alert cold-start windows, and non-gating T3 observation ledger.
    requirement: COST-01
    verification:
      - kind: other
        ref: "COSTS.md required service-row, cold-start, T3, headroom, and provenance acceptance checks"
        status: pass
      - kind: other
        ref: "grep-based COSTS.md unsourced-dollar scan"
        status: pass
    human_judgment: false
  - id: D2
    description: Seven-step account runbook explains member/management billing ownership, pinning, no-backfill tags, subscription confirmation, and OIDC claim recording.
    requirement: COST-08
    verification:
      - kind: other
        ref: "docs/RUNBOOK-account-setup.md seven numbered steps and fenced verification commands"
        status: pass
      - kind: integration
        ref: "aws ce get-cost-and-usage --profile microservices-demo --time-period Start=2026-10-06,End=2026-10-08 --granularity DAILY --metrics UnblendedCost"
        status: pass
      - kind: manual_procedural
        ref: "User confirmed member IAM Billing access in console; member IAM toggle has no API readback."
        status: pass
    human_judgment: true
    rationale: Member Billing console access is controlled by a root-only account setting that has no API readback; the user confirmed the setting, while member Cost Explorer access is independently verified by API.
  - id: D3
    description: Account trust anchor and root credential posture are verified without creating account resources.
    requirement: COST-08
    verification:
      - kind: integration
        ref: "aws sts get-caller-identity --profile microservices-demo; .aws-account-id equality and git check-ignore"
        status: pass
      - kind: integration
        ref: "aws iam get-credential-report root row: no password, access keys, or signing certificates"
        status: pass
    human_judgment: false
duration: 1h 14m
completed: 2026-10-08
status: complete
---

# Phase 1 Plan 03: Account Runbook and Cost Model Summary

**Dedicated Organizations member-account runbook and dated us-east-1 pricing model with $4.99 L0 idle headroom**

## Performance

- **Duration:** 1h 14m
- **Started:** 2026-10-08T14:40:37+07:00
- **Completed:** 2026-10-08T15:54:27+07:00
- **Tasks:** 4/4
- **Files modified:** 8, including planning/checkpoint metadata

## Accomplishments

- Recorded the user's approved D-03 change to a newly created dedicated AWS Organizations member account, preserving the management account/payer outside Terraform.
- Authored a seven-step setup runbook that distinguishes management-account Cost Explorer/tag controls from member-account cost visibility, and keeps account identifiers out of tracked documentation.
- Added dated us-east-1 price provenance, a 13-line L0 idle model totaling about $0.01/month, cold-start windows, and three non-gating deferred observations in `COSTS.md`.

## Task Commits

1. **Task 1: Confirm the permanent AWS account trust anchor** - decision recorded in `.planning/PROJECT.md` and phase context; no separate task code commit.
2. **Task 2: Author account setup runbook** - `0d74d51` (`docs`).
3. **Task 3: Complete console-only account prerequisites** - member identity/pin and read-only checks passed; console confirmation was user-reported. Gate adaptations: `643e01a` and `6b7e3ed` (`docs`).
4. **Task 4: Author COSTS.md** - `92127fe` (`docs`).

Checkpoint/state commits during the plan: `a3e97c5`, `da932eb`, `715e309`, `d74252e`.

## Files Created/Modified

- `docs/RUNBOOK-account-setup.md` - member account pin, root access, billing access, Cost Explorer, future tag activation, SNS email confirmation, and OIDC claim-format steps.
- `COSTS.md` - bulk-API prices with provenance, L0 idle estimate, budget/CAD timing, T3 ledger, and Phase 2 measurement placeholder.
- `.planning/PROJECT.md`, `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md`, and `01-03-PLAN.md` - approved account-model and root-access gate amendments.

## Decisions Made

- The user explicitly replaced D-03's standalone-account assumption with a newly created, dedicated Organizations member account. Its ID remains only in gitignored `.aws-account-id`.
- The management account owns consolidated billing, organization-level Cost Explorer enablement, cost-allocation tag management, and centralized root access. The member account can inspect only its own Cost Explorer data.
- Member Cost Anomaly Detection uses a `DIMENSIONAL` `SERVICE` monitor. The management account's `LINKED_ACCOUNT` monitor is not part of this member-account stack.
- Cost-allocation tag activation is deferred to plan 01-10 after the first tagged apply; it is not attempted from the member account.
- The member credential report contains no root password, access keys, or signing certificates. Under centralized root management, `AccountMFAEnabled=0` is expected; do not create root credentials merely to make that flag 1.

## Deviations from Plan

### User-Authorized Account Scope Change

**1. Replace standalone-account D-03 with a dedicated Organizations member account**
- **Found during:** Task 1 (account trust-anchor checkpoint)
- **Issue:** The user's selected account was a newly created Organizations member, contradicting the original standalone/no-payer D-03.
- **Resolution:** The user explicitly authorized the deviation. Updated D-03, D-04 and D-25 context, added the account/billing constraint to PROJECT.md, and revised the runbook and task-3 checkpoint. Management/payer stays outside Terraform.
- **Verification:** Read-only STS identity matched the checkpoint; member Cost Explorer query returned estimated zero usage; AWS documentation was checked for CE visibility, tag-manager scope, Budgets, anomaly monitors, and Organizations root management.
- **Committed in:** `0d74d51`, `643e01a`, `6b7e3ed`.

**2. Make root MFA conditional on member root credentials**
- **Found during:** Task 3 (account prerequisite verification)
- **Issue:** The initial plan required `AccountMFAEnabled=1`, but AWS Organizations-created member accounts can have root credentials centrally removed, making `0` expected.
- **Resolution:** Updated the runbook, PROJECT.md, context, and checkpoint to inspect the root row in the IAM credential report: absent credentials are compliant; if credentials exist, require MFA. The report showed no password, access keys, or signing certificates.
- **Verification:** Exact runbook credential-report command passed and reported `root_credentials_present: false`.
- **Committed in:** `6b7e3ed`.

---

**Total deviations:** 2, both explicitly user-authorized or required to match the approved account architecture and AWS Organizations security model.
**Impact on plan:** Account onboarding and billing controls are now correct for the selected member account; Terraform still does not manage Organizations resources.

## Issues Encountered

- The initially attempted member `ce list-cost-allocation-tags` call was denied because AWS reserves organization cost-allocation tag management for the management account. The runbook/checkpoint were corrected to use member `ce get-cost-and-usage` for data access and reserve tag activation for management-account work in plan 01-10.
- AWS CLI initially returned `NoCredentials`. The user configured the `microservices-demo` profile; subsequent STS, Cost Explorer, and IAM credential-report checks passed.
- The Billing console IAM-access toggle has no direct API readback. The user confirmed it was enabled; member Cost Explorer reads are independently verified.

## User Setup Required

None pending for this plan. Root credentials are centrally absent, and the user confirmed member Billing console access. The future cost-allocation tag activation requires the Organizations management account and is tracked under plan 01-10.

## Next Phase Readiness

Plan 01-04 can proceed with a verified member account, matching ignored account pin, and documented management/member boundaries. Pricing provenance and the L0 idle model are ready for plan 01-06; tag activation remains deliberately deferred until the state bucket's tags surface in the management account.

## Self-Check: PASSED

- All 4 plan tasks are complete; the account checkpoint and member-account console setup were resolved.
- `COSTS.md` required price rows, headroom, cold-start windows, T3 rows, and provenance checks pass.
- Runbook has seven numbered steps with verification commands, explicitly handles member-account access and management-only tag controls, and contains no account ID or alert address.
- `make validate` passes across all four Terraform layers; `bats tests/` passes (32 cases, with only the intentional 01-04/01-07 skips).
- The member root credential report shows no root credentials; no AWS infrastructure resources were created.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-08*