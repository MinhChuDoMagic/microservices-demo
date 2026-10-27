---
title: Real vs local deploy policy
date: 2026-10-26
context: /gsd-explore — cost of deploying real AWS resources in every phase
---

# Real vs local deploy policy

**Motivation:** Deploying real AWS resources (EKS, NAT, nodes) in every phase is too expensive.

## Decision

Real AWS resources are deployed only in these phases:

- Phase 2 — Ephemeral Infrastructure & Drain Scripts (hard gate: two zero-orphan round-trips)
- Phase 4 — GitOps Seam & Walking Skeleton (real ALB, clean `make down`)
- Phase 8 — Karpenter, Spot & Graceful Drain (real Spot interruption)
- Phase 13 — Chaos Scenarios & Runbooks

All other phases (3, 5, 6, 7, 9, 10, 11, 12, 14) run local/offline: kind/k3d, LocalStack/MinIO, Testcontainers, fixtures.

## Verification

Local-only phases are not re-verified on real AWS later (user decision, 2026-10-26).

## Known risks (accepted)

- Phase 6 (OQ5): `traceparent` propagation through EventBridge → SQS may behave differently in LocalStack than in AWS.
- Phase 10: Pod Identity, WAF and Cognito are hard to prove fully without real AWS.
- Phase 5 SC2 (Tempo blocks in S3) and SC5 (hourly cost) assume real AWS and need rewording.

## Related

- Phase 1 truths #3 (COST-04 Cost Anomaly Detection) and #4 (COST-01/COST-05 billing-period) are to be dropped — see todo `drop-phase1-human-needed-truths`.
