---
title: Drop the two human_needed truths from Phase 1
date: 2026-10-26
priority: high
---

Remove the two roadmap truths that cannot be verified now so Phase 1 stops blocking live Phase 2 work:

- Truth #3 / COST-04 — Cost Anomaly Detection alert from a deliberate $1 resource
- Truth #4 / COST-01, COST-05 — per-layer attribution and idle cost ≤ $5 over a real billing period

Files to update:

- `.planning/ROADMAP.md` — Phase 1 success criteria 3 and 4
- `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-VERIFICATION.md` — status, score, gaps
- `.planning/STATE.md` — Phase 1 `human_needed` blocker line
- `.planning/REQUIREMENTS.md` — COST-01, COST-04, COST-05 wording/status

Keep the fork-PR observation as a static-assertion-only item (UAT #29). Phase 2's M1 precondition ("no live Phase 2 AWS operation while Phase 1 is human_needed") then clears.
