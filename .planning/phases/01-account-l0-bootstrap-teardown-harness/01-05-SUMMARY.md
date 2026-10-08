---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 05
subsystem: infra
tags: [bash, aws-ec2, teardown, bats, jq]

requires:
  - phase: 01
    provides: Fixture replay harness and the baseline teardown verifier spine
provides:
  - Fixture-proven EC2 instance and snapshot checks with server-side state and owner filters
  - Elastic IP and detached ENI checks with cost and service-ownership exclusions
  - Report class coverage guard, populated counts, actionable usual-cause lines, and error-first verdict
affects: [teardown-verifier, phase-1-sweep-expansion, phase-2-lifecycle]

actuals:
  tokens: 4700
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - Server-side AWS filters are asserted from the replay shim call log and raw fixtures are defensively filtered.
    - Every report class is explicitly mapped to a live checker or a deliberate later-plan placeholder.

key-files:
  created:
    - tests/fixtures/aws/ec2-describe-images.json
  modified:
    - scripts/verify-teardown.sh
    - tests/verify_teardown_exclusions.bats
    - tests/verify_teardown_exit_codes.bats
    - tests/fixtures/aws/README.md

key-decisions:
  - Keep all report schema classes explicit; later-plan classes map to a no-op placeholder until their checker is implemented, while unregistered keys fail closed.
  - Apply the required EC2 state filter at AWS and locally because fixture replay returns raw, unfiltered responses.

requirements-completed: [LIFE-05, COST-08]

coverage:
  - id: D1
    description: Running and stopped EC2 instances plus manual snapshots are reported while terminated instances and AMI-backed snapshots are excluded.
    requirement: LIFE-05
    verification:
      - kind: unit
        ref: tests/verify_teardown_exclusions.bats#instance-and-snapshot fixtures
        status: pass
      - kind: other
        ref: shellcheck scripts/verify-teardown.sh
        status: pass
    human_judgment: false
  - id: D2
    description: Unassociated public IPv4 addresses and plain detached interfaces are reported with service-managed exclusions and actionable reasons.
    requirement: COST-08
    verification:
      - kind: unit
        ref: tests/verify_teardown_exclusions.bats#address-and-interface fixtures
        status: pass
    human_judgment: false
  - id: D3
    description: The report summarizes all schema classes, explains common orphan causes, and returns error when any sweep class fails even after findings accumulate.
    requirement: LIFE-05
    verification:
      - kind: unit
        ref: tests/verify_teardown_exit_codes.bats#late credential failure and missing class registration
        status: pass
      - kind: unit
        ref: tests/verify_teardown_exclusions.bats#summary and usual-cause output
        status: pass
      - kind: other
        ref: bats tests/ && shellcheck scripts/verify-teardown.sh
        status: pass
    human_judgment: false

duration: 23min
completed: 2026-10-08
status: complete
---

# Phase 1 Plan 05: Sweep Expansion A Summary

**Five teardown classes now report fixture-proven findings with a guarded report schema and cost-aware explanations**

## Performance

- **Duration:** 23 min
- **Started:** 2026-10-08T10:00:26Z
- **Completed:** 2026-10-08T10:23:08Z
- **Tasks:** 3/3
- **Files modified:** 5

## Accomplishments

- Wired EC2 instance and snapshot checks, filtering instance states on the API call and excluding self-owned AMI backing snapshots through one image lookup.
- Wired unassociated Elastic IP and detached ENI checks, preserving association data and excluding requester-managed and service-managed interfaces.
- Added report counts and per-class usual causes, an explicit schema/check registry, and a test proving a missing class fails closed.
- Strengthened the mid-sweep credential failure test to ensure exit 2 wins after earlier orphan findings have accumulated.

## Task Commits

1. **Task 1: EC2 instance and snapshot classes** - `921a4f0` (RED tests), `d2d649a` (GREEN implementation)
2. **Task 2: Elastic IP and network interface classes** - `50654f5` (RED tests), `eb1e288` (GREEN implementation)
3. **Task 3: Report and table coverage** - `28362b5` (implementation and regression tests)

## Files Created/Modified

- `scripts/verify-teardown.sh` - Four new checks, explicit class coverage registry, error-first verdict note, and class-specific table causes.
- `tests/verify_teardown_exclusions.bats` - Activated instance, volume, snapshot, address, and ENI cases; added reason and report coverage assertions.
- `tests/verify_teardown_exit_codes.bats` - Tests late-sweep error precedence and missing class registration.
- `tests/fixtures/aws/ec2-describe-images.json` - Self-owned AMI reference for the image-backed snapshot exclusion.
- `tests/fixtures/aws/README.md` - Documents the new image lookup fixture contract.

## Decisions Made

- Keep the full report schema stable. Later-plan classes are explicitly mapped to a no-op placeholder, preserving zero-count slots while ensuring an unregistered schema key fails closed.
- Keep both the EC2 API state filter and a local state predicate because the fixture shim replays raw AWS responses rather than applying CLI filters.

## Deviations from Plan

### Auto-fixed Issues

**1. Added a self-owned image response fixture**
- **Found during:** Task 1 (snapshot check)
- **Issue:** The required `describe-images` cross-reference had no replay fixture; the harness intentionally treats missing fixtures as errors.
- **Fix:** Added `ec2-describe-images.json` and documented its AMI-backed snapshot ID in the fixture README.
- **Files modified:** `tests/fixtures/aws/ec2-describe-images.json`, `tests/fixtures/aws/README.md`
- **Verification:** The snapshot test records `--owners self`, excludes the referenced image snapshot, and reports the manual snapshot.
- **Committed in:** `921a4f0`

**2. Filter raw instance fixtures locally as well as at the API**
- **Found during:** Task 1 (instance fixture test)
- **Issue:** The replay shim returns raw responses, so it does not simulate AWS applying the server-side state filter.
- **Fix:** Kept the required API filter and added a local state predicate for pending/running/stopping/stopped.
- **Files modified:** `scripts/verify-teardown.sh`
- **Verification:** The call-log assertion proves the API filter is present; the fixture test excludes terminated and shutting-down instances.
- **Committed in:** `d2d649a`

**3. Registered later-plan report classes explicitly**
- **Found during:** Task 3 (coverage guard)
- **Issue:** Failing on every currently unwired schema class would contradict the requirement to retain zero-count slots for later plans.
- **Fix:** Mapped later-plan classes to a deliberate no-op placeholder and made the guard reject schema/registry drift or missing functions.
- **Files modified:** `scripts/verify-teardown.sh`
- **Verification:** The exit-code suite injects an unregistered schema key and asserts exit 2 plus an error naming it.
- **Committed in:** `28362b5`

**4. Move the credential failure later in the sweep**
- **Found during:** Task 3 (error ordering)
- **Issue:** The old fixture failed on the first resource class and did not prove error precedence after findings existed.
- **Fix:** Fail snapshot enumeration after EBS and instance findings have accumulated, then assert the report still returns error 2.
- **Files modified:** `tests/verify_teardown_exit_codes.bats`
- **Verification:** The case asserts both `.errors` and a positive orphan count alongside the error verdict.
- **Committed in:** `28362b5`

---

**Total deviations:** 4 auto-fixed (fixture coverage, raw fixture filtering, explicit future-class registrations, stronger error-ordering test).
**Impact on plan:** All changes strengthen the required fixture and report contracts; no AWS resources were created and the JSON schema remained unchanged.

## Issues Encountered

- Copilot marks `scripts/verify-teardown.sh` as ignored, so `apply_patch` was blocked. After the prior handoff's authorization and explicit confirmation in this session, a unique-anchor Node edit was used; ShellCheck and the full Bats suite passed.
- Initial patch attempts and the first table/guard tests exposed local context and assertion issues, which were corrected before the final verification run.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 01-06 can add cost guardrails. The teardown verifier now reports five resource classes and retains explicit zero-count entries for classes assigned to later plans. The known Phase 01-07 OIDC subject-format decision remains the next human checkpoint.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-08*
