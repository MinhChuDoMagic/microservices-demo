---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 06
subsystem: infra
tags: [bash, gnu-timeout, bats, terraform, teardown]

requires:
  - phase: 02-05
    provides: Tested Ingress, NodePool, and PVC drains plus Make-owned layer helpers
provides:
  - Fixed 900-second process-group deadline for teardown
  - Shared elapsed-time origin, bounded transient AWS retries, and timeout-tool preflight
  - Eight-action teardown contract and successful-only timing ledger schema
affects: [phase-02 acceptance gate, COST-09, lifecycle operators]

actuals:
  tokens: 5044
  tasks: 3
  commits: 7
commits: 7
plan_head_before: bd1b8b1ce6961026cff552a2333f285394886c45

tech-stack:
  added: [GNU coreutils timeout]
  patterns: [fixed outer process-group deadline, shared Bash elapsed origin, successful-only timing records]

key-files:
  created: [.planning/phases/02-ephemeral-infrastructure-drain-scripts/02-06-SUMMARY.md]
  modified: [Makefile, sh/down.sh, sh/lifecycle-common.sh, sh/doctor.sh, tests/phase2_lifecycle.bats, tests/static_contracts.bats, COSTS.md, layers/10-infra/README.md]
  deleted: [sh/run-down-with-deadline.py]

key-decisions:
  - "Use GNU timeout or gtimeout as the single hard cutoff; retain 900 seconds as a fixed, non-overridable budget."
  - "Use Bash SECONDS for diagnostics and boundary logic; only the external timeout enforces stuck-process termination."
  - "Publish down timing only after verifier exit 0, and keep measured-run tables blank until actual successful runs exist."

patterns-established:
  - "Make remains the sole owner of Terraform backend initialization and exact layer state keys."
  - "Drain failures stop before destroy; a fresh invocation resumes from action one after remediation."

requirements-completed: [LIFE-02, LIFE-03, LIFE-04, LIFE-06]
coverage:
  - id: D1
    description: "Fixed teardown deadline, compatible timeout preflight, and bounded transient retry behavior"
    requirement: LIFE-02
    verification:
      - kind: unit
        ref: "bats tests/phase2_lifecycle.bats tests/static_contracts.bats"
        status: pass
    human_judgment: false
  - id: D2
    description: "Eight-action orchestration, stop-before-destroy behavior, and verifier exit mapping"
    requirement: LIFE-03
    verification:
      - kind: integration
        ref: "make test (fixture-backed lifecycle suite)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Successful-only timing ledger schema and explicit Phase 2 acceptance gate"
    requirement: LIFE-06
    verification:
      - kind: unit
        ref: "tests/static_contracts.bats: lifecycle timing ledgers are blank and document successful-only round-trip gates"
        status: pass
    human_judgment: false
  - id: D4
    description: "Two consecutive clean empty-cluster make up/down round-trips"
    requirement: LIFE-04
    verification:
      - kind: manual_procedural
        ref: "Live AWS acceptance was not run under the no-mutation constraint."
        status: unknown
    human_judgment: true
    rationale: "Acceptance requires real AWS lifecycle mutations, which were explicitly prohibited for this execution."

# Metrics
duration: 19min
completed: 2026-10-14
status: complete
---

# Phase 02-06: Ephemeral Infrastructure Drain Scripts Summary

**A fixed 15-minute process-group deadline now covers teardown through verification, with bounded retries and successful-only timing records.**

## Performance

- **Duration:** 19 min from the first recorded task commit to completion
- **Started:** 2026-10-14T15:08:35+07:00 (first recorded task commit)
- **Completed:** 2026-10-14T08:27:45Z
- **Tasks:** 3
- **Files modified:** 9 (including one removed runner)

## Accomplishments

- Replaced the Python timeout runner with GNU `timeout`/Homebrew `gtimeout`, fixed at 900 seconds without a per-run override; the process group is terminated on expiry.
- Kept the eight actions ordered as Argo preparation, three drains, L3/L2/L1 destroys, and verification. Confirmed drains proceed automatically; drain failures stop before destroy.
- Added doctor coverage for deadline tooling, fixed retry limits and monotonic boundary tests, and blank successful-only `make up`/`make down` timing tables.
- Documented the seven-versus-eight roadmap count and the two consecutive clean empty-cluster round-trip gate before application code.

## Task Commits

1. **Task 1: Enforce the single deadline and finish the eight-action teardown path** - `f06d27c` (test), `1f129e0` (feat), `76bb20b` (chore)
2. **Task 2: Guard deadline tooling, retry bounds, and exact timing boundaries** - `ec5030d` (test), `8bbc451` (fix), `ce6f96d` (test harness correction)
3. **Task 3: Define successful-only teardown timing records** - `a76279b` (docs)

## Files Created/Modified

- `Makefile` - Fixed GNU timeout invocation for the complete teardown.
- `sh/down.sh` - Shared timing origin and drain execution; timing prints only after verifier exit 0.
- `sh/lifecycle-common.sh` - Fixed deadline and retry bounds, monotonic elapsed/deadline helpers.
- `sh/doctor.sh` - Detects `timeout`/`gtimeout` and provides the macOS installation hint.
- `tests/phase2_lifecycle.bats`, `tests/static_contracts.bats` - Deadline, retries, tool preflight, orchestration, and documentation contracts.
- `COSTS.md`, `layers/10-infra/README.md` - Empty measured-run tables and operator acceptance contract.
- `sh/run-down-with-deadline.py` - Removed obsolete Python timeout runner.

## Decisions Made

GNU timeout owns hard process-group termination; Bash `SECONDS` is used only for diagnostics and deterministic cutoff checks. The published ledger remains empty until successful measured runs are available.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserve the elapsed-time origin across drain scripts**
- **Found during:** Task 2
- **Issue:** Launching each drain as a fresh Bash process would give its `SECONDS` counter a different origin from the orchestrator.
- **Fix:** Source each drain in a Bash subshell and export the orchestrator's start value, preserving shared elapsed-time diagnostics while keeping the parent isolated.
- **Files modified:** `sh/down.sh`, `sh/lifecycle-common.sh`
- **Verification:** Fake-clock boundary test, full lifecycle Bats suite, ShellCheck.
- **Committed in:** `8bbc451`

**Total deviations:** 1 auto-fixed (Rule 1 - Bug). The change is limited to shared timing correctness.

## Issues Encountered

The isolated doctor test PATH initially omitted `rm`, causing Bats cleanup warnings. Added its test-only symlink and committed the correction; all tests pass. The repository's TDD evidence helper does not recognize Bats TAP, so verification relied on actual Bats failures/passes rather than synthetic evidence.

## User Setup Required

None.

## Next Phase Readiness

Implementation and local verification are ready. The two required real empty-cluster round-trips remain unverified and must pass before application code; no AWS acceptance, `make up`, or `make down` was attempted.

## Verification

- `make test`: passed, 116 tests.
- `AWS_PROFILE=microservices-demo make validate`: passed for all four Terraform layers, formatting, and ShellCheck. Terraform validation used `init -backend=false`.
- `bats tests/phase2_lifecycle.bats tests/static_contracts.bats`: passed, 71 tests before the Task 3 docs assertion; `make test` subsequently passed the full 116-test suite including it.
- No real AWS mutation, Terraform apply/destroy, or live lifecycle command was run.

## Self-Check: PASSED

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Completed: 2026-10-14*
