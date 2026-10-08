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

- [ ] Entire stack provisioned by Terraform with remote state in S3 using native `use_lockfile` locking plus bucket versioning, surviving teardown
- [ ] Terraform split into four lifetime-aligned layers — `00-bootstrap` (never destroyed), `10-infra`, `20-data`, `30-gitops` (daily)
- [ ] `make up` lifecycle provisioning the full stack in ≤ 20 minutes
- [ ] `make down` lifecycle as an explicit 7-step sequence — disable Argo auto-sync → drain Ingresses → drain Karpenter NodePools → drain PVCs → destroy L3→L2→L1 → verify — with each drain polling to an AWS-API-confirmed terminal state, completing in ≤ 15 minutes
- [ ] `scripts/verify-teardown.sh` exiting non-zero on any orphaned resource, written before there is anything to tear down
- [ ] Session profiles with `$/session` as the primary budget unit — Profile A `core` (~$0.22/hr, the default), Profile B `full` (~$0.29–0.33/hr, occasional), Profile C `managed`
- [ ] Idle cost ≤ ~$5/month
- [ ] VPC across 2 AZs with `/20` private subnets, fck-nat instance (t4g.nano) for egress, and **gateway endpoints only** (S3 + DynamoDB, free); interface endpoints behind a default-off flag
- [ ] Cost guardrails — dedicated AWS account, zero-spend AWS Budget, Cost Anomaly Detection at a $1 absolute threshold, cost allocation tags, Karpenter `NodePool.spec.limits`, and an EC2 instance-type allowlist

**EKS Platform**

- [ ] EKS cluster pinned to Kubernetes 1.34, provisioned via `terraform-aws-modules/eks` v21
- [ ] System managed node group on **on-demand** instances, tainted `CriticalAddonsOnly` — Karpenter cannot provision the node it runs on
- [ ] Karpenter (v1 API) provisioning all Spot capacity, with `consolidateAfter: 5m`, disruption budgets, `expireAfter` paired with `terminationGracePeriod`, `limits`, and ≥10 instance types across ≥2 families
- [ ] Spot interruption handling via a Terraform-managed SQS interruption queue and EventBridge rules
- [ ] AWS Load Balancer Controller fronting the cluster with a single shared ALB via IngressGroup, using an anchor Ingress that owns all Exclusive annotations
- [ ] Platform addons managed declaratively — Argo CD, External Secrets Operator, Kyverno, metrics-server, EBS CSI driver, EKS Pod Identity Agent
- [ ] A written Terraform-vs-Argo CD ownership table, authored before the first Argo Application

**Core Services (Milestone 1)**

- [ ] `api-gateway` — Spring Cloud Gateway handling routing, JWT validation against Cognito, and rate limiting
- [ ] `catalog` — Spring Boot over DynamoDB, read-heavy, HPA-scaled
- [ ] `cart` — Spring Boot over Redis with TTL-based ephemeral state; in-cluster Redis by default, ElastiCache behind a toggle
- [ ] `order` — Spring Boot over Postgres, acting as saga orchestrator with the transactional outbox pattern; in-cluster Postgres by default, RDS behind `var.use_rds`
- [ ] `payment-sim` — Spring Boot fake payment service with deliberate, configurable failure injection
- [ ] `inventory` — Spring Boot over DynamoDB using optimistic locking and compensating transactions
- [ ] `notification` — Python Lambda consuming EventBridge/SQS events, sending via SES/SNS
- [ ] `frontend` — React + Vite SPA served from S3 behind CloudFront, deliberately minimal

**Event-Driven Communication**

