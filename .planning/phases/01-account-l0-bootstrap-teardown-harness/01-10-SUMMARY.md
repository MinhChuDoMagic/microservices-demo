---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 10
subsystem: infrastructure
tags: [aws, github-actions, oidc, terraform, teardown, cost-allocation]
requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Tagged bootstrap resources, OIDC roles, teardown verifier, and fixture test harness.
provides:
  - Pull-request plan, develop-branch apply, and scheduled read-only teardown workflows through OIDC.
  - A deliberately confirmed bootstrap decommission path and versioned-bucket emptier.
  - Recorded cost-allocation tag activation and the deferred attribution window.
affects: [phase-01-closeout, phase-02-teardown-gate]
actuals:
  tokens: 16411
  tasks: 3
  commits: 6
tech-stack:
  added: []
  patterns:
    - CI roles are disjoint by purpose; the sweep role cannot read Terraform state objects.
    - L0 decommissioning is isolated from the daily lifecycle and requires the live account ID.
key-files:
  created:
    - .github/workflows/terraform-plan.yml
    - .github/workflows/terraform-apply.yml
    - .github/workflows/scheduled-teardown-sweep.yml
    - sh/empty-versioned-bucket.sh
  modified:
    - layers/00-bootstrap/oidc.tf
    - Makefile
    - docs/CONVENTIONS.md
    - tests/static_contracts.bats
    - VERSIONS.md
    - COSTS.md
key-decisions:
  - "Use develop as the only apply and sweep branch because it is the repository's default branch."
  - "Give the scheduled sweep its own read-only role with an explicit state-object read deny."
  - "Keep `prevent_destroy` in tracked configuration; temporarily edit and restore it only inside the decommission target."
  - "Treat `nuke-bootstrap` as a D-19 decommission exception, not a D-35 daily-loop target."
requirements-completed: [CD-05, LIFE-05, LIFE-09, LIFE-10, COST-05]
coverage:
  - id: D1
    description: Terraform plan and apply workflows assume their branch-scoped AWS roles through OIDC, with a negative trust test.
    requirement: CD-05
    verification:
      - kind: integration
        ref: "GitHub Actions runs 37911796549 (plan) and 37912898939 (apply); negative run 37910392741 rejected role assumption."
        status: pass
      - kind: unit
        ref: "bats tests/static_contracts.bats"
        status: pass
    human_judgment: true
    rationale: The fork-PR fallback was not observed live because the repository has no forks; user chose to leave this observational item unverified.
  - id: D2
    description: The scheduled teardown workflow distinguishes all three verifier outcomes and uploads a report on every run.
    requirement: LIFE-05
    verification:
      - kind: integration
        ref: "GitHub Actions sweep run 37914598359 succeeded; teardown-report-37914598359 artifact uploaded (714 bytes)."
        status: pass
      - kind: unit
        ref: "bats tests/static_contracts.bats"
        status: pass
    human_judgment: false
  - id: D3
    description: Bootstrap decommissioning has a live-account confirmation, refuses other layer state, restores the destroy guard, and empties all bucket versions before destroy.
    requirement: LIFE-09
    verification:
      - kind: unit
        ref: "bats tests/static_contracts.bats#nuke-bootstrap rejects a wrong confirmation before changing state"
        status: pass
      - kind: integration
        ref: "shellcheck sh/empty-versioned-bucket.sh; make -n nuke-bootstrap; routine-target dry runs"
        status: pass
    human_judgment: true
    rationale: The valid-confirmation destroy path is intentionally never executed; guard restoration is reviewed structurally and the mismatch path is tested.
  - id: D4
    description: Four cost-allocation keys were activated and the permanent pre-activation attribution gap was recorded.
    requirement: COST-05
    verification:
      - kind: manual_procedural
        ref: "Operator-confirmed Billing console status on 2026-10-09; COSTS.md records the unattributable resources and 2026-12-02 observation date."
        status: pass
    human_judgment: true
    rationale: The member-account CLI profile is denied access to organization cost-allocation tags; active status was confirmed in the Billing console, not through the API.
duration: multi-session (not reliably measured)
completed: 2026-10-13
status: complete
---

# Phase 1 Plan 10: OIDC Workflows and Guarded L0 Decommissioning Summary

**Branch-scoped OIDC workflows now run end to end, and L0 has a separate account-confirmed decommission path that preserves its destroy guard by default.**

## Performance

- **Duration:** Continued across sessions; elapsed time is not reliably recorded.
- **Started:** 2026-10-09 (resumed 2026-10-13)
- **Completed:** 2026-10-13
- **Tasks:** 3 implementation tasks, plus the decision and billing checkpoints
- **Files modified:** 10

## Accomplishments

