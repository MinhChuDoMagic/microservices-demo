---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 04
subsystem: infrastructure
tags: [terraform, aws-s3, state-locking, teardown, bash]
requires:
  - phase: 01
    provides: Four-layer Terraform skeleton, account pin/doctor, raw AWS fixtures and Bats contracts
provides:
  - Versioned, encrypted, public-access-blocked L0 S3 state bucket with literal destroy guard
  - Account-aware local-to-S3 state migration and generated native-lock backend config
  - D-10 verifier spine with EBS fixture/live checks, complete report slots, and baseline allowlist
  - Stale-lock recovery target and state-recovery documentation
affects: [phase-1-cost-guardrails, phase-1-oidc, phase-2-lifecycle]
actuals:
  tokens: 7426
  tasks: 3
  commits: 2
tech-stack:
  added: []
  patterns: [account-aware backend migration, native S3 lockfile, temporary local-backend bootstrap, versioned-state recovery]
key-files:
  created:
    - layers/00-bootstrap/backend.tf
    - layers/00-bootstrap/main.tf
    - layers/00-bootstrap/outputs.tf
    - sh/verify-teardown.sh
    - sh/teardown-allowlist.txt
  modified:
    - Makefile
    - layers/00-bootstrap/versions.tf
    - layers/00-bootstrap/README.md
    - tests/helpers/stub-aws.bash
    - tests/static_contracts.bats
key-decisions:
  - "Use the checkpoint-approved repo-root generated backend config by absolute path; pass each layer's state key separately."
  - "Use 30-day noncurrent version expiry while retaining the 10 newest versions; S3 versioning remains the only recovery mechanism."
  - "Use force-copy only when the bucket exists but remote state does not; reconfigure when remote state exists."
  - "Keep the baseline allowlist empty because the user confirmed no account resources must survive and the baseline verifier found none."
patterns-established:
  - "Bootstrap the state bucket locally, then migrate to S3 without removing the tracked empty backend block permanently."
  - "Keep all AWS calls in the verifier behind one stderr-classifying wrapper and check hard errors before findings."
requirements-completed: [LIFE-05, LIFE-07, LIFE-08, LIFE-09, LIFE-10, COST-08]
coverage:
  - id: D1
    description: L0 S3 state bucket and state migration are live, versioned, encrypted, locked, and protected from destroy/replacement.
    requirement: LIFE-08
    verification:
      - kind: integration
        ref: "AWS_PROFILE=microservices-demo make bootstrap; output state_bucket_name; S3 head-object and get-bucket-versioning checks"
        status: pass
      - kind: integration
        ref: "terraform -chdir=layers/00-bootstrap plan -detailed-exitcode via make bootstrap (no changes); .tflock Versions/DeleteMarkers both present"
        status: pass
    human_judgment: true
    rationale: The bucket and migration are one-way state boundaries; the operator approved the seam and version-retention window at the plan checkpoint before apply.
  - id: D2
    description: The account-wide verifier returns a clean verdict for the EBS tracer and emits all class slots without widening the baseline allowlist.
    requirement: LIFE-05
    verification:
      - kind: unit
        ref: "bats tests/verify_teardown_exit_codes.bats tests/verify_teardown_exclusions.bats"
        status: pass
      - kind: integration
        ref: "AWS_PROFILE=microservices-demo make verify-teardown; .teardown-report.json verdict/exit_code/class-slot assertions"
        status: pass
      - kind: other
        ref: "ShellCheck sh/verify-teardown.sh; bash -n; empty non-comment teardown allowlist"
        status: pass
    human_judgment: false
  - id: D3
    description: Bootstrap README records state keys, recovery, destroy-guard behavior, and the PROJECT.md native-locking regression contract.
    requirement: LIFE-10
    verification:
      - kind: unit
        ref: "bats tests/static_contracts.bats (7 passing cases)"
        status: pass
      - kind: other
        ref: "README recovery/replacement acceptance checks; PROJECT.md byte-identical and native-locking regression checks"
        status: pass
    human_judgment: false