- [ ] SNS + SQS + EventBridge as the asynchronous backbone between services
- [ ] An explicit event envelope contract — `{ eventId, eventType, traceparent, version, occurredAt, payload }` — designed before the second service exists
- [ ] Saga with a genuine pivot transaction — `ReserveInventory → AuthorizePayment → CapturePayment (PIVOT) → ConfirmOrder → OrderConfirmed`, compensated by `ReleaseInventory` and `VoidAuthorization`
- [ ] Persisted saga state machine (`saga_instance`, `saga_step_log`) plus a timeout sweeper and an explicit `COMPENSATION_FAILED` state with alerting
- [ ] Dead-letter queues on every queue, retry with exponential backoff, an actually-executed redrive, and three-layer idempotency (API key → producer event ID → store-native conditional write)
- [ ] Transactional outbox in `order` via a polling publisher using `FOR UPDATE SKIP LOCKED`, with `traceparent` stored as an outbox column

**CI/CD**

- [ ] GitHub Actions pipelines for build, test, container image publish to ECR, and Terraform plan/apply, running on arm64 runners
- [ ] Argo CD performing pull-based GitOps deployment via app-of-apps with sync waves
- [ ] OIDC federation between GitHub Actions and AWS IAM — no long-lived access keys anywhere
- [ ] Argo Rollouts canary on `catalog`, gated by a Prometheus `AnalysisTemplate` that automatically aborts and rolls back a deliberately broken build

**Observability**

- [ ] Self-hosted in-cluster stack — Prometheus and Tempo first, Loki later; Loki in `SingleBinary` mode, Tempo monolithic, both backed by S3 rather than EBS
- [ ] Grafana Alloy for log collection (Promtail reaches EOL 2026-03-02)
- [ ] The observability stack on its own tainted Karpenter NodePool with its own limits, so it cannot starve application workloads
- [ ] OpenTelemetry instrumentation across all Spring Boot services producing distributed traces
- [ ] Manual `traceparent` injection and extraction across the EventBridge/SQS boundary — `PutEvents` has no message-attribute channel, so broker-level propagation cannot be relied on
- [ ] A single trace spanning gateway → order → EventBridge → SQS → inventory, asserted automatically against the Tempo API
- [ ] Grafana dashboards for RED/USE metrics, DLQ-depth alerts on every DLQ, and Prometheus exemplars linking metrics to traces
- [ ] S3-backed long-term metric storage (Thanos or remote-write) so SLO burn-rate alerting has real multi-day history

**Security**

- [ ] EKS Pod Identity giving each service least-privilege, pod-scoped IAM; IRSA implemented once as a deliberate named exercise, then discarded
- [ ] External Secrets Operator syncing from SSM Parameter Store (free tier) — zero secrets in Git; Secrets Manager reserved for ≤2 genuinely rotating credentials
- [ ] Trivy image scanning plus ECR scan-on-push, failing CI on high/critical CVEs
- [ ] Kubernetes NetworkPolicies enforcing zero-trust pod-to-pod networking, applied namespace by namespace, each with a **negative enforcement test** proving the policy actually blocks
- [ ] Kyverno admission policies enforcing pod security standards and image provenance — **Audit mode first**, system namespaces excluded, `failurePolicy: Ignore`
- [ ] AWS WAF on the ALB/CloudFront with OWASP managed rules and rate limiting
- [ ] Trivy `config` scanning plus Checkov as a second opinion, blocking insecure Terraform in CI (tfsec is deprecated and absorbed into Trivy)

**Testing**

- [ ] Unit and integration tests for Spring Boot services using Testcontainers, plus LocalStack for the outbox poller and idempotent consumers
- [ ] Contract testing via Spring Cloud Contract, plus event-schema backward-compatibility tests
- [ ] A smoke/E2E suite covering both the happy path and the compensated-failure path, gating deployment against a freshly provisioned cluster

**Chaos & Troubleshooting**

- [ ] Break-glass module with injectable failures via Chaos Mesh and AWS FIS — including authentic 2-minute Spot interruption notices, plus network latency, dependency outages, OOMKills, and DNS failures
- [ ] At least five scenarios ranked by learning value, with the centrepiece being a Spot interruption *mid-saga* and a payment that timed out but actually succeeded
- [ ] A written runbook per scenario, authored by actually debugging the failure rather than describing it in theory — a phase is not complete until its runbook exists

### Out of Scope