- Proved the plan role on a pull request, the apply role on `develop`, and rejection of an untrusted branch. Added a dedicated read-only sweep role and scheduled workflow; its clean live run uploaded the report artifact successfully.
- Added `make nuke-bootstrap` as the only bootstrap destroy path. It requires a typed confirmation containing the live account ID, refuses while other layer state exists, migrates bootstrap state to local, edits the literal guard with a backup and restoring trap, empties object versions and delete markers, then destroys.
- Recorded operator-confirmed activation of `Project`, `Layer`, `ManagedBy`, and `Environment`, the permanently unattributable pre-activation L0 resources, and the first post-billing-month attribution observation date.

## Task Commits

1. **Task 1: Terraform plan/apply OIDC workflows** - `b622ac5` (`feat`)
2. **Task 2: Scheduled teardown sweep** - `14c8527`, `2fe830b`, `53dcbb8` (`feat`, `feat`, `fix`)
3. **Task 4: Guarded bootstrap decommission path** - `d89bbfa` (`feat`)
4. **Billing checkpoint: Record cost-allocation activation** - `34f2c35` (`docs`)

## Files Created/Modified

- `.github/workflows/terraform-plan.yml` - PR-only OIDC plan path with a fork-safe fallback.
- `.github/workflows/terraform-apply.yml` - OIDC apply path restricted to `develop`.
- `.github/workflows/scheduled-teardown-sweep.yml` - Scheduled and manual sweep with three-way outcomes and report upload.
- `layers/00-bootstrap/oidc.tf` - Dedicated sweep role and explicit state-object read denial.
- `sh/empty-versioned-bucket.sh` - Batch-deletes versions and delete markers and checks per-object errors.
- `Makefile` - Decommission-only target, help entry, and the explicitly approved `shellcheck sh/*.sh` validation change.
- `docs/CONVENTIONS.md` - D-19 versus D-35 scope and destroy-guard convention.
- `tests/static_contracts.bats` - Emptier, target structure, and safe confirmation-refusal tests.
- `VERSIONS.md` - Immutable action pins.
- `COSTS.md` - Tag activation, attribution window, and verification limitation.

## Decisions Made

- Use `develop` for apply and sweep trust because it is the repository's only/default branch.
- Keep the sweep role separate and deny it state-object reads explicitly.
- Preserve `prevent_destroy = true` in the tracked Terraform resource and use a trap-restored in-place edit only for decommissioning.
- Interpret D-19 as a separate account-decommission target and D-35 as the daily-loop target list; `make up` and `make down` must never reach `00-bootstrap`.

## Deviations from Plan

- The required read-only `aws ce list-cost-allocation-tags --status Active` check was denied from the member-account profile. The user confirmed all four keys Active in the Organizations Billing console; that confirmation and the CLI limitation are recorded in `COSTS.md`.
- The live fork-PR fallback observation remains unverified because the repository has no forks; this was an accepted user choice. Static assertions cover the fallback structure.

**Total deviations:** 2 documented verification limitations. **Impact:** The billing state is operator-confirmed but not API-verified from this account; the fork path remains a future observation. Neither changes the implemented guardrails.

## Issues Encountered

- `make validate` initially lacked `AWS_PROFILE=microservices-demo`; rerunning with the profile passed.
- The GSD CLI helper cannot load because it imports the missing `sh/fix-slash-commands.cjs`; planning close-out must use the checked-in artifacts and careful manual updates.
- The valid-confirmation decommission path was not run, as required. Only its mismatch path and dry-run recipe were exercised.

## Verification

- `AWS_PROFILE=microservices-demo make validate`: passed, including Terraform validation and ShellCheck.
- `bats tests/`: 55 passed, 0 skipped, 0 failed.
- `AWS_PROFILE=microservices-demo make verify-teardown`: clean account.
- `make -n verify-teardown`, `make -n validate`, and `make -n bootstrap`: no bootstrap destroy path. `make -n nuke-bootstrap` was also inspected without executing the target.
- Mismatch confirmation test: passed; caller identity was the only AWS call and `layers/00-bootstrap/main.tf` remained unchanged.
- Live GitHub sweep run `37914598359`: succeeded; 714-byte artifact uploaded.
- `git diff --check`: passed.

## User Setup Required

None for Plan 01-10. The management-account Billing action was completed by the operator and confirmed in the console.

## Next Phase Readiness

Plan 01-10 implementation and checkpoints are complete. Phase-level verification remains to run. Cost Explorer per-layer attribution is deferred until 2026-12-02; fork-PR runtime behavior remains unobserved because no forks exist.

## Self-Check: PASSED

- All three implementation tasks and both blocking checkpoints are accounted for.
- The destructive target was never executed; routine targets were checked for isolation.
- Known verification limitations are explicit above and in `COSTS.md`.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-13*