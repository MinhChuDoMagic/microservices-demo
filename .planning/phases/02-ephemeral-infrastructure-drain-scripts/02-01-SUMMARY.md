---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 01
subsystem: infra
tags: [aws, terraform, teardown, bats, bash, python]

requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Generated S3 backend config, teardown verifier, and AWS fixture harness
provides:
  - Fail-closed eight-stage empty-stack teardown through make down
  - Ephemeral-only state lookup and destroy helpers
  - Fixed 900-second monotonic process-group deadline
  - Lifecycle and static contract coverage
affects: [phase-02-drain-plans, teardown, lifecycle-testing]

actuals:
  tokens: 4718
  tasks: 2
  commits: 5

tech-stack:
  added: [Python standard-library subprocess timeout runner]
  patterns: [Fail closed before destroy when cluster state is present or unknown, Atomic teardown lock, Process-group deadline with monotonic clock]

key-files:
  created:
    - sh/down.sh
    - sh/run-down-with-deadline.py
  modified:
    - Makefile
    - tests/phase2_lifecycle.bats
    - tests/static_contracts.bats

key-decisions:
  - "Use a standard-library Python wrapper because macOS lacks GNU timeout; keep the 900-second monotonic deadline fixed and non-overridable (D-06)."
  - "Reject teardown before Terraform destroy whenever cluster state is present or uncertain; retries begin at stage one (D-04, D-05)."
  - "Keep daily destroy targets limited to 30-gitops, 20-data, and 10-infra; never include bootstrap."

requirements-completed: [LIFE-02, LIFE-03, LIFE-04, LIFE-06]

coverage:
  - id: D1
    description: "make down performs the ordered empty-stack teardown and preserves verifier outcomes."
    requirement: LIFE-02
    verification:
      - kind: integration
        ref: tests/phase2_lifecycle.bats#make down runs through the deadline runner without AWS side effects
        status: pass
      - kind: unit
        ref: tests/phase2_lifecycle.bats#the verifier orphan result remains exit 1
        status: pass
      - kind: unit
        ref: tests/phase2_lifecycle.bats#the verifier error result remains exit 2
        status: pass
    human_judgment: false
  - id: D2
    description: "Unknown or active cluster state cannot reach Terraform destroy."
    requirement: LIFE-04
    verification:
      - kind: unit
        ref: tests/phase2_lifecycle.bats#a present infrastructure state fails closed before any destroy
        status: pass
      - kind: unit
        ref: tests/phase2_lifecycle.bats#an unknown state lookup fails closed before any destroy
        status: pass
    human_judgment: false
  - id: D3
    description: "The full make down operation is bounded by one fixed monotonic deadline and excludes bootstrap state."
    requirement: LIFE-06
    verification:
      - kind: unit
        ref: tests/static_contracts.bats#daily teardown has one fixed deadline and only ephemeral state keys
        status: pass
    human_judgment: false

duration: 21 min
completed: 2026-10-14
status: complete
---

# Phase 2 Plan 1: Empty-Stack Teardown Summary

**A fail-closed eight-stage `make down` tracer with a fixed 900-second monotonic deadline and ephemeral-only destroy boundary.**

## Performance

- **Duration:** 21 min
- **Started:** 2026-10-14T06:33:58Z
- **Completed:** 2026-10-14T06:54:59Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Implemented the ordered teardown stages and blocks destroy until state is known and every required drain is proven.
- Added a portable Python standard-library runner that terminates the entire child process group at the fixed deadline and propagates normal child exit codes.
- Added lifecycle, static deadline, lock, state-key, and bootstrap-exclusion contracts.

## Task Commits

1. **Task 1: Tracer — empty-stack teardown through the verifier** - `4336378` (implementation); TDD tests: `4959e8d`, `70d73e8`
2. **Task 2: Lock the lifecycle entry-point and layer boundary contracts** - `16a4994` (test)

**Plan metadata:** pending

## Files Created/Modified

- `sh/down.sh` - Ordered, locked, fail-closed teardown orchestration.
- `sh/run-down-with-deadline.py` - Fixed monotonic timeout and process-group cleanup.
- `Makefile` - Public `down` entrypoint and exact ephemeral state helpers.
- `tests/phase2_lifecycle.bats` - Lifecycle failures, exit propagation, idempotence, and entrypoint integration.
- `tests/static_contracts.bats` - Deadline and layer-boundary assertions.

## Decisions Made

- Used Python's standard library because this macOS environment has neither `timeout` nor `gtimeout`; the timeout remains fixed at 900 seconds.
- Applied D-04, D-05, and D-06: failed drains stop before destroy, reruns restart from the first stage, and the single monotonic deadline covers the whole invocation.

## Deviations from Plan

**1. Portable deadline implementation**
- **Found during:** Task 1 (empty-stack teardown)
- **Issue:** GNU `timeout` utilities are unavailable on the target macOS environment.
- **Fix:** Added a Python standard-library wrapper using `time.monotonic()`, a new process session, and TERM/KILL process-group cleanup.
- **Files modified:** `Makefile`, `sh/run-down-with-deadline.py`, `tests/phase2_lifecycle.bats`, `tests/static_contracts.bats`
- **Verification:** Focused lifecycle/static tests and full suite passed; Python syntax and Pylance diagnostics were clean.
- **Committed in:** `4336378`, `16a4994`

**Total deviations:** 1 auto-fixed (environment portability)
**Impact on plan:** Preserves the required fixed deadline and timeout semantics without adding a dependency.

## Issues Encountered

- The first multi-file patch did not create the runner file; added it separately and validated it before continuing.
- Final full Bats suite passed 74/74. `AWS_PROFILE=microservices-demo make validate` passed all Terraform layers, format checks, and ShellCheck. `git diff --check` passed.
- No live AWS mutations were performed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for plan 02-02's local implementation work. The Phase 1 verification remains `human_needed`; no live Phase 2 AWS mutation or final acceptance should proceed until that gate is resolved.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Completed: 2026-10-14*