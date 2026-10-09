---
gsd_state_version: "1.0"
milestone: v1.0
milestone_name: Practice Platform
current_phase: 01
current_phase_name: Account, L0 Bootstrap & Teardown Harness
status: executing
stopped_at: Completed 01-06-PLAN.md; SNS confirmation verified
last_updated: "2026-10-09T02:47:38.961Z"
last_activity: 2026-10-09
state_head: fe0301995868a5edaa2d614ef931e93b92a55477
progress:
  total_phases: 14
  completed_phases: 0
  total_plans: 10
  completed_plans: 6
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-24)

**Core value:** Every AWS, Kubernetes, and DevOps concept in this project must be practiced end-to-end in a system that can be stood up and completely destroyed on the same day for a few dollars — if teardown or rebuild breaks, the entire practice loop dies with it.
**Current focus:** Phase 01 — Account, L0 Bootstrap & Teardown Harness

## Current Position

Phase: 01 (Account, L0 Bootstrap & Teardown Harness) — EXECUTING
Plan: 7 of 10
Status: Ready to execute
Last activity: 2026-10-09

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

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

### Pending Todos

None yet.

### Blockers/Concerns

- **[Phase 5/6] OQ5: OTel trace context across EventBridge.** Resolved in approach (manual `traceparent` in the envelope), unverified in practice. Three of four researchers flagged this as the most likely thing to silently break the flagship demo. Watch for the Link-vs-Parent false negative.
- **[Phase 9] OQ2/OQ4 unresolved.** Prometheus TSDB dies nightly but burn-rate alerting needs multi-day history; platform footprint estimates (2.1 / 2.5–4 / 3.5–6.5 GiB) are unmeasured hypotheses.
- **[Phase 5] OQ1 unresolved.** RDS viability under same-day teardown — `var.use_rds` defaults false pending measured create/delete timings.
- **[Cross-cutting] "Infrastructure forever, never ship a feature."** No deadline means no forcing function. Phase 4's walking skeleton and Phase 6's trace moment exist as deliberate defences.

## Deferred Items

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-09T02:47:25.193Z
Stopped at: Completed 01-06-PLAN.md; SNS confirmation verified
Resume file: None
