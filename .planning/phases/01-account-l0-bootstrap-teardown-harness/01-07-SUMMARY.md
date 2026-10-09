---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 07
subsystem: auth
tags: [aws, iam, oidc, github-actions, terraform]

requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Remote S3 state bucket and cost guardrails for bootstrap.
provides:
  - GitHub OIDC provider with immutable-aware repository subjects.
  - Pull-request-only plan role and main-branch-only apply role.
  - Static trust-policy contracts and recorded repository metadata.
affects: [Phase 01-10 workflow integration, Phase 03 CI pipeline]

actuals:
  tokens: 3400
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - Exact StringEquals conditions for both GitHub OIDC subject and audience.
    - Scope S3 lock mutation permissions to the .tflock object suffix.
key-files:
  created:
    - layers/00-bootstrap/oidc.tf
    - .planning/phases/01-account-l0-bootstrap-teardown-harness/01-07-USER-SETUP.md
  modified:
    - layers/00-bootstrap/terraform.tfvars
    - tests/oidc_trust.bats
    - docs/RUNBOOK-account-setup.md

key-decisions:
  - "Use immutable GitHub OIDC subjects: repository creation date is 2026-09-23, after the 2026-07-15 cutover."
  - "Keep plan and apply subjects disjoint; scope plan-role S3 writes and deletes to .tflock only."
  - "Keep AdministratorAccess temporary, with explicit account and credential denies; Phase 10 replaces it using recorded CloudTrail activity."
  - "Do not publish an unredacted claim debugger workflow in this public repository."

patterns-established:
  - "OIDC trust policies use exact StringEquals checks for aud and a single trigger-specific sub."
  - "Broad apply permissions carry an explicit replacement phase and protective deny policy."

requirements-completed: [CD-05]
coverage:
  - id: D1
    description: GitHub OIDC provider and pull-request plan role use the ID-qualified subject, exact audience, and lock-file-scoped S3 access.
    requirement: CD-05
    verification:
      - kind: unit
        ref: tests/oidc_trust.bats#both trust policies require exact audience and subject conditions
        status: pass
      - kind: integration
        ref: AWS IAM get-role and get-role-policy checks for gha-terraform-plan
        status: pass
      - kind: other
        ref: terraform validate and terraform plan -detailed-exitcode
        status: pass
    human_judgment: false
  - id: D2
    description: The apply role trusts only the ID-qualified main-branch subject and denies account closure, billing administration, and long-lived credential creation without denying cost controls.
    requirement: CD-05
    verification:
      - kind: unit
        ref: tests/oidc_trust.bats#apply deny blocks account and credential administration
        status: pass
      - kind: integration
        ref: AWS IAM get-role and get-role-policy checks for gha-terraform-apply
        status: pass
    human_judgment: false
  - id: D3
    description: Static tests reject wildcard, prefix, set-operator, missing-condition, and shared-subject trust policy shapes.
    requirement: CD-05
    verification:
      - kind: unit
        ref: bats tests/oidc_trust.bats (10 tests, zero skips)
        status: pass
    human_judgment: false
  - id: D4
    description: The runbook and ignored Terraform inputs record the repository's immutable-subject metadata without exposing credentials.
    verification:
      - kind: manual_procedural
        ref: User-provided GitHub API metadata for owner ID, repository ID, and creation date; checked against the 2026-07-15 cutover
        status: pass
      - kind: integration
        ref: docs/RUNBOOK-account-setup.md section 7 and 01-07-USER-SETUP.md
        status: pass
    human_judgment: false

duration: 46 min
completed: 2026-10-09
status: complete
---

# Phase 1 Plan 7: GitHub OIDC Roles Summary

**GitHub Actions now has disjoint, ID-qualified plan and apply roles with lock-scoped state access and structural account safeguards.**

## Performance

- **Duration:** 46 min
- **Started:** 2026-10-09T02:48:00Z
- **Completed:** 2026-10-09T03:34:17Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Created the thumbprint-free GitHub OIDC provider and an immutable-aware subject builder using owner ID `82219047` and repository ID `1383184443`.
- Applied separate plan and apply roles: pull requests can use read-only access plus `.tflock` operations; only `main` can assume the broad apply role.
- Added explicit account, billing-configuration, and long-lived-credential denies while preserving Budgets and Cost Explorer access.
- Activated ten static trust tests and recorded the repository metadata and subject format in the setup runbook.

## Task Commits

Task 1 was the blocking metadata decision checkpoint and required no code commit. The user selected option A after supplying the GitHub API creation date and IDs.

1. **Task 2: OIDC provider and plan role with lock-scoped state access** - `e966550`
2. **Task 3: Apply role with scoped deny and static trust assertions** - `706ac02`

Plan metadata is committed with this summary and the GSD state/roadmap update.

## Files Created/Modified

- `layers/00-bootstrap/oidc.tf` - Provider, immutable subjects, both roles, trust documents, and permission policies.
- `layers/00-bootstrap/terraform.tfvars` - Owner and repository IDs; this file remains gitignored.
- `tests/oidc_trust.bats` - Ten active exact-trust and permission-scope contracts.
- `docs/RUNBOOK-account-setup.md` - Repository creation date, IDs, and immutable subject values.
- `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-07-USER-SETUP.md` - Completed metadata checkpoint record.

## Decisions Made

- Use ID-qualified subjects because the repository was created on 2026-09-23, after the immutable-claim cutover.
- Keep plan and apply trust disjoint and require exact matches for both `aud` and `sub`.
- Grant the plan role write/delete only on lock-file objects; never on Terraform state objects.
- Keep the administrator grant temporary, with explicit account and credential denies and a Phase 10 replacement.
- Do not run or publish an unredacted OIDC debugger in this public repository; the selected metadata-based checkpoint path is sufficient.

## Deviations from Plan

None. The user selected the plan's metadata-based option A. The recommended claim-debugger option B was not used because the repository is public.

## Issues Encountered

- The local shell lacked the GitHub CLI, so the user supplied the output of the plan's `gh api` metadata command.
- Initial intermediate test failures were resolved before Task 3 completion; the final suite passes all ten tests with zero skips.
- A Terraform output check initially omitted the AWS profile and was rerun successfully with `AWS_PROFILE=microservices-demo`.

## User Setup Required

Complete. See [01-07-USER-SETUP.md](./01-07-USER-SETUP.md). The owner and repository IDs are in the ignored `terraform.tfvars` file.

## Next Phase Readiness

- Both role ARNs and trust policies are live; Plan 01-10 can reference them when it adds workflows.
- AWS trust-policy configuration and permissions were verified live, but no GitHub Actions assume-role workflow exists yet; end-to-end token exchange remains for workflow integration.
- CD-05 remains pending until its shared Plan 01-10 coverage is complete.

## Self-Check: PASSED

- All plan acceptance criteria and live AWS trust/permission checks passed.
- `bats tests/oidc_trust.bats`: 10 passed, zero skipped.
- Terraform validate/fmt passed; detailed-exitcode plan reported no changes.
- The runbook and user-setup artifact record metadata-derived subjects and do not claim an observed JWT subject.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-09*