---
phase: "1"
slug: "account-l0-bootstrap-teardown-harness"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-24"
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> **Derived from** `01-RESEARCH.md` § Validation Architecture. This is an infrastructure
> phase — Terraform HCL and Bash, no application runtime — so the "test framework" is a
> composition of `shellcheck`, `bats-core`, `terraform validate`, and live-account
> assertion scripts rather than a single unit-test runner.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `bats-core` (Bash assertions) + `shellcheck` (lint) + `terraform fmt`/`validate` (HCL) |
| **Config file** | none — Wave 0 installs `bats-core` and creates `tests/` |
| **Quick run command** | `make validate` (→ `terraform fmt -check -recursive`, `terraform validate` per layer, `shellcheck scripts/*.sh`) |
| **Full suite command** | `make validate && bats tests/` |
| **Estimated runtime** | ~20 seconds (T1 static only — no AWS calls) |

**Live-account tiers run separately** and are NOT part of the quick/full loop:

| Tier | Command | Requires |
|------|---------|----------|
| **T2** live-account automated | `make test-verify-teardown` | Valid AWS credentials; creates and deletes one 1 GiB gp3 volume |
| **T3** deferred observational | manual, recorded in `COSTS.md` | Elapsed real time (≥24h for tags, ≥10d for Cost Anomaly Detection) |

---

## Sampling Rate

- **After every task commit:** Run `make validate`
- **After every plan wave:** Run `make validate && bats tests/`
- **After the sweep-script wave specifically:** Also run `make test-verify-teardown` (T2)
- **Before `/gsd-verify-work`:** Full suite green AND `make test-verify-teardown` exits 0
- **Max feedback latency:** 20 seconds (T1); ~90 seconds (T2, EBS volume create/delete round-trip)

---

## Per-Task Verification Map

*Seeded as draft — populated by `/gsd-validate-phase` once `01-PLAN.md` exists.*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | 01 | — | COST-01 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | COST-04 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | COST-05 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | COST-08 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | COST-09 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | LIFE-05 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | LIFE-07 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | LIFE-08 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | LIFE-09 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | LIFE-10 | — | — | — | — | ❌ W0 | ⬜ pending |
| TBD | 01 | — | CD-05 | T-1-01 | OIDC trust admits only this repo on `main`/PR; no long-lived keys | integration | `bats tests/oidc_trust.bats` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 must exist before any sweep logic is written — the fixture harness is what makes the
false-positive exclusions (the hard part of LIFE-05) cheap to prove.

- [ ] `bats-core` installed and `make validate` wired to `shellcheck`
- [ ] `tests/fixtures/aws/` — recorded JSON responses per orphan class
- [ ] `tests/helpers/stub-aws.bash` — puts a stub `aws` binary on `PATH` that replays fixtures
- [ ] `tests/verify_teardown_exclusions.bats` — one case per LIFE-05 class asserting the
      **exclusion** holds (default SG, terminated instance, `--owner-ids self` snapshots,
      `RequesterManaged` ENI, AWS-managed log group)
- [ ] `tests/verify_teardown_exit_codes.bats` — asserts the D-10 three-way contract, including
      that `HARD_ERROR` is checked **before** findings so a credential failure cannot print
      "CLEAN"
- [ ] `tests/oidc_trust.bats` — static assertions on the rendered trust policies
      (`StringEquals` not `StringLike`; no `*` in any `sub`)
- [ ] `tests/static_contracts.bats` — `grep` assertions for SC2 (`no dynamodb_table`,
      `use_lockfile` present) and SC4 (`default_tags` has all four keys in every layer)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AWS account prerequisites (root MFA, admin identity, Cost Explorer opt-in) | COST-08 | D-01 — the account is a manual prerequisite, never Terraform-managed; it bootstraps the credentials Terraform needs | Follow `docs/RUNBOOK-account-setup.md` end to end |
| Cost allocation tag activation | COST-01 | Billing-console only; takes up to 24h and **never backfills** — must be done *before* resources are created | Billing → Cost allocation tags → activate `Project`, `Layer`, `ManagedBy`, `Environment`; record activation date in `COSTS.md` |
| SNS email subscription confirmation | COST-04 | Terraform cannot confirm an email subscription; it reports success while the subscription stays inert | Click the confirmation link, then assert `aws sns list-subscriptions-by-topic` shows `Confirmed`, not `PendingConfirmation` |
| Cost Anomaly Detection alert actually firing | COST-04 | **T3 / deferred** — per RESEARCH F-02, CAD needs ~10 days of per-service history plus warm-up; impossible inside the phase window | Record the testable-from date in `COSTS.md`. The F-02 daily `ACTUAL` $1 budget is the automatable proxy that seals the phase |
| Cost Explorer per-layer attribution against a real billing period | COST-01, COST-09 | **T3 / deferred** — requires ≥24h tag activation plus a real billing period | Record the observation date in `COSTS.md`; assert tag *presence* via `resourcegroupstaggingapi` in the meantime |
| GitHub repo `sub` claim shape (immutable vs legacy) | CD-05 | **BLOCKING per RESEARCH F-01** — determines whether the trust policy literal is correct at all | `gh api repos/OWNER/REPO --jq .created_at`; repos created on/after 2026-07-15 use the `@ID` form. Must run **before** the IAM role tasks |
| Negative OIDC test (non-`main`, non-PR ref must fail to assume the apply role) | CD-05 | Requires a real GitHub Actions run from a throwaway branch | Push a branch with a workflow that attempts `gha-terraform-apply`; assert the job fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] Every T3 deferred item has a recorded testable-from date in `COSTS.md`
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