duration: 48 min
completed: 2026-10-08
status: complete
---

# Phase 1 Plan 04: Bootstrap and Teardown Tracer Summary

**Versioned S3 state bootstrap, guarded account-aware migration, and a clean EBS-backed teardown tracer**

## Performance

- **Duration:** 48 min
- **Started:** 2026-10-08T08:59:04Z
- **Completed:** 2026-10-08T09:46:56Z
- **Tasks:** 3/3
- **Files modified:** 10

## Accomplishments

- Created the six-resource L0 state bucket foundation with versioning, SSE-S3, all public-access blocks, enforced bucket ownership, lifecycle retention (30 days plus the 10 newest noncurrent versions), and a literal `prevent_destroy` guard.
- Added an account-aware `make bootstrap` path that keeps the first apply local, generates ignored backend config, safely migrates state, verifies no drift, and reconfigures without copying when remote state already exists.
- Added the D-10 verifier/report spine with only available EBS wired, an empty baseline allowlist, native-lock cleanup tooling, and documented state recovery.

## Task Commits

1. **Task 1: Confirm the bootstrap seam before the first real apply** - checkpoint decision A; repo-root absolute backend path, 30-day/10-version retention, ignored account pin, and guarded copy migration confirmed.
2. **Task 2: End-to-end bootstrap state lands in S3 and the account verifies clean** - `2bb756a` (`feat`).
3. **Task 3: Record the seam and native-locking regression guard** - `2514c7a` (`docs`).

## Files Created/Modified

- `layers/00-bootstrap/main.tf`, `backend.tf`, `outputs.tf`, and `versions.tf` - account-derived S3 state bucket and partial backend.
- `Makefile` - guarded local bootstrap/migration, three-way verifier mapping, generated backend assertion, and layer-specific `unlock` target.
- `sh/verify-teardown.sh` and `sh/teardown-allowlist.txt` - verifier wrapper/report/EBS path and empty baseline inventory.
- `layers/00-bootstrap/README.md` - ownership, state-key contract, version recovery, destroy guard, and L0 lifecycle.
- `tests/helpers/stub-aws.bash` and `tests/static_contracts.bats` - raw-response call-log assertion support and the read-only PROJECT locking guard.

## Decisions Made

- Used the approved repo-root `backend.hcl` and absolute backend-config path; state keys remain per-layer command-line arguments.
- The first apply temporarily removes `backend.tf` and restores it with traps so Terraform can use a local backend; subsequent migration explicitly requests `-migrate-state -force-copy` only while the remote state object is absent.
- The baseline sweep found no available EBS volumes or survivors, so `sh/teardown-allowlist.txt` remains header-only.
- The local ignored `.aws-account-id` pin and generated backend file are not committed.

## Deviations from Plan

### Auto-fixed Issues

**1. macOS Bash 3.2 and fixture-response compatibility**
- **Found during:** Task 2 (sweep spine)
- **Issue:** `mapfile` is unavailable in the system Bash 3.2, and the test shim deliberately returns raw fixture objects while the AWS CLI returns query-projected arrays.
- **Fix:** Used a Bash-3.2-compatible indexed array loader and allowed the EBS parser to consume either raw `.Volumes[]` objects or projected arrays; the server-side availability filter remains in the CLI call.
- **Files modified:** `sh/verify-teardown.sh`, `tests/helpers/stub-aws.bash`
- **Verification:** Focused exit/EBS Bats suites passed, including the recorded availability filter and D-10 error ordering.
- **Committed in:** `2bb756a`