- **Real payment provider integration** — no PCI surface wanted; `payment-sim` exists to be broken on purpose, which is more instructive
- **Custom domain names** — avoids registrar cost and DNS propagation friction on a stack that is destroyed daily
- **Amazon MSK / managed Kafka** — roughly $180/month destroys the cost model; SNS/SQS/EventBridge teaches the same async patterns
- **Self-hosted Strimzi/Kafka as a "cheap Kafka"** — the trap hiding behind the MSK exclusion; broker state on daily-destroyed Spot nodes is a nightmare that teaches operations of Kafka rather than of this system
- **Interface VPC endpoints in the default stack** — ~$7.30/month each per AZ; five across two AZs is ~$73/month, 24× the fck-nat instance they were meant to complement. Available behind a default-off flag for one deliberate session
- **AWS Secrets Manager as the primary secret store** — $0.40/secret/month means ten secrets consume the entire idle budget; Parameter Store teaches the identical pattern for free
- **Amazon Managed Grafana / AMP** — self-hosting the stack is both cheaper and where the actual learning lives
- **Managed NAT Gateway** — ~$32/month idle; a fck-nat instance costs ~$3/month and forces real VPC understanding
- **EKS Auto Mode and Fargate** — both abstract away the node-level control and DaemonSet support this project is meant to practice
- **Canary deployment on the saga services** — mid-saga version skew and event-schema compatibility across versions is a legitimately hard problem and a rabbit hole, not a phase; canary is practised on `catalog` instead
- **Full Pact contract testing with a broker** — solves an inter-team problem a single author does not have, and a broker is one more service to host and destroy daily; Spring Cloud Contract plus event-schema compatibility tests give the same protection
- **Custom operators, custom chaos frameworks, and Backstage** — enormous effort, little learning relative to cost
- **Rich frontend UX** — the UI exists only to exercise the backend; effort belongs in infrastructure and distributed systems
- **Multi-region / active-active DR** — cost and complexity outweigh the learning at this stage
- **Real users, real traffic, production SLAs** — this is a practice environment, not a product
- **Dedicated auth service** (deferred to M2) — Cognito validated at the gateway covers M1 needs
- **image-processor Lambda, OpenSearch search, reviews, recommendations** (deferred to M2) — additive surface, not needed to prove the core architecture
- **Falco, GuardDuty, Security Hub, Cosign/SBOM, service mesh mTLS** (deferred to M2) — valuable but would balloon M1 scope
- **Deadlines and delivery pressure** — this is open-ended practice; correctness and depth beat speed
- **Cost-cutting below the learning floor** — fewer than 2 nodes, 2 replicas of saga-critical services, or 2 AZs optimises away pod eviction, PDBs, Spot interruption, and rolling updates, which is all of the learning

## Context

**Operator background.** Holds AWS Solutions Architect Professional (SAP-C02) and Certified Kubernetes Administrator (CKA). Theory is solid across AWS services, Kubernetes primitives, and architecture patterns. The explicit gap is applied experience — building, operating, breaking, and fixing a real distributed system. This means the project should skip tutorials and beginner scaffolding, and instead lean into the areas certifications do not cover: day-2 operations, failure modes, debugging under uncertainty, and cost engineering.

**Starting state.** Effectively greenfield. The repository contains only a one-line `README.md` ("# AWS EKS Learning Project"), GSD tooling under `.github/`, and an empty `research/` directory. No application code, no infrastructure, no CI.

**Language preference.** Java Spring Boot for containerized backend services — it is the operator's strongest backend stack, so cognitive budget goes to infrastructure rather than language learning. Python reserved for lightweight Lambda functions. Frontend framework left to the agent's discretion; React + Vite chosen for familiarity and trivially cheap static hosting.

**The centrepiece.** The order → payment → inventory saga is where distributed-systems pain actually lives — partial failures, compensating transactions, idempotency, and eventual consistency. Troubleshooting scenarios are only meaningful because this saga exists to break.

**Working rhythm.** No deadline, no fixed hours. Work happens in sessions: spin up, practice, destroy the same day. This rhythm is the single strongest architectural constraint in the project.

**Research corrections absorbed.** Four parallel researchers (see `.planning/research/`) produced twelve factual corrections to the initial project definition, all applied above. The most consequential: interface VPC endpoints are ~24× the cost of the NAT instance they were meant to replace; IRSA is structurally incompatible with daily teardown because trust policies embed a cluster OIDC ID that changes on every rebuild; tfsec is deprecated; DynamoDB state locking is deprecated in favour of S3 native locking; and the flat hourly budget does not close for the full stack. Five open questions remain deliberately unresolved pending measurement — RDS viability under teardown, Prometheus retention vs SLO alerting, ElastiCache necessity, whether the observability stack plus six services fit the node shape, and trace propagation across EventBridge.

## Constraints

- **Budget**: Idle cost ≤ ~$5/month. Active cost is budgeted **per session, not per hour** — Profile A `core` ~$0.22/hr covers ~80% of sessions; Profile B `full` may reach ~$0.33/hr and is bounded by session length instead. The EKS control plane alone is 42–47% of hourly cost, so no instance-type tuning rescues a cluster left running — session discipline is the real lever
- **Account and billing**: Run the project in a newly created, dedicated AWS Organizations member account. The management account/payer stays outside Terraform and this repository; it owns consolidated payment, organization-level Cost Explorer enablement, cost-allocation tag management, and centralized root access. The member account sees only its own cost and usage data, subject to management-account access controls. Centrally credential-less member root accounts do not require `AccountMFAEnabled=1`; if member root credentials exist, require MFA. Keep account-specific IDs in the gitignored pin file, not in tracked project documents.
- **Lifecycle**: Every resource must be destroyable and reproducible on the same day — anything that cannot be cleanly torn down and rebuilt is a design defect, not an inconvenience. `make up` ≤ 20 minutes, `make down` ≤ 15 minutes; wall-clock is the scarcest resource in the project
- **Ownership boundary**: Terraform owns the AWS API, Argo CD owns the Kubernetes API, with exactly one seam — a two-resource `30-gitops` layer that installs Argo CD and nothing else. The Terraform `kubernetes`/`helm` providers need a live API server at plan time, and on destroy that server may already be gone, wedging state
- **Tech stack**: Java Spring Boot for containerized services, Python for Lambdas, Terraform for all infrastructure, React + Vite for the frontend — plays to existing strength so learning budget goes to AWS and Kubernetes
- **Tech stack**: No expensive managed services (MSK, Managed Grafana, NAT Gateway, multi-AZ RDS, interface VPC endpoints) — cost model dominates service selection
- **Security**: No long-lived AWS credentials anywhere; GitHub Actions authenticates via OIDC and pods via EKS Pod Identity — matches production practice and removes the most common leak vector
- **Security**: No secrets committed to Git; all secret material flows through SSM Parameter Store via External Secrets Operator
- **Scope**: No custom domains, no real payments, no real users — removes cost, compliance, and support surface that teaches nothing here
- **Learning floor**: Never fewer than 2 nodes, 2 replicas of saga-critical services, or 2 AZs — below that, the failure modes worth practising stop occurring
- **Learning-first**: When a cheaper-and-easier option and a harder-but-more-instructive option cost roughly the same, choose the instructive one — the entire point is difficulty

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| EKS with an on-demand system node group + Karpenter-provisioned Spot | Cheapest compute; forces real practice with bin-packing, interruption handling, and graceful shutdown. The system group must be on-demand because Karpenter cannot provision the node it runs on — Spot-reclaiming it deadlocks the cluster at zero capacity. Rejected Auto Mode (~12% premium, less control) and Fargate (no DaemonSet support, which would break the self-hosted observability stack) | — Pending |
| Polyglot persistence, but in-cluster by default | Most realistic e-commerce data architecture; each store teaches a different access pattern. However RDS (~6–10 min create) and ElastiCache (~8–12 min) consume a disproportionate share of a practice session, so both sit behind toggles with in-cluster Postgres/Redis as the default. DynamoDB stays always-on — fast and free at rest | — Pending |
| SNS + SQS + EventBridge as the event backbone | Near-free, AWS-native, and exercises fan-out, DLQs, and retry semantics. MSK ruled out purely on cost (~$180/month), and self-hosted Strimzi rejected as the trap hiding behind that exclusion | — Pending |
| GitHub Actions for CI, Argo CD for CD (GitOps) | Production-standard split; pull-based delivery is a significant learning win over push-based `kubectl apply` and keeps cluster credentials out of CI | — Pending |
| Terraform owns AWS, Argo CD owns Kubernetes, one two-resource seam | The Terraform `kubernetes`/`helm` providers require a live API server at plan time and may find it already deleted on destroy — the single most common way these stacks become un-teardownable | — Pending |
| Self-hosted Prometheus + Tempo first, Loki later, all S3-backed | Costs roughly nothing and teaches far more than managed equivalents. S3 backing avoids the AZ-pinned-EBS orphan class and lets yesterday's traces survive teardown. Sequencing the signals separately also lets each one's real footprint be measured | — Pending |
| fck-nat instance (t4g.nano), gateway endpoints only | Cuts ~$32/month to ~$3/month and forces genuine understanding of VPC routing. Interface endpoints were initially assumed to be the cheap alternative to NAT — they are not at this scale (~$7.30/month each per AZ, ~24× the NAT instance). The "endpoints instead of NAT" heuristic is correct at production volume and inverts here | — Pending |
| EKS Pod Identity throughout, IRSA as a one-off exercise | Beyond AWS's current recommendation: IRSA trust policies embed the cluster's OIDC provider ID, which changes on every rebuild, making IRSA actively hostile to a daily-teardown workflow. `terraform-aws-modules/eks` v21 also removed the Karpenter IRSA path entirely | — Pending |
| SSM Parameter Store over Secrets Manager | Secrets Manager costs $0.40/secret/month — ten secrets would consume the entire idle budget. The External Secrets Operator learning is identical either way | — Pending |
| Pin EKS to Kubernetes 1.34 | Chosen over 1.36 for rebuild reliability — 1.36 permanently disables `gitRepo` volumes and enables `StrictIPCIDRValidation`, which rejects CIDRs some third-party charts still ship. Extended support costs $0.60/hr, a 6× increase, so the 14-month window must be watched | — Pending |
| Trim Milestone 1 to 6 containerized services + 1 Lambda | Ten Spring Boot services is a lot of boilerplate before reaching the AWS work; the trimmed set still preserves the full saga and every infrastructure concern. Research strengthened this: the well-known reference implementations (Online Boutique, Sock Shop, Robot Shop) have no real saga at all, so depth of failure surface — not service count — is the differentiator | — Pending |
| Cognito validated at the API gateway rather than a dedicated auth service | Removes one service from M1 while still practising OIDC and JWT validation | — Pending |
| Deliberate chaos scenarios with hand-written runbooks | Highest-value component for someone holding certifications but lacking operational scar tissue; runbooks must be written by debugging, not by describing. A runbook documenting a *wrong* hypothesis is the highest-signal artifact in the repo | — Pending |
| Manual `traceparent` propagation rather than broker-level | EventBridge `PutEvents` has no message-attribute channel, and the transactional outbox publishes long after the original context is gone — so broker-level propagation cannot work. Three of four researchers flagged this as the most likely thing to silently break the flagship demo | — Pending |
| Same-day spin-up and destroy as a hard design constraint | Controls cost, and forces genuinely reproducible infrastructure — any manual step or undocumented drift surfaces immediately on the next rebuild | — Pending |
| Session profiles with `$/session` as the budget unit | The flat $0.30/hr ceiling does not close for the full stack (~$0.29/hr on estimates where only two line items were authoritatively verified — a rounding error, not a margin). Profiles preserve the learning floor rather than trimming the cluster below it | — Pending |

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
*Last updated: 2026-09-24 after research synthesis*
