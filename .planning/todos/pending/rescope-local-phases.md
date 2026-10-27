---
title: Rescope success criteria for local-only phases
date: 2026-10-26
priority: medium
---

Per `.planning/notes/real-vs-local-deploy-policy.md`, rewrite ROADMAP success criteria for phases 3, 5, 6, 7, 9, 10, 11, 12, 14 so they are provable locally (kind/k3d, LocalStack/MinIO, Testcontainers).

Criteria that currently assume real AWS and need rewording:

- Phase 5 SC2 — Tempo blocks in S3 surviving cluster destroy
- Phase 5 SC5 — core-profile hourly rate ≤ ~$0.23/hr recorded in `COSTS.md` (COST-02)
- Phase 6 SC1/SC2 — trace through real EventBridge/SQS
- Phase 9 — S3-backed long-term metrics
- Phase 10 — Pod Identity, ESO, WAF, Cognito

Also review requirement mappings (COST-02, COST-09) and OQ1/OQ3/OQ5 decision gates.