**2. Terraform local-backend bootstrap required hiding the tracked S3 backend block temporarily**
- **Found during:** Task 2 (first local init/apply)
- **Issue:** Terraform 1.16.4 still requested S3 backend initialization with the empty backend block present, despite `init -backend=false`.
- **Fix:** Move only `backend.tf` aside for the local init/apply, restore it with EXIT/INT/TERM traps, then migrate. The next retry detects and restores a leftover disabled backend file before inspecting account state.
- **Files modified:** `Makefile`
- **Verification:** Local bucket apply succeeded; remote state was verified absent before retry; explicit migration completed without overwriting existing remote state, and the subsequent detailed-exitcode plan had no changes.
- **Committed in:** `2bb756a`

**3. Explicit `-migrate-state` needed alongside `-force-copy`**
- **Found during:** Task 2 (local-to-S3 migration)
- **Issue:** `init -force-copy` alone did not complete the backend transition.
- **Fix:** Add `-migrate-state -force-copy` to the two guarded branches where remote state is absent; remote-present branches use only `-reconfigure`.
- **Files modified:** `Makefile`
- **Verification:** The first attempt preserved local lineage/serial and remote state remained absent; the corrected path migrated state and the second bootstrap took the no-copy path.
- **Committed in:** `2bb756a`

**4. ShellCheck SC2329 on trap-invoked functions**
- **Found during:** Task 2 (script lint)
- **Issue:** ShellCheck did not infer that `cleanup` and `on_err` are invoked indirectly by traps.
- **Fix:** Added narrow SC2329 directives at the two trap handler definitions.
- **Files modified:** `sh/verify-teardown.sh`
- **Verification:** `shellcheck sh/verify-teardown.sh` passes.
- **Committed in:** `2bb756a`

**5. PROJECT.md state-locking guard added to the static suite**
- **Found during:** Task 3 (locking-constraint regression guard)
- **Issue:** The plan explicitly requires the existing project requirement to remain unchanged while protecting it from a state-locking-context DynamoDB regression.
- **Fix:** Added a read-only Bats assertion for native `use_lockfile` wording and a negative lock-table pattern anchored on state/backend context.
- **Files modified:** `tests/static_contracts.bats`
- **Verification:** `bats tests/static_contracts.bats` passes seven cases; `git diff --quiet` confirms `.planning/PROJECT.md` was not modified by task 3.
- **Committed in:** `2514c7a`

---

**Total deviations:** 5 auto-fixed (runtime compatibility, migration behavior, shell lint annotation, and regression coverage).
**Impact on plan:** No resource scope was added. One state bucket was created in the approved member account; migration was completed only after confirming the remote state key was absent.

## Issues Encountered

- A `make -n bootstrap` check was unsafe because recursive `$(MAKE)` caused the shell recipe to run; it stopped before applying resources. Do not dry-run the recursive bootstrap target. Validation thereafter used offline `make validate` and the explicit guarded bootstrap path.
- `make verify-teardown` initially showed the plan-01-01 placeholder; after plan-04 wiring, the live baseline and post-bootstrap verifier both returned clean.
- A normal file patch was blocked for the Copilot-ignored verifier. The user explicitly approved the alternate write path; no other ignored source was edited.

## User Setup Required

None outstanding for plan 01-04. The account's Billing IAM toggle was user-confirmed in plan 01-03; the Organizations management account still owns future cost-tag activation in plan 01-10.

## Next Phase Readiness

Plan 01-05 can expand the verifier with EC2, snapshots, EIPs, and ENIs using the raw fixtures and active EBS contract. Plan 01-06 can add cost guardrails to the already-remote bootstrap state. The current state bucket is immortal, versioned, locked, and outside the daily lifecycle.

## Self-Check: PASSED

- Six state-bucket resources created and state migrated to the expected S3 key.
- Second `make bootstrap` reconfigured and planned no changes without `-force-copy`.
- `make verify-teardown` returned clean; report has 15 class keys and the baseline allowlist is empty.
- S3 versioning is enabled; `.tflock` has retained versions and delete markers; DynamoDB table count is zero.
- `make validate`, `bats tests/`, ShellCheck, Bash syntax, README acceptance, and PROJECT.md regression checks pass.
- No other Phase 1 resource classes or Makefile lifecycle targets were added.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-08*