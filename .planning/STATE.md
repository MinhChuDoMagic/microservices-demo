---
gsd_state_version: "1.0"
milestone: v1.0
milestone_name: Practice Platform
current_phase: 02
current_phase_name: Ephemeral Infrastructure & Drain Scripts
status: executing
stopped_at: Phase 2 context gathered
last_updated: "2026-10-15T03:31:22.148Z"
last_activity: 2026-10-14
last_activity_desc: Phase 02 execution started
state_head: 152eb72d2ea912296b3b1cfc924bbbc07a5b06d8
progress:
  total_phases: 14
  completed_phases: 0
  total_plans: 18
  completed_plans: 17
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-24)

**Core value:** Every AWS, Kubernetes, and DevOps concept in this project must be practiced end-to-end in a system that can be stood up and completely destroyed on the same day for a few dollars — if teardown or rebuild breaks, the entire practice loop dies with it.
**Current focus:** Phase 02 — Ephemeral Infrastructure & Drain Scripts

## Current Position

Phase: 02 (Ephemeral Infrastructure & Drain Scripts) — EXECUTING
Plan: 1 of 8
Status: Executing Phase 02
Last activity: 2026-10-14 — Phase 02 execution started

Progress: 100%

## Performance Metrics

**Velocity:**

 Total plans completed: 10

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 20 min | 3 tasks | 24 files |
| Phase 01 P02 | 29 min | 3 tasks | 21 files |
| Phase 01 P03 | 1h 14m | 4 tasks | 8 files |
| Phase 01 P04 | 48 min | 3 tasks | 10 files |
| Phase 01 P05 | 23 min | 3 tasks | 5 files |
| Phase 01 P06 | 16h 21m | 3 tasks | 4 files |
| Phase 01 P07 | 46 min | 3 tasks | 5 files |
| Phase 01 P08 | — | 3 tasks | 5 files |
| Phase 01 P09 | 15 min | 3 tasks | 5 files |
| Phase 01 P10 | multi-session | 3 tasks | 10 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Teardown harness precedes all provisioning — `verify-teardown.sh` is the Phase 1 deliverable, written before there is anything to tear down
- [Roadmap]: Hard gate at Phase 2 — two consecutive zero-orphan `make up`/`make down` round-trips on an empty cluster before any application code
- [Roadmap]: Minimal Prometheus + Tempo land in Phase 5, before the second service — a distributed saga cannot be debugged without traces
- [Roadmap]: Security and policy deliberately late (Phase 10) — added early, every bug looks like a policy bug
- [Roadmap]: `catalog` and `cart` placed in Phase 11, closing a coverage gap in the research build order (they were never explicitly placed, yet Phase 12's canary presupposes `catalog`)
- [Phase 01]: Exact Terraform and AWS provider pins with committed checksums — Keep every layer reproducible across machines.
- [Phase 01]: Literal per-layer Layer tags with four shared default tags — The teardown sweep uses Layer to separate immortal bootstrap resources from ephemeral resources.
- [Phase 01]: Generated root backend config with per-layer state keys — Keep account-specific bucket data and local state out of Git.
- [Phase 01]: Preserve CloudFront empty-account fixture without DistributionList.Items — The required raw empty response contains no distribution entry, so the fixture README records this as the one-sided empty-shape exception.
- [Phase 01]: Use a dedicated Organizations member account as the project trust anchor — The user explicitly approved amending D-03; the management account remains outside Terraform, controls Cost Explorer access and pays the consolidated bill, and the project member account has no surviving resources.
- [Phase 01]: Credential-less Organizations member root accounts do not require AccountMFAEnabled=1 — AWS centrally managed member roots have no root credentials; the credential report confirms no password, access keys, or certificates. If credentials exist, root MFA remains required.
- [Phase 01]: Generate repo-root backend.hcl and pass it by absolute path — The checkpoint adopted option A; the root location avoids -chdir-relative path ambiguity while per-layer state keys remain CLI arguments.
- [Phase 01]: Expire noncurrent state versions after 30 days while retaining the newest 10 — The checkpoint adopted option A and confirmed this bounded recovery window.
- [Phase 01]: Force-copy only when remote state is absent — When bucket and state object exist, reconfigure; a fresh checkout must never overwrite good remote state with stale local state.
- [Phase 01]: Keep the baseline teardown allowlist empty — The user confirmed the member account had no resources that must survive, and the pre-apply sweep found none.
- [Phase 01]: Keep all report schema classes explicit — Later-plan classes retain zero-count slots through a deliberate placeholder; unknown schema keys fail closed.
- [Phase 01]: Defensively filter raw EC2 instance fixtures — Keep the required server-side state filter and repeat it locally because fixture replay does not apply AWS CLI projections.
- [Phase 01]: Use a daily actual-spend tripwire during alert cold starts — The  daily budget provides deterministic first-day coverage while forecast budgets and Cost Anomaly Detection lack sufficient history.
- [Phase 01]: Use immediate service-dimension anomaly alerts — A DIMENSIONAL SERVICE monitor is valid in the member account and IMMEDIATE supports the SNS-only subscription.
- [Phase 01]: Keep the cost-alert SNS topic unencrypted — AWS Budgets requires additional permissions for encrypted topics and the KMS key cost is unnecessary.
- [Phase 01]: Use immutable GitHub OIDC subjects for CI trust — The repository was created on 2026-09-23, after the 2026-07-15 cutover; metadata shows owner ID 82219047 and repository ID 1383184443, so both IDs qualify the subject. The repository is public, so no unredacted claim debugger workflow will be published.
- [Phase 01]: Keep OIDC roles disjoint by purpose — the plan role trusts PRs only; the apply role and a separate read-only sweep role trust only `develop`. The sweep role explicitly denies state-object reads while retaining required S3 bucket metadata access.
- [Phase 01]: Keep AdministratorAccess temporary and deny account and credential administration — The apply role's explicit deny blocks Organizations, billing configuration, and long-lived credential creation, but leaves budgets and Cost Explorer usable. Phase 10 replaces the broad grant using recorded CloudTrail activity.
- [Phase 01]: Use `develop` as the only apply and sweep branch — It is the repository's only/default branch.
- [Phase 01]: Keep bootstrap destruction outside the daily loop — `make nuke-bootstrap` requires the live account ID and restores the literal destroy guard from backup.

### Pending Todos

None yet.

### Blockers/Concerns

- **[Phase 5/6] OQ5: OTel trace context across EventBridge.** Resolved in approach (manual `traceparent` in the envelope), unverified in practice. Three of four researchers flagged this as the most likely thing to silently break the flagship demo. Watch for the Link-vs-Parent false negative.
- **[Phase 9] OQ2/OQ4 unresolved.** Prometheus TSDB dies nightly but burn-rate alerting needs multi-day history; platform footprint estimates (2.1 / 2.5–4 / 3.5–6.5 GiB) are unmeasured hypotheses.
- **[Phase 5] OQ1 unresolved.** RDS viability under same-day teardown — `var.use_rds` defaults false pending measured create/delete timings.
- **[Phase 1] Fork-PR workflow observation unverified (non-gating).** No forks exist; static assertions cover the fallback.
- **[Cross-cutting] "Infrastructure forever, never ship a feature."** No deadline means no forcing function. Phase 4's walking skeleton and Phase 6's trace moment exist as deliberate defences.
- [Phase 1] Phase verifier status is `passed` in 01-VERIFICATION.md (3/3 remaining truths) as of 2026-10-26: the user dropped truth #3 (Cost Anomaly Detection live delivery) and truth #4 (billing-period attribution and idle cost) as not verifiable. Native S3 lock acquisition/release was observed during a read-only plan; the authorized live EBS hard-gate passed orphan detection, cleanup, and error handling. The valid bootstrap destroy and real $1 cost event were not run by explicit constraint.

## Deferred Items

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-14T03:13:43.703Z
Stopped at: Phase 2 context gathered
Resume file: .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-CONTEXT.md
