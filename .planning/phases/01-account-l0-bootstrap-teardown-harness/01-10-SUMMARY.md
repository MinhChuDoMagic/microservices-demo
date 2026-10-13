---
phase: 01-account-l0-bootstrap-teardown-harness
plan: 10
subsystem: infrastructure
tags: [aws, github-actions, oidc, terraform, teardown, cost-allocation]
requires:
  - phase: 01-account-l0-bootstrap-teardown-harness
    provides: Tagged bootstrap resources, OIDC roles, teardown verifier, and fixture test harness.
provides:
  - Pull-request and develop-branch OIDC role smoke checks, plus the scheduled read-only teardown workflow.
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
    - .github/workflows/oidc-plan-role-smoke.yml
    - .github/workflows/oidc-apply-role-smoke.yml
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
    description: Branch-scoped OIDC role smoke checks validate assumption and reject an untrusted branch; they do not run Terraform plan or apply.
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

# Phase 1 Plan 10: OIDC Role Checks and Guarded L0 Decommissioning Summary

**Branch-scoped OIDC role checks are explicit smoke tests, and L0 has a separate account-confirmed decommission path that preserves its destroy guard by default.**

## Performance

- **Duration:** Continued across sessions; elapsed time is not reliably recorded.
- **Started:** 2026-10-09 (resumed 2026-10-13)
- **Completed:** 2026-10-13
- **Tasks:** 3 implementation tasks, plus the decision and billing checkpoints
- **Files modified:** 10

## Accomplishments

- Proved plan-role assumption on a pull request, apply-role assumption on `develop`, and rejection of an untrusted branch. These are OIDC smoke checks, not Terraform plan/apply automation. Added a dedicated read-only sweep role and scheduled workflow; its clean live run uploaded the report artifact successfully.
- Added `make nuke-bootstrap` as the only bootstrap destroy path. It requires a typed confirmation containing the live account ID, refuses while other layer state exists, explicitly migrates bootstrap state to a temporary local backend and verifies the bucket resource is present before purge, and uses an EXIT trap to restore both the backend declaration and destroy guard.
- Recorded operator-confirmed activation of `Project`, `Layer`, `ManagedBy`, and `Environment`, the permanently unattributable pre-activation L0 resources, and the first post-billing-month attribution observation date.

## Task Commits

1. **Task 1: OIDC role smoke workflows** - `b622ac5` (`feat`)
2. **Task 2: Scheduled teardown sweep** - `14c8527`, `2fe830b`, `53dcbb8` (`feat`, `feat`, `fix`)
3. **Task 4: Guarded bootstrap decommission path** - `d89bbfa` (`feat`)
4. **Billing checkpoint: Record cost-allocation activation** - `34f2c35` (`docs`)

## Files Created/Modified

- `.github/workflows/oidc-plan-role-smoke.yml` - PR-only OIDC plan-role smoke check with a fork-safe fallback; does not run `terraform plan`.
- `.github/workflows/oidc-apply-role-smoke.yml` - OIDC apply-role smoke check restricted to `develop`; does not run `terraform apply`.
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
- The plan/apply workflows were renamed and documented as OIDC role smoke checks by user choice. They do not execute Terraform plan/apply; requirement CD-06 remains open for a separately configured delivery pipeline.

**Total deviations:** 3 documented verification limitations or scope adjustments. **Impact:** The billing state is operator-confirmed but not API-verified from this account; the fork path remains a future observation; actual Terraform plan/apply automation remains open under CD-06.

## Issues Encountered

- `make validate` initially lacked `AWS_PROFILE=microservices-demo`; rerunning with the profile passed.
- The GSD CLI helper cannot load because it imports the missing `sh/fix-slash-commands.cjs`; planning close-out must use the checked-in artifacts and careful manual updates.
- The valid-confirmation decommission path was not run, as required. Only its mismatch path and dry-run recipe were exercised.
- Source review found that `-backend=false` did not migrate bootstrap state and that the apply guard omitted service-specific credentials. Both are fixed and covered by focused regression tests; actual remote-state migration and valid decommission remain intentionally unexecuted.
- The phase verifier reports `human_needed` (1/5 roadmap truths fully verified). The live IAM guardrail matches source, and both published OIDC smoke workflows passed, including their AWS role assumptions. Required lifecycle, alert, and billing-period observations remain incomplete; Phase 1 remains executing.

## Verification

- Historical checks before the review follow-up: `AWS_PROFILE=microservices-demo make validate` and `AWS_PROFILE=microservices-demo make verify-teardown` passed; the latter observed a clean account.
- Current `bats tests/`: 56 passed, 0 skipped, 0 failed.
- Current isolated Terraform `init -backend=false` and `validate` passed in fresh `TF_DATA_DIR` directories for all four layers. `terraform fmt -check -recursive` and `shellcheck sh/*.sh` passed.
- After restoring SSO, current `AWS_PROFILE=microservices-demo make validate` passed all four layers and `AWS_PROFILE=microservices-demo make verify-teardown` reported the account clean for wired classes.
- Read-only live checks found root access-key count 0, no IAM users, zero Actions/Dependabot/Codespaces secrets, no GitHub environments, and all four expected repository variables. The bootstrap bucket versioning is Enabled, the current state object exists, no current lock object or DynamoDB table exists, and live OIDC trust subjects match the intended PR/develop claims.
- The live `gha-terraform-apply` policy `phase1-broad-apply-guardrails` was updated from the explicitly authorized saved plan to deny `iam:CreateServiceSpecificCredential`: 0 added, 1 changed, 0 destroyed. The live read-back confirmed the deny. After publishing the renamed workflows, apply-role run `38370037745` on `develop` and plan-role PR run `38370179861` both succeeded. Temporary PR #4 was closed without merging and its branch deleted.
- Current `make -n nuke-bootstrap` expanded the migration and local-state verification before bucket emptying; the valid target was not executed. The wrong-confirmation test passed and confirmed caller identity was the only AWS call and `layers/00-bootstrap/main.tf` remained unchanged.
- Focused source re-review: clean, 0 findings. `git diff --check` passed.
- Historical live GitHub sweep run `37914598359`: succeeded; 714-byte artifact uploaded.
- Phase verification: `01-VERIFICATION.md` status `human_needed` with 1/5 truths verified; Phase 1 remains executing. `STATE.md` records remaining external-outcome evidence.

## User Setup Required

None for Plan 01-10. The management-account Billing action was completed by the operator and confirmed in the console.

## Next Phase Readiness

Plan 01-10 implementation and checkpoints are complete. Phase-level verification returned `human_needed` with 1/5 truths verified; keep Phase 1 executing until remaining lifecycle, cost-alert, and billing-period evidence is addressed. Cost Explorer per-layer attribution is deferred until 2026-12-02, fork-PR runtime behavior remains unobserved because no forks exist, and CD-06 plan/apply automation remains open.

## Self-Check: PASSED

- All three implementation tasks and both blocking checkpoints are accounted for.
- The destructive target was never executed; routine targets were checked for isolation.
- Known verification limitations are explicit above and in `COSTS.md`.

---
*Phase: 01-account-l0-bootstrap-teardown-harness*
*Completed: 2026-10-13*