---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 02
subsystem: testing
tags: [bats, aws-cli, fixtures, terraform, oidc]
requires:
  - phase: 01
    provides: Four-layer Terraform skeleton, Makefile test target, pinned local test tooling
provides:
  - Fixture-replaying AWS CLI shim with argv logging, error precedence, and cleanup
  - Raw AWS response fixtures with documented report/exclude contracts
  - Bats suites for teardown exclusions, exit codes, OIDC trust, and static contracts
affects: [phase-1-bootstrap, teardown-verifier, oidc-trust, wave-0-validation]
actuals:
  tokens: 6578
  tasks: 3
  commits: 3
tech-stack:
  added: []
  patterns: [temporary PATH shims, fixture-driven AWS calls, class-specific plan-attributed skips]
key-files:
  created:
    - tests/helpers/stub-aws.bash
    - tests/helpers/load.bash
    - tests/harness_selftest.bats
    - tests/fixtures/aws/README.md
    - tests/verify_teardown_exclusions.bats
    - tests/verify_teardown_exit_codes.bats
    - tests/oidc_trust.bats
    - tests/static_contracts.bats
  modified:
    - tests/fixtures/aws/ec2-describe-volumes.json
key-decisions:
  - "Keep fixtures as raw AWS CLI response bodies before query projection so call-shape changes remain testable."
  - "Resolve replay fixtures from the first service and operation arguments, prefer .err files, and record complete argv."
  - "Inspect OIDC HCL directly for T1 checks because plan rendering can require credentials."
patterns-established:
  - "Two-sided fixture oracle: each resource fixture names an item that must report and an item that must be excluded."
  - "Skip unavailable sweep checks by check-function presence, with a plan-attributed MISSING sentinel."
requirements-completed: [LIFE-05, LIFE-10, CD-05]
coverage:
  - id: D1
    description: Fixture-replay harness exercises success, error, missing-fixture, argv logging, and cleanup behavior.
    requirement: LIFE-05
    verification:
      - kind: unit
        ref: "bats tests/harness_selftest.bats (6 passing cases)"
        status: pass
      - kind: other
        ref: "shellcheck tests/helpers/*.bash"
        status: pass
    human_judgment: false
  - id: D2
    description: Raw AWS response fixtures cover the teardown resource classes and document their exclusion contracts.
    requirement: LIFE-05
    verification:
      - kind: other
        ref: "jq validation of tests/fixtures/aws/*.json; required SG, instance, and CloudFront shape assertions; README row-to-fixture check"
        status: pass
    human_judgment: false
  - id: D3
    description: Four assertion suites provide executable future-plan gates while keeping unavailable code explicitly skipped.
    verification:
      - kind: unit
        ref: "bats tests/ (32 cases: 12 pass, 20 expected MISSING skips)"
        status: pass
      - kind: other
        ref: "bats --count checks for exactly 3 exit-code cases and at least 6 static-contract cases; skip reason regex check"
        status: pass
    human_judgment: false
duration: 29 min
completed: 2026-10-01
status: complete
---

# Phase 1 Plan 02: Wave-0 Validation Harness Summary

**Fixture-driven AWS test harness, per-class response corpus, and future-ready teardown/OIDC contract suites**

## Performance

- **Duration:** 29 min
- **Started:** 2026-10-01T07:51:48.523Z
- **Completed:** 2026-10-01T08:20:28.256Z
- **Tasks:** 3/3
- **Files modified:** 21

## Accomplishments

- Added a temporary PATH-injected `aws` shim that replays raw JSON, prefers error fixtures, logs complete arguments, returns 99 for missing fixtures, and restores PATH on cleanup.
- Recorded per-class AWS response fixtures and documented the report/exclude oracle for every JSON file.
- Added the four Wave-0 Bats suites; the self-test and static contracts pass, while behavior tests carry explicit skips until their implementation plans land.

## Task Commits

1. **Task 1: Install bats-core and build the stubbed aws binary harness** - `ca1815a` (`test`)
2. **Task 2: Record per-class AWS fixtures encoding the LIFE-05 false-positive exclusions** - `a0b380b` (`test`)
3. **Task 3: Author the four assertion suites** - `8ff44cb` (`test`)

## Files Created/Modified

- `tests/helpers/stub-aws.bash` and `tests/helpers/load.bash` - shared fixture replay and test setup.
- `tests/harness_selftest.bats` - six passing checks of replay, error, lookup, logging, and cleanup behavior.
- `tests/fixtures/aws/*.json`, `tests/fixtures/aws/sts-get-caller-identity-expired.err`, and `tests/fixtures/aws/README.md` - raw response corpus and fixture contract.
- `tests/verify_teardown_exclusions.bats` - per-class two-sided assertions, gated on check-function availability.
- `tests/verify_teardown_exit_codes.bats` - clean, orphan, and mid-sweep credential-failure assertions.
- `tests/oidc_trust.bats` - direct-source HCL trust checks, gated until plan 01-07.
- `tests/static_contracts.bats` - six active lock, tag, pinning, credential, and resource-tag assertions.

## Decisions Made

- Test fixtures preserve service-native response field names and are returned before any AWS CLI `--query` projection.
- The temporary shim uses a test-overridable fixture directory, so self-tests remain independent of sweep implementation.
- OIDC assertions inspect source HCL directly; rendering a Terraform plan may need AWS credentials and would not be a T1 check.
- Sweep assertions activate only when their corresponding check function is present, allowing plans 01-04, 01-05, and 01-08 to turn on coverage incrementally.

## Deviations from Plan

### Auto-fixed Issues

**1. CloudFront's required empty response cannot satisfy the general two-sided fixture rule**
- **Found during:** Task 2 (per-class AWS fixtures)
- **Issue:** The required real empty-account shape omits `DistributionList.Items`, so it has no distribution entry that could also be a must-report example.
- **Fix:** Preserved the required raw empty response and documented the exception and non-empty behavior in the fixture contract README.
- **Files modified:** `tests/fixtures/aws/README.md`, `tests/fixtures/aws/cloudfront-list-distributions.json`
- **Verification:** `jq -e '.DistributionList | has("Items") | not' tests/fixtures/aws/cloudfront-list-distributions.json`; README fixture row and corpus checks passed.
- **Committed in:** `a0b380b`

---

**Total deviations:** 1 auto-fixed (required CloudFront empty-response exception)
**Impact on plan:** Preserves the exact AWS response shape and records the narrow case that cannot be a two-sided resource oracle; all other resource fixtures include reportable and excluded entries.

## Issues Encountered

- ShellCheck initially reported SC1091 for the dynamically sourced shared loader; adding its source directive made the specified lint check clean.
- `develop` is protected by the repository guard. The user explicitly authorized `git.allow_default_branch_commits=true` so the required plan commits could proceed; this override remains enabled for the current execution run.

## User Setup Required

None for this plan. No live AWS calls were made.

## Next Phase Readiness

Plan 01-03 can now resolve AWS unit pricing and author the account-setup runbook. Plan 01-04 can use the EBS fixture and exit-code suite to build the first teardown-sweep path. The 20 current skips are intentional; plan 01-09 remains responsible for requiring zero skips before phase completion.

## Self-Check: PASSED

- All three task commits are present in the measured plan range.
- All JSON fixtures parse, each fixture is documented, and the required SG, EC2, and CloudFront shapes pass.
- `bats tests/` passes with 12 executed cases and 20 plan-attributed skips; ShellCheck is clean.
- No sweep logic, Terraform resources, or Makefile changes were added.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-01*