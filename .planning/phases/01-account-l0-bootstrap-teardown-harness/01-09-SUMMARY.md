---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 09
subsystem: infrastructure
tags: [aws, bash, github-actions, credentials, teardown, bats]
requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Teardown verifier, AWS bootstrap account, GitHub OIDC roles, and fixture test harness.
provides:
  - Repeatable three-arm live teardown hard-gate test.
  - AWS and GitHub long-lived credential audit.
  - Explicit log-retention convention and static guard.
affects: [phase-01-closeout, phase-02-teardown-gate]
actuals:
  tokens: 3400
  tasks: 3
  commits: 3
tech-stack:
  added: []
  patterns:
    - Temporary resource tags identify test-created resources for signal-safe cleanup, then are removed before orphan detection.
    - GitHub CLI errors are distinct from empty secret-store results.
key-files:
  created:
    - sh/verify-no-access-keys.sh
    - docs/CONVENTIONS.md
  modified:
    - sh/test-verify-teardown.sh
    - Makefile
    - tests/static_contracts.bats
key-decisions:
  - "Store role ARNs as repository variables, not secrets; the ARN values are not secret material."
  - "Keep the log-retention convention guard-only in Phase 1 because no bootstrap resource emits CloudWatch logs natively."
requirements-completed: [LIFE-05, CD-05, COST-08]
coverage:
  - id: D1
    description: Three-arm teardown proof verifies clean, orphan, and verifier-error outcomes and removes its test volume.
    requirement: LIFE-05
    verification:
      - kind: integration
        ref: "AWS_PROFILE=microservices-demo make test-verify-teardown"
        status: pass
      - kind: integration
        ref: "test available EBS volume count is zero; AWS_PROFILE=microservices-demo make verify-teardown"
        status: pass
    human_judgment: false
  - id: D2
    description: AWS credential inventory and all GitHub secret stores are empty; plan and apply role variables are present.
    requirement: CD-05
    verification:
      - kind: integration
        ref: "AWS_PROFILE=microservices-demo make verify-no-keys"
        status: pass
    human_judgment: false
  - id: D3
    description: Terraform CloudWatch log-group resources require explicit retention, with a fixture proving the guard fails closed.
    requirement: COST-08
    verification:
      - kind: unit
        ref: "bats tests/static_contracts.bats"
        status: pass
    human_judgment: false
  - id: D4
    description: Cleanup trap removes a created volume after an interrupted test run.
    requirement: LIFE-05
    verification: []
    human_judgment: true
    rationale: The live test verified normal cleanup and a zero-volume postcondition, but a signal was not injected between volume creation and the first sweep.
duration: 15min
completed: 2026-10-09
status: complete
---

# Phase 1 Plan 09: Hard Gate and Credential Proof

**The teardown verifier now has live clean, orphan, and error-path evidence, alongside repeatable credential checks and a log-retention guard.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-10-09T08:46:12Z
- **Completed:** 2026-10-09T09:01:09Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Made the teardown hard-gate script executable and corrected its EBS creation/recovery path. It tags the volume at creation for interruption recovery, removes that tag before the sweep, confirms the volume ID in the orphan report, and exercises clean, orphan, and invalid-credential outcomes.
- Added `make verify-no-keys` and a fail-closed audit for the root key count, every IAM user, the credential report, Actions/Dependabot/Codespaces/environment secret stores, and required repository variables. Confirmed no active AWS keys or GitHub secrets; populated the two role ARN variables from Terraform outputs.
- Documented five infrastructure conventions and added a comment-aware log-group retention guard, including a fixture that proves missing retention is reported.

## Task Commits

1. **Task 1: Three-arm teardown hard-gate evidence** - `3e8820b` (`fix`)
2. **Task 2: AWS and GitHub credential proof** - `91149f6` (`feat`)
3. **Task 3: Log-retention convention and guard** - `406090a` (`test`)

## Files Created/Modified

- `sh/test-verify-teardown.sh` - Fixed ShellCheck findings, executable mode, and tag-based recovery for the live EBS test.
- `sh/verify-no-access-keys.sh` - Added AWS and GitHub credential inventory with distinct tool-failure handling.
- `Makefile` - Added the `verify-no-keys` target; preserved the pre-existing validation-target change.
- `docs/CONVENTIONS.md` - Recorded the five infrastructure conventions and rationale.
- `tests/static_contracts.bats` - Added the CloudWatch retention guard and its positive/negative fixture checks.

## Decisions Made

- Use a unique temporary EC2 tag to find a created volume if interruption occurs before its ID is captured; remove the tag before running the sweep so the test still proves untagged-volume detection.
- Keep GitHub role ARNs in repository variables, not secret stores.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AWS CLI does not support `ec2 create-volume --description`**
- **Found during:** Task 1 (three-arm hard-gate test)
- **Issue:** The original script's create command exited before creating the test volume.
- **Fix:** Added a unique tag at creation, used it as the cleanup recovery key, and removed it before orphan detection.
- **Files modified:** `sh/test-verify-teardown.sh`
- **Verification:** ShellCheck, `bash -n`, and all three live arms passed; post-run volume count was zero and the verifier was clean.
- **Committed in:** `3e8820b`

**2. [Rule 2 - Missing Critical] The hard-gate script was not executable and had ShellCheck warnings**
- **Found during:** Task 1
- **Issue:** Make could not invoke the script, and four `SC2155` warnings masked command-substitution statuses.
- **Fix:** Set executable mode and split assignments from `readonly` declarations.
- **Files modified:** `sh/test-verify-teardown.sh`
- **Verification:** ShellCheck and `bash -n` passed; the Make target completed successfully.
- **Committed in:** `3e8820b`

---

**Total deviations:** 2 auto-fixed (one bug, one missing-critical fix). **Impact:** Both were required to run the planned verification; scope stayed within Plan 01-09.

## Issues Encountered

- The local GSD initializer could not load because `.github/gsd-core/bin/lib/command-roster.cjs` imports missing `sh/fix-slash-commands.cjs`. Execution continued inline using the checked-in workflows and plan; unrelated GSD runtime changes were left untouched.
- `make validate` initially lacked an AWS profile. Rerunning with `AWS_PROFILE=microservices-demo` passed.
- Required role ARN repository variables were absent. They were added from the existing Terraform outputs; no secret values were introduced.

## Verification

- `shellcheck sh/test-verify-teardown.sh sh/verify-no-access-keys.sh`: passed.
- `bash -n sh/test-verify-teardown.sh sh/verify-no-access-keys.sh`: passed.
- `AWS_PROFILE=microservices-demo make test-verify-teardown`: all three arms passed.
- Zero available EBS volumes after the live test; `AWS_PROFILE=microservices-demo make verify-teardown`: clean.
- `AWS_PROFILE=microservices-demo make verify-no-keys`: passed; root and IAM-user key checks, credential report, all secret stores, and both repository variables verified.
- `AWS_PROFILE=microservices-demo make validate && bats tests/`: Terraform validation passed in all four layers; 49 Bats tests passed with zero skips.

## User Setup Required

None. The two non-secret role ARN repository variables were populated during this plan.

## Next Phase Readiness

Plan 01-09 is complete. Plan 01-10 remains before Phase 1 can close. The signal-interruption cleanup path is implemented but was not live-tested; this remains an explicit verification item.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-09*
