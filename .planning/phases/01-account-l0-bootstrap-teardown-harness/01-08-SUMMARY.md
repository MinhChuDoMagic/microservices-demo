---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 08
subsystem: teardown
tags: [aws, bash, teardown, bats, jq]
requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Baseline teardown verifier and live L0 account resources.
provides:
  - Full home-region, global, and enabled-region teardown scopes.
  - Project-tag pagination with explicit token termination and provenance.
  - Concurrent tier-three checks with report scope lists.
affects: [01-09 teardown hard gate, 01-10 workflows]
actuals:
  tasks: 3
  commits: 0
tech-stack:
  added: []
  patterns:
    - Isolated checker work directories and NDJSON merge for concurrent inventories.
    - Project tag scan supplements untagged-resource blind-spot checks.
key-decisions:
  - Keep tier three to five expensive resource classes in enabled non-home regions.
  - Use a four-region concurrency cap; higher fan-out increased measured runtime.
  - Record actual full, global, and tier-three scopes in the report.
requirements-completed: [LIFE-05, COST-08]
---

# Phase 1 Plan 08: Teardown Sweep Completion

**The teardown verifier now covers tagged resources, regional blind spots, and explicit sweep scopes.**

## Accomplishments

- Completed the load-balancer, target-group, security-group, CloudWatch, IAM, CloudFront, and S3 checks from Tasks 1 and 2.
- Added Project-tag pagination, empty/absent-token termination, stripped-tag handling, and `discovered_by=tag` findings.
- Added enabled-region discovery and concurrent five-class tier-three checks, with regional unavailability tolerated only in that tier.
- Populated `regions_scanned` for full, global, and tier-three scopes; retained a fixed report schema and fail-closed errors.
- Added fixture coverage for regional resources, pagination expiry, and unavailable regional endpoints.

## Verification

- `shellcheck sh/verify-teardown.sh tests/helpers/stub-aws.bash`: passed.
- `bats --print-output-on-failure tests/`: 47 passed, zero skipped.
- `AWS_PROFILE=microservices-demo make verify-teardown`: clean live account, 28.139 seconds; all three scope lists populated across 16 tier-three regions and all 14 class keys present.
- Static contract checks passed: no executable `--all-regions` request and every allowlist entry has a reason.

## Deviations

- Home/global checks and the five tier-three checks are executed with isolated concurrent workers; modern and classic load-balancer calls also overlap. This was needed to meet the measured 30-second live-sweep ceiling. The four-region cap performed better than eight- or sixteen-region bursts.
- Added empty-array-safe report serialization for macOS Bash with `set -u`.

No commits were created.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-09*
