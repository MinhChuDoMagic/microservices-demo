---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 05
subsystem: tests
tags: [bats, aws-fixtures, lifecycle, teardown, test-harness]
requires:
  - phase: 02-ephemeral-infrastructure-drain-scripts
    provides: Shared lifecycle drains and fail-closed EKS/AWS state decisions from plan 02-04
provides:
  - Opt-in sequential AWS response replay with operation-specific persistent call counters
  - Scenario manifest for EKS, ELBv2, EC2, EBS, transient errors, malformed data, and absence
  - Fixture-driven pending-to-terminal and failed-drain teardown contracts
affects: [02-06, 02-08, lifecycle, test-harness]
actuals:
  tokens: 6971
  tasks: 2
  commits: 3
tech-stack:
  added: []
  patterns: [explicit scenario opt-in, per-operation response sequences, fail-closed missing response, counter reset by fresh temporary stub]
key-files:
  created:
    - tests/fixtures/aws/phase2-lifecycle-sequences.json
  modified:
    - tests/helpers/stub-aws.bash
    - tests/harness_selftest.bats
    - tests/fixtures/aws/README.md
    - tests/phase2_lifecycle.bats
key-decisions:
  - "Sequence mode requires an explicit scenario and manifest; ordinary raw fixture lookup remains unchanged when not enabled."
  - "Each sequence response is either an AWS-shaped JSON object or an explicit stderr/nonzero-exit error envelope."
  - "Counters persist across AWS shim processes within a stub directory; starting a new directory resets them so retries begin at response one."
  - "Missing scenarios, operations, responses, or invalid envelopes fail with exit 98 and never fall through to static fixtures."
patterns-established:
  - "Every asynchronous drain transition is tested with separate pending and terminal AWS API responses and recorded call counts."
  - "Lifecycle negative paths use the shared AWS stub and retain independent kubectl/Terraform fakes."
requirements-completed: [LIFE-03, LIFE-04]
coverage:
  - id: D1
    description: Existing raw fixture behavior, precedence, and argv logging remain unchanged
    requirement: LIFE-04
    verification:
      - kind: unit
        ref: "tests/harness_selftest.bats#replays a JSON fixture verbatim and records full argv including region"
        status: pass
      - kind: unit
        ref: "tests/harness_selftest.bats#prefers an error fixture over a JSON fixture"
        status: pass
    human_judgment: false
  - id: D2
    description: Ordered sequences advance, reset, preserve errors, and fail closed on missing responses
    requirement: LIFE-04
    verification:
      - kind: unit
        ref: "tests/harness_selftest.bats#sequence mode advances the response for repeated AWS operations"
        status: pass
      - kind: unit
        ref: "tests/harness_selftest.bats#sequence counters reset with a new per-test stub directory"
        status: pass
      - kind: unit
        ref: "tests/harness_selftest.bats#sequence error responses preserve stderr and exit status"
        status: pass
      - kind: unit
        ref: "tests/harness_selftest.bats#a missing scenario operation response fails closed"
        status: pass
    human_judgment: false
  - id: D3
    description: All three drains wait for AWS terminal absence and failed states never reach Terraform destroy
    requirement: LIFE-03
    verification:
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#Ingress drain waits for ELBv2 load balancers and target groups to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#NodePool drain waits for tagged Karpenter instances to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#PVC drain waits for PVC-owned EBS volumes to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a fresh teardown retry replays the first pending AWS responses"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a failed NodePool drain stops make down before Terraform destroy"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a failed PVC drain stops make down before Terraform destroy"
        status: pass
    human_judgment: false
duration: multi-session
completed: 2026-10-14
status: complete
---

# Phase 02 Plan 05 Summary

**The AWS test harness can now replay explicit state transitions, proving drains wait for AWS rather than trusting Kubernetes requests**

## Performance

- **Duration:** Multi-session execution
- **Started:** Not recorded; resumed from Phase 2 execution
- **Completed:** 2026-10-14
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added an opt-in `STUB_AWS_SEQUENCE_SCENARIO` plus `STUB_AWS_SEQUENCE_FIXTURE` mode to the shared AWS shim without changing default raw fixture resolution.
- Added persistent service/operation call counters in the temporary stub directory; each invocation selects exactly one ordered response.
- Added explicit AWS-shaped JSON and stderr/nonzero-exit response envelopes. Missing scenario data and invalid entries fail closed with exit 98.
- Added scenarios for Ingress ELBv2, Karpenter EC2, PVC EBS, EKS statuses, ResourceNotFound, authorization errors, transient retry/saturation, and malformed data.
- Migrated transition and recovery tests to shared fixtures; assertions verify operation counts, pending-to-absent polling, fresh-run counter reset, and stop-before-destroy behavior.
- Documented the separation between raw one-response fixtures and the sequence manifest.

## Task Commits

1. **Task 1 RED: Specify sequenced AWS fixture replay** - `15f25cc` (`test`)
2. **Task 1 GREEN: Add opt-in AWS response sequences** - `3c69174` (`feat`)
3. **Task 2: Exercise drain state sequences** - `7c6a710` (`test`)

## Files Created/Modified

- `tests/helpers/stub-aws.bash` - Opt-in ordered responses, persistent call counts, explicit errors, and fail-closed missing response handling.
- `tests/fixtures/aws/phase2-lifecycle-sequences.json` - AWS response transitions and error/state scenarios.
- `tests/fixtures/aws/README.md` - Sequence envelope and counter/reset contract.
- `tests/harness_selftest.bats` - Legacy behavior, advance/reset, error propagation, and missing scenario assertions.
- `tests/phase2_lifecycle.bats` - Shared-fixture transition and teardown-boundary coverage.

## Decisions Made

- Static raw fixtures remain the default; sequence replay activates only when both scenario and manifest are explicitly provided.
- A response sequence is consumed once, never held on its last response, and missing data is an error rather than a clean absence.
- A fresh temporary stub directory is the explicit D-05 retry boundary and resets every operation counter.
- The sequence envelope separates API response bodies from AWS CLI errors so the drains exercise distinct stdout and stderr paths.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- The initial sequence tests failed against the unchanged fixture shim as expected; the opt-in implementation made them pass without altering existing raw fixture tests.
- No AWS API, kubectl cluster, Terraform apply/destroy, or live resource mutation was used.

## User Setup Required

None.

## Next Phase Readiness

Plan 02-05 is locally complete. Shared scenario fixtures now cover the three asynchronous drains and state/error boundaries. Continue with the next Phase 2 plan; live acceptance remains blocked on the Phase 1 human gate.

## Self-Check: PASSED

- `make test` passed all 109 Bats tests.
- `git diff --check 73e1ad2..HEAD` passed.
- `bash -n tests/helpers/stub-aws.bash` passed.
- `jq empty tests/fixtures/aws/phase2-lifecycle-sequences.json` passed.
- Editor diagnostics reported no errors in the changed files.
- No AWS mutation or live cluster operation was run.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Plan: 05*
*Completed: 2026-10-14*