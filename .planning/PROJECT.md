# AWS EKS E-Commerce Microservices Practice Platform

## What This Is

A deliberately challenging, production-shaped e-commerce microservices system built from scratch on AWS EKS, existing purely as a hands-on practice ground for AWS, Terraform, Kubernetes, and DevOps. It pairs a polyglot service mesh of Java Spring Boot services and Python Lambdas with a full GitOps delivery pipeline, self-hosted observability stack, and injectable failure scenarios. The audience is one person — a SAP-C02 and CKA certified engineer with strong theory who needs scar tissue from real day-2 operations.

## Core Value

Every AWS, Kubernetes, and DevOps concept in this project must be practiced end-to-end in a system that can be stood up and completely destroyed on the same day for a few dollars — if teardown or rebuild breaks, the entire practice loop dies with it.

## Requirements

### Validated

(None yet — ship to validate)

### Active

**Infrastructure & Cost Control**

- [ ] Entire stack provisioned by Terraform with remote state in S3 + DynamoDB state locking that survives teardown
- [ ] Single-command `make up` and `make down` lifecycle that provisions and fully destroys all billable resources
- [ ] Idle cost ≤ ~$5/month; active session cost ≤ ~$0.30/hour
- [ ] VPC with public/private subnets, fck-nat instance (t4g.nano) for egress, and VPC endpoints for AWS-native traffic
- [ ] Cost visibility — AWS Budgets alarm, cost allocation tags, and a teardown verification check that proves nothing billable was orphaned

**EKS Platform**

- [ ] EKS cluster provisioned via Terraform with managed node groups on Spot instances
- [ ] Karpenter for node autoscaling, bin-packing, and Spot interruption handling
- [ ] AWS Load Balancer Controller fronting the cluster with an ALB ingress
- [ ] Platform addons managed declaratively — ArgoCD, External Secrets Operator, Kyverno, metrics-server, EBS CSI driver

**Core Services (Milestone 1)**

- [ ] `api-gateway` — Spring Cloud Gateway handling routing, JWT validation against Cognito, and rate limiting
- [ ] `catalog` — Spring Boot over DynamoDB, read-heavy, HPA-scaled
- [ ] `cart` — Spring Boot over ElastiCache Redis with TTL-based ephemeral state
- [ ] `order` — Spring Boot over RDS Postgres, acting as saga orchestrator with the transactional outbox pattern
- [ ] `payment-sim` — Spring Boot fake payment service with deliberate, configurable failure injection
- [ ] `inventory` — Spring Boot over DynamoDB using optimistic locking and compensating transactions
- [ ] `notification` — Python Lambda consuming EventBridge/SQS events, sending via SES/SNS
- [ ] `frontend` — React + Vite SPA served from S3 behind CloudFront, deliberately minimal

**Event-Driven Communication**

- [ ] SNS + SQS + EventBridge as the asynchronous backbone between services
- [ ] Order → payment → inventory saga with compensating transactions on failure
- [ ] Dead-letter queues, retry policies with exponential backoff, and idempotent consumers
- [ ] Transactional outbox in `order` to guarantee no lost events on database commit

**CI/CD**

- [ ] GitHub Actions pipelines for build, test, container image publish to ECR, and Terraform plan/apply
- [ ] ArgoCD performing pull-based GitOps deployment from a dedicated manifests repo/directory
- [ ] OIDC federation between GitHub Actions and AWS IAM — no long-lived access keys anywhere
- [ ] Progressive delivery for at least one service (canary or blue/green) to practice safe rollout and rollback

**Observability**

- [ ] Self-hosted in-cluster stack — Prometheus, Grafana, Loki, and Tempo
- [ ] OpenTelemetry instrumentation across all Spring Boot services producing distributed traces
- [ ] A trace that follows a single order end-to-end across the full saga
- [ ] Grafana dashboards for RED/USE metrics plus alerting rules on SLO burn

**Security**

- [ ] IRSA / EKS Pod Identity giving each service least-privilege, pod-scoped IAM
- [ ] External Secrets Operator syncing from AWS Secrets Manager — zero secrets in Git
- [ ] Trivy image scanning plus ECR scan-on-push, failing CI on high/critical CVEs
- [ ] Kubernetes NetworkPolicies enforcing zero-trust pod-to-pod networking
- [ ] Kyverno admission policies enforcing pod security standards and image provenance
- [ ] AWS WAF on the ALB/CloudFront with OWASP managed rules and rate limiting
- [ ] tfsec/Checkov IaC scanning blocking insecure Terraform in CI

**Testing**

- [ ] Unit and integration tests for Spring Boot services using Testcontainers
- [ ] Contract testing between services
- [ ] A smoke/E2E suite that runs against a freshly provisioned cluster and gates deployment

**Chaos & Troubleshooting**

- [ ] Break-glass module with injectable failures — pod evictions, network latency, dependency outages, Spot interruptions, OOMKills, DNS failures
- [ ] A written runbook per scenario, authored by actually debugging the failure rather than describing it in theory

### Out of Scope

- **Real payment provider integration** — no PCI surface wanted; `payment-sim` exists to be broken on purpose, which is more instructive
- **Custom domain names** — avoids registrar cost and DNS propagation friction on a stack that is destroyed daily
- **Amazon MSK / managed Kafka** — roughly $180/month destroys the cost model; SNS/SQS/EventBridge teaches the same async patterns
- **Amazon Managed Grafana / AMP** — self-hosting the stack is both cheaper and where the actual learning lives
- **Managed NAT Gateway** — ~$32/month idle; a fck-nat instance costs ~$3/month and forces real VPC understanding
- **EKS Auto Mode and Fargate** — both abstract away the node-level control and DaemonSet support this project is meant to practice
- **Rich frontend UX** — the UI exists only to exercise the backend; effort belongs in infrastructure and distributed systems
- **Multi-region / active-active DR** — cost and complexity outweigh the learning at this stage
- **Real users, real traffic, production SLAs** — this is a practice environment, not a product
- **Dedicated auth service** (deferred to M2) — Cognito validated at the gateway covers M1 needs
- **image-processor Lambda, OpenSearch search, reviews, recommendations** (deferred to M2) — additive surface, not needed to prove the core architecture
- **Falco, GuardDuty, Security Hub, Cosign/SBOM, service mesh mTLS** (deferred to M2) — valuable but would balloon M1 scope
- **Deadlines and delivery pressure** — this is open-ended practice; correctness and depth beat speed

## Context

**Operator background.** Holds AWS Solutions Architect Professional (SAP-C02) and Certified Kubernetes Administrator (CKA). Theory is solid across AWS services, Kubernetes primitives, and architecture patterns. The explicit gap is applied experience — building, operating, breaking, and fixing a real distributed system. This means the project should skip tutorials and beginner scaffolding, and instead lean into the areas certifications do not cover: day-2 operations, failure modes, debugging under uncertainty, and cost engineering.

**Starting state.** Effectively greenfield. The repository contains only a one-line `README.md` ("# AWS EKS Learning Project"), GSD tooling under `.github/`, and an empty `research/` directory. No application code, no infrastructure, no CI.

**Language preference.** Java Spring Boot for containerized backend services — it is the operator's strongest backend stack, so cognitive budget goes to infrastructure rather than language learning. Python reserved for lightweight Lambda functions. Frontend framework left to the agent's discretion; React + Vite chosen for familiarity and trivially cheap static hosting.

**The centrepiece.** The order → payment → inventory saga is where distributed-systems pain actually lives — partial failures, compensating transactions, idempotency, and eventual consistency. Troubleshooting scenarios are only meaningful because this saga exists to break.

**Working rhythm.** No deadline, no fixed hours. Work happens in sessions: spin up, practice, destroy the same day. This rhythm is the single strongest architectural constraint in the project.

## Constraints

- **Budget**: Idle cost ≤ ~$5/month, active session ≤ ~$0.30/hour — this is self-funded practice, and an unnoticed running cluster is the classic way these projects die
- **Lifecycle**: Every resource must be destroyable and reproducible on the same day — anything that cannot be cleanly torn down and rebuilt is a design defect, not an inconvenience
- **Tech stack**: Java Spring Boot for containerized services, Python for Lambdas, Terraform for all infrastructure, React + Vite for the frontend — plays to existing strength so learning budget goes to AWS and Kubernetes
- **Tech stack**: No expensive managed services (MSK, Managed Grafana, NAT Gateway, multi-AZ RDS) — cost model dominates service selection
- **Security**: No long-lived AWS credentials anywhere; GitHub Actions authenticates via OIDC and pods via IRSA/Pod Identity — matches production practice and removes the most common leak vector
- **Security**: No secrets committed to Git; all secret material flows through AWS Secrets Manager via External Secrets Operator
- **Scope**: No custom domains, no real payments, no real users — removes cost, compliance, and support surface that teaches nothing here
- **Learning-first**: When a cheaper-and-easier option and a harder-but-more-instructive option cost roughly the same, choose the instructive one — the entire point is difficulty

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| EKS with managed node groups on Spot + Karpenter | Cheapest compute; forces real practice with bin-packing, interruption handling, and graceful shutdown. Rejected Auto Mode (~12% premium, less control) and Fargate (no DaemonSet support, which would break the self-hosted observability stack) | — Pending |
| Polyglot persistence — RDS Postgres + DynamoDB + ElastiCache Redis | Most realistic e-commerce data architecture; each store teaches a different access pattern. Accepts the snapshot/restore friction that daily teardown imposes on RDS as itself a useful lesson | — Pending |
| SNS + SQS + EventBridge as the event backbone | Near-free, AWS-native, and exercises fan-out, DLQs, and retry semantics. MSK ruled out purely on cost (~$180/month) | — Pending |
| GitHub Actions for CI, ArgoCD for CD (GitOps) | Production-standard split; pull-based delivery is a significant learning win over push-based `kubectl apply` and keeps cluster credentials out of CI | — Pending |
| Self-hosted Prometheus + Grafana + Loki + Tempo | Costs roughly nothing and teaches far more than managed equivalents; CloudWatch's per-GB and per-custom-metric charges also conflict with the cost ceiling | — Pending |
| fck-nat instance (t4g.nano) + VPC endpoints instead of managed NAT Gateway | Cuts ~$32/month to ~$3/month and forces genuine understanding of VPC routing, rather than paying to have it abstracted away | — Pending |
| Trim Milestone 1 to 6 containerized services + 1 Lambda | Ten Spring Boot services is a lot of boilerplate before reaching the AWS work; the trimmed set still preserves the full saga and every infrastructure concern. Auth service, image-processor, search, and reviews deferred to M2 | — Pending |
| Cognito validated at the API gateway rather than a dedicated auth service | Removes one service from M1 while still practising OIDC and JWT validation | — Pending |
| Deliberate chaos scenarios with hand-written runbooks | Highest-value component for someone holding certifications but lacking operational scar tissue; runbooks must be written by debugging, not by describing | — Pending |
| Same-day spin-up and destroy as a hard design constraint | Controls cost, and forces genuinely reproducible infrastructure — any manual step or undocumented drift surfaces immediately on the next rebuild | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-24 after initialization*
