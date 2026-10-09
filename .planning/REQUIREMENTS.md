# Requirements: AWS EKS E-Commerce Microservices Practice Platform

**Defined:** 2026-09-24
**Core Value:** Every AWS, Kubernetes, and DevOps concept in this project must be practiced end-to-end in a system that can be stood up and completely destroyed on the same day for a few dollars — if teardown or rebuild breaks, the entire practice loop dies with it.

---

## v1 Requirements

Requirements for Milestone 1. Each maps to a roadmap phase.

> **Note on framing.** This is a practice platform, not a product. "User" below means **the operator** — the person building and running this system — except in the E-Commerce category, where it means a shopper exercising the system. Requirements are written to be testable, because an untestable learning objective is indistinguishable from a wish.

### Cost Control

- [x] **COST-01**: Operator can see total idle cost stay at or below $5/month with the cluster destroyed, verified against a real billing period
- [ ] **COST-02**: Operator can run a `core` profile session at or below ~$0.23/hour with in-cluster Postgres and Redis, Prometheus and Tempo only
- [ ] **COST-03**: Operator can run a `full` profile session with RDS, ElastiCache, Loki, and WAF, accepting ~$0.29–0.33/hour bounded by session length
- [x] **COST-04**: A zero-spend AWS Budget and Cost Anomaly Detection at a $1 absolute threshold alert the operator within one day of unexpected spend
- [ ] **COST-05**: Every provisioned resource carries cost-allocation tags applied via Terraform `default_tags`, and spend can be attributed by layer
- [ ] **COST-06**: Karpenter `NodePool.spec.limits` caps total provisionable CPU and memory, so a runaway workload produces a bounded `NodePool limit exceeded` event rather than an unbounded bill
- [ ] **COST-07**: An EC2 instance-type allowlist prevents a resource-request typo from summoning an oversized instance
- [ ] **COST-08**: The project runs in a dedicated AWS account, isolating spend and making a blunt sweep script safe
- [x] **COST-09**: `COSTS.md` records measured `make up` and `make down` wall-clock times and real observed costs per session profile

### Lifecycle

- [ ] **LIFE-01**: Operator can provision the entire stack with a single `make up` completing in 20 minutes or less
- [ ] **LIFE-02**: Operator can destroy every billable resource with a single `make down` completing in 15 minutes or less
- [ ] **LIFE-03**: `make down` executes an explicit ordered sequence — disable Argo auto-sync, drain Ingresses, drain Karpenter NodePools, drain PVCs, destroy L3→L2→L1, verify — rather than a bare `terraform destroy`
- [ ] **LIFE-04**: Each drain step polls to an AWS-API-confirmed terminal state rather than firing and forgetting, because `kubectl delete ingress` returns before the ALB is gone
- [ ] **LIFE-05**: `sh/verify-teardown.sh` exits non-zero when any orphaned resource survives, checking ALBs, target groups, controller-created security groups, EC2 instances, EBS volumes, snapshots, Elastic IPs, ENIs, and CloudWatch log groups
- [ ] **LIFE-06**: Operator can complete two consecutive clean up/down round-trips on an empty cluster with zero orphans before any application code is written
- [x] **LIFE-07**: Terraform state is split into four lifetime-aligned layers — `00-bootstrap` (never destroyed), `10-infra`, `20-data`, `30-gitops`
- [x] **LIFE-08**: Remote state lives in a versioned S3 bucket using native `use_lockfile` locking, with no DynamoDB lock table
- [ ] **LIFE-09**: Slow-to-delete and near-free resources (CloudFront, ECR, S3) live in `00-bootstrap` and never enter the daily loop
- [ ] **LIFE-10**: A rebuild weeks later produces an identical stack, with all provider and module versions pinned in `VERSIONS.md`

### Network

- [ ] **NET-01**: VPC spans 2 availability zones with `/20` private subnets sized to survive VPC CNI warm-pool IP consumption
- [ ] **NET-02**: Intra subnets with no default route host the data stores
- [ ] **NET-03**: A fck-nat `t4g.nano` ASG provides egress, with route tables targeting the ENI rather than an instance ID so replacement does not break routing
- [ ] **NET-04**: S3 and DynamoDB gateway endpoints are enabled (free); the S3 endpoint is mandatory because ECR image layers are served from S3
- [ ] **NET-05**: Interface VPC endpoints are available behind a default-off flag, with their real cost documented, so the operator can enable them for one deliberate comparison session
- [ ] **NET-06**: A single shared ALB serves all services via IngressGroup, with one anchor Ingress owning every Exclusive annotation
- [ ] **NET-07**: Subnet discovery tags use a deterministic cluster name so the AWS Load Balancer Controller finds subnets on every rebuild

### EKS Platform

- [ ] **EKS-01**: Cluster is pinned to Kubernetes 1.34 and never floats, provisioned by `terraform-aws-modules/eks` v21
- [ ] **EKS-02**: A system managed node group runs on on-demand instances, tainted `CriticalAddonsOnly`, hosting CoreDNS, the ALB Controller, Karpenter, and Argo CD controllers
- [ ] **EKS-03**: Karpenter provisions all Spot capacity using the `karpenter.sh/v1` API, with `consolidateAfter: 5m`, a disruption budget, `expireAfter` paired with `terminationGracePeriod`, resource limits, and at least 10 instance types across 2 or more families
- [ ] **EKS-04**: Karpenter's AWS-side resources (IAM, interruption SQS queue, EventBridge rules) are defined in Terraform, not the upstream CloudFormation template
- [ ] **EKS-05**: A Spot interruption drains the affected node gracefully without dropping an in-flight request, verified by observation rather than assumption
- [ ] **EKS-06**: PodDisruptionBudgets use `maxUnavailable: 1` for single-replica workloads and `minAvailable: 1` only at 2 or more replicas
- [ ] **EKS-07**: The observability stack runs on its own tainted Karpenter NodePool with its own limits, so it cannot silently starve application workloads
- [ ] **EKS-08**: EKS managed addons including the Pod Identity Agent are installed and version-pinned

### Ownership Boundary

- [ ] **OWN-01**: Terraform manages the AWS API and Argo CD manages the Kubernetes API, with the only seam a `30-gitops` layer containing exactly two resources
- [ ] **OWN-02**: The Terraform `kubernetes` and `helm` providers are absent from every layer except `30-gitops`, so no layer requires a live API server at plan time
- [ ] **OWN-03**: A written ownership table in the README states which system owns each resource class, authored before the first Argo Application

### Delivery

- [ ] **CD-01**: Argo CD deploys everything in-cluster via app-of-apps, with sync waves ordering CRDs before the resources that use them
- [ ] **CD-02**: `make up` completes only when `argocd app wait root --health` returns, not when Terraform returns
- [ ] **CD-03**: The Argo CD admin password is pinned deterministically from Parameter Store, so a rebuild does not require hunting for a generated secret
- [ ] **CD-04**: GitHub Actions builds, tests, scans, and publishes each service image to ECR on arm64 runners
- [ ] **CD-05**: GitHub Actions authenticates to AWS via OIDC with a trust policy scoped to a specific repository and branch — no long-lived access keys exist anywhere
- [ ] **CD-06**: Terraform plan runs on pull requests and apply runs on merge, both through the same OIDC path
- [ ] **CD-07**: An Argo Rollouts canary on `catalog`, gated by a Prometheus `AnalysisTemplate`, automatically aborts and rolls back a deliberately broken build
- [ ] **CD-08**: Argo CD reconnects and re-bootstraps cleanly against a freshly rebuilt cluster with no manual intervention

### E-Commerce Services

- [ ] **SVC-01**: Shopper can browse a product catalog served by `catalog` from DynamoDB, scaled by an HPA
- [ ] **SVC-02**: Shopper can add and remove items from a cart served by `cart` from Redis with TTL expiry
- [ ] **SVC-03**: Shopper can place an order through `order`, receiving an order ID immediately while fulfilment proceeds asynchronously
- [ ] **SVC-04**: `inventory` reserves and releases stock against DynamoDB using conditional writes on a version attribute, rejecting concurrent conflicting updates
- [ ] **SVC-05**: `payment-sim` authorizes, captures, and voids payments, with failure modes configurable at runtime without a redeploy
- [ ] **SVC-06**: `api-gateway` (Spring Cloud Gateway Server Web MVC) routes all traffic, validates Cognito JWTs, and applies rate limiting
- [ ] **SVC-07**: `notification` — a Python Lambda — reacts to `OrderConfirmed` off EventBridge with zero knowledge in `order` that it exists, proving loose coupling
- [ ] **SVC-08**: A minimal React + Vite SPA served from S3 behind CloudFront with OAC exercises the full backend
- [ ] **SVC-09**: All six Spring Boot services share a parent POM with a common container template — JVM sizing, startup/readiness/liveness probes, `preStop` hook, and graceful shutdown configured once
- [ ] **SVC-10**: A rolling deploy of any service completes without dropping an in-flight request

### Event Backbone

- [ ] **EVT-01**: An explicit event envelope contract — `{ eventId, eventType, traceparent, version, occurredAt, payload }` — is defined before the second service is written
- [ ] **EVT-02**: SNS fan-out, SQS queues per consumer, and EventBridge rules form the documented topology
- [ ] **EVT-03**: Every queue has a dead-letter queue with a configured redrive policy and exponential backoff
- [ ] **EVT-04**: The operator has actually executed a DLQ redrive, not merely configured one
- [ ] **EVT-05**: `order` publishes events via a transactional outbox using a polling publisher with `FOR UPDATE SKIP LOCKED`, so no event is lost when the database commits
- [ ] **EVT-06**: `traceparent` is stored as a column in the outbox table, because the relay publishes long after the original trace context is gone

### Saga

- [ ] **SAGA-01**: The order flow executes `ReserveInventory → AuthorizePayment → CapturePayment (pivot) → ConfirmOrder → emit OrderConfirmed`
- [ ] **SAGA-02**: Inventory is reserved before payment is touched, because releasing a reservation always succeeds and refunding money does not
- [ ] **SAGA-03**: Authorize and Capture are separate steps, so compensation is a void rather than a refund and the pivot transaction is explicit
- [ ] **SAGA-04**: A failure before the pivot triggers compensations `ReleaseInventory` and `VoidAuthorization`, leaving no stranded reservation or authorization
- [ ] **SAGA-05**: Saga state persists in `saga_instance` and `saga_step_log`, so progress survives a pod restart mid-saga
- [ ] **SAGA-06**: A timeout sweeper advances or compensates sagas stalled beyond a threshold
- [ ] **SAGA-07**: A failed compensation transitions the saga to `COMPENSATION_FAILED`, raises an alert, and lands in a manual queue rather than failing silently
- [ ] **SAGA-08**: Idempotency is enforced at three layers — an API `Idempotency-Key`, a producer-generated `event_id`, and a store-native conditional write — so a duplicate SQS delivery cannot double-charge or double-reserve
- [ ] **SAGA-09**: `payment-sim` can be made to fail the *void* specifically, so the compensation-fails path is genuinely exercised rather than theoretical

### Observability

- [ ] **OBS-01**: Prometheus and Tempo are running before the second service is deployed, so the very first cross-service call produces a trace
- [ ] **OBS-02**: A single `curl -X POST /api/orders` produces one trace spanning gateway → order → EventBridge → SQS → inventory
- [ ] **OBS-03**: An automated assertion against the Tempo API verifies that a single `traceID` contains spans from all four services, failing CI if propagation breaks
- [ ] **OBS-04**: `traceparent` is injected and extracted manually across the EventBridge boundary, since `PutEvents` has no message-attribute channel
- [ ] **OBS-05**: Tempo and Loki are backed by S3 rather than EBS PVCs, so yesterday's traces and logs survive teardown and no AZ-pinned volume is orphaned
- [ ] **OBS-06**: Loki runs in `SingleBinary` mode with Grafana Alloy collecting logs (the chart default `SimpleScalable` is deprecated; Promtail reaches EOL 2026-03-02)
- [ ] **OBS-07**: Prometheus scrape config omits etcd, scheduler, and controller-manager jobs, because EKS does not expose them and permanently-red panels train the operator to ignore red
- [ ] **OBS-08**: Three RED/USE dashboards exist that the operator wrote and can defend, rather than forty imported ones
- [ ] **OBS-09**: An alert fires when any DLQ depth exceeds zero
- [ ] **OBS-10**: Prometheus exemplars link a metric spike to the exact trace in one click
- [ ] **OBS-11**: Cardinality guards (`enforcedSampleLimit`, `enforcedLabelLimit`) prevent a naive label from exhausting Prometheus memory
- [ ] **OBS-12**: Metrics are written to S3-backed long-term storage, so SLO burn-rate alerting has real multi-day history rather than a compressed window
- [ ] **OBS-13**: A multi-window multi-burn-rate SLO alert fires against real history and the operator has seen it fire
- [ ] **OBS-14**: Measured `kubectl top` figures for the platform stack are recorded, correcting the ~2.1 vCPU / 6.1 GiB estimate with real numbers

### Security

- [ ] **SEC-01**: Every service assumes a least-privilege IAM role via EKS Pod Identity, with no wildcard resource ARNs
- [ ] **SEC-02**: One service is wired with IRSA as a deliberate named exercise, then discarded — documenting why its OIDC-bound trust policy breaks on every rebuild
- [ ] **SEC-03**: External Secrets Operator syncs from SSM Parameter Store, with no secret material in Git or in plain ConfigMaps
- [ ] **SEC-04**: The EKS public API endpoint is restricted to the operator's IP, not `0.0.0.0/0`
- [ ] **SEC-05**: EKS envelope encryption is enabled for Kubernetes secrets
- [ ] **SEC-06**: Trivy scans images in CI and ECR scans on push, failing the build on high or critical CVEs
- [ ] **SEC-07**: Trivy `config` and Checkov both scan Terraform in CI, blocking insecure infrastructure — and their disagreements are documented, because that contrast is the lesson
- [ ] **SEC-08**: NetworkPolicies enforce default-deny namespace by namespace, each accompanied by a **negative test** proving traffic is actually blocked — because the dangerous failure is policies that appear to work while enforcing nothing
- [ ] **SEC-09**: Kyverno runs in Audit mode first, with system namespaces excluded and `failurePolicy: Ignore`, before any policy moves to Enforce
- [ ] **SEC-10**: A Kyverno policy rejects Exclusive ALB annotations on non-anchor IngressGroup members
- [ ] **SEC-11**: AWS WAF with OWASP managed rules and rate limiting protects the anchor Ingress
- [ ] **SEC-12**: Cognito authenticates shoppers at the gateway, with ALB-native auth protecting platform paths
- [ ] **SEC-13**: A documented break-glass procedure removes a lockout-causing admission webhook, kept at the top of the runbook

### Testing

- [ ] **TEST-01**: Unit and integration tests run in CI for every service, with Testcontainers 2.0.5 providing real Postgres and Redis
- [ ] **TEST-02**: LocalStack covers the outbox poller and idempotent consumers without AWS
- [ ] **TEST-03**: Spring Cloud Contract verifies inter-service contracts without hosting a broker
- [ ] **TEST-04**: Event-schema backward-compatibility tests fail when a producer change would break an existing consumer
- [ ] **TEST-05**: An E2E smoke suite runs against a freshly provisioned cluster and gates deployment, covering both the happy path and the compensated-failure path
- [ ] **TEST-06**: A chaos scenario runs as an automated test in CI

### Chaos & Runbooks

- [ ] **CHAOS-01**: Chaos Mesh provides in-cluster faults as GitOps-managed CRDs
- [ ] **CHAOS-02**: AWS FIS delivers an authentic 2-minute Spot interruption notice via `aws:ec2:send-spot-instance-interruptions`
- [ ] **CHAOS-03**: FIS experiment templates live permanently in Terraform, since they bill only per action-minute and cost nothing at rest
- [ ] **CHAOS-04**: k6 generates enough load to actually cause optimistic-locking conflicts, which do not occur at 1 RPS
- [ ] **CHAOS-05**: At least five scenarios are executed and debugged — a Spot interruption mid-saga, a payment that timed out but actually succeeded, an SQS consumer killed between processing and delete, a DNS failure, latency injected on inventory, and an OOMKill
- [ ] **CHAOS-06**: Each scenario has a runbook written *during* the debugging, not after, that a cold reader could follow
- [ ] **CHAOS-07**: At least one runbook documents a hypothesis that turned out to be wrong, and what the evidence actually showed

---

## v2 Requirements

Deferred to a future milestone. Tracked but not in the current roadmap.

### Services

- **V2-SVC-01**: Dedicated `auth` service replacing gateway-level Cognito validation
- **V2-SVC-02**: `image-processor` Python Lambda triggered by S3 events with presigned upload URLs
- **V2-SVC-03**: `search` service backed by OpenSearch
- **V2-SVC-04**: `reviews` and `recommendations` services

### Security

- **V2-SEC-01**: Falco runtime threat detection
- **V2-SEC-02**: GuardDuty EKS Protection and Security Hub
- **V2-SEC-03**: Cosign image signing and SBOM generation
- **V2-SEC-04**: Service mesh mTLS via Istio or Linkerd

### Platform

- **V2-PLAT-01**: In-place Kubernetes upgrade 1.34 → 1.35 → 1.36 as a deliberate exercise
- **V2-PLAT-02**: OpenCost or Kubecost exporting cost as a Grafana dashboard
- **V2-PLAT-03**: Infracost as a CI gate failing pull requests that breach the project's stated cost ceiling
- **V2-PLAT-04**: Multi-environment promotion (dev → staging) via Argo CD ApplicationSets

---

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real payment provider integration | No PCI surface wanted; `payment-sim` exists to be broken on purpose, which is more instructive |
| Custom domain names | Registrar cost and DNS propagation friction on a stack destroyed daily |
| Amazon MSK / managed Kafka | ~$180/month destroys the cost model; SNS/SQS/EventBridge teaches the same async patterns |
| Self-hosted Strimzi/Kafka as a "cheap Kafka" | The trap hiding behind the MSK exclusion — broker state on daily-destroyed Spot nodes teaches Kafka operations, not this system |
| Interface VPC endpoints in the default stack | ~$7.30/month each per AZ; five across two AZs is ~$73/month, 24× the NAT instance they were meant to replace. Available behind a default-off flag |
| AWS Secrets Manager as primary secret store | $0.40/secret/month — ten secrets consume the entire idle budget; Parameter Store teaches the identical pattern for free |
| Amazon Managed Grafana / AMP | Self-hosting is cheaper and is where the learning lives |
| Managed NAT Gateway | ~$32/month idle vs ~$3/month for fck-nat, which also forces real VPC understanding |
| EKS Auto Mode and Fargate | Both abstract away the node-level control and DaemonSet support this project exists to practice |
| DynamoDB state lock table | Deprecated in favour of S3 native `use_lockfile`; also one more immortal resource |
| tfsec | Deprecated and absorbed into Trivy |
| Promtail | Reaches EOL 2026-03-02; Grafana Alloy replaces it |
| Debezium CDC for the outbox | Requires `wal_level = logical`, a custom parameter group, and an instance reboot on every `make up` |
| Canary deployment on saga services | Mid-saga version skew and cross-version event-schema compatibility is a rabbit hole, not a phase; canary is practised on `catalog` |
| Full Pact contract testing with a broker | Solves an inter-team problem a single author does not have, and a broker is one more service to destroy daily |
| Custom operators, custom chaos frameworks, Backstage | Enormous effort, little learning relative to cost |
| Rich frontend UX | The UI exists only to exercise the backend |
| Multi-region / active-active DR | Cost and complexity outweigh the learning at this stage |
| Real users, real traffic, production SLAs | This is a practice environment, not a product |
| Keeping an EBS PVC alive across teardowns | Precisely the orphan pattern that kills the project; S3 backing solves the same problem safely |
| Cost-cutting below 2 nodes / 2 replicas / 2 AZs | Optimises away pod eviction, PDBs, Spot interruption, and rolling updates — i.e. all of the learning |
| Deadlines and delivery pressure | Open-ended practice; correctness and depth beat speed |

---

## Open Decisions

Deliberately unresolved. Each is a decision gate during its phase, not a detail to be assumed away.

| ID | Question | Resolution path |
|----|----------|-----------------|
| **OQ1** | Is RDS viable under same-day teardown? Create is ~6–10 min, delete ~5 min. | `var.use_rds` defaults false. Measure real timings in the infra phase, record in `COSTS.md`, flip the default if total `make up` stays under 20 min. |
| **OQ2** | Prometheus TSDB dies nightly, but SLO burn-rate alerting needs multi-day history. | Resolved in principle — S3-backed long-term storage (OBS-12). Deferred to the observability-depth phase. Until then, burn-rate rules are written against a compressed window and the limitation is recorded. |
| **OQ3** | ElastiCache or in-cluster Redis? | Cut from the default profile, module retained behind a toggle. Reverse freely if `make up` time proves not to be the binding constraint. |
| **OQ4** | Does the full observability stack plus six JVM services actually fit the node shape? | Unresolved until measured. All three researcher estimates (2.1 / 2.5–4 / 3.5–6.5 GiB) are hypotheses. Sequence signals separately and record real figures (OBS-14). |
| **OQ5** | Does OTel trace context survive SNS/SQS/EventBridge? | Resolved in approach (manual envelope, OBS-04), unverified in practice. Highest-priority research flag. Note the false negative: OTel often creates a **Link** rather than a parent-child relationship, and Tempo does not render linked spans as one trace by default — check before concluding propagation is broken. |
| **OQ6** | Spring Boot 4.1.1 or fall back to 3.5.16? | Pin the whole set in a shared parent POM. If third-party starters break, fall back as a *set*, not piecemeal. |

---

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| COST-01 | Phase 1 | Complete |
| COST-02 | Phase 5 | Pending |
| COST-03 | Phase 10 | Pending |
| COST-04 | Phase 1 | Complete |
| COST-05 | Phase 1 | Pending |
| COST-06 | Phase 8 | Pending |
| COST-07 | Phase 8 | Pending |
| COST-08 | Phase 1 | Pending |
| COST-09 | Phase 1 | Complete |
| LIFE-01 | Phase 2 | Pending |
| LIFE-02 | Phase 2 | Pending |
| LIFE-03 | Phase 2 | Pending |
| LIFE-04 | Phase 2 | Pending |
| LIFE-05 | Phase 1 | Pending |
| LIFE-06 | Phase 2 | Pending |
| LIFE-07 | Phase 1 | Complete |
| LIFE-08 | Phase 1 | Complete |
| LIFE-09 | Phase 1 | Pending |
| LIFE-10 | Phase 1 | Pending |
| NET-01 | Phase 2 | Pending |
| NET-02 | Phase 2 | Pending |
| NET-03 | Phase 2 | Pending |
| NET-04 | Phase 2 | Pending |
| NET-05 | Phase 2 | Pending |
| NET-06 | Phase 4 | Pending |
| NET-07 | Phase 2 | Pending |
| EKS-01 | Phase 2 | Pending |
| EKS-02 | Phase 2 | Pending |
| EKS-03 | Phase 8 | Pending |
| EKS-04 | Phase 2 | Pending |
| EKS-05 | Phase 8 | Pending |
| EKS-06 | Phase 8 | Pending |
| EKS-07 | Phase 9 | Pending |
| EKS-08 | Phase 2 | Pending |
| OWN-01 | Phase 4 | Pending |
| OWN-02 | Phase 2 | Pending |
| OWN-03 | Phase 4 | Pending |
| CD-01 | Phase 4 | Pending |
| CD-02 | Phase 4 | Pending |
| CD-03 | Phase 4 | Pending |
| CD-04 | Phase 3 | Pending |
| CD-05 | Phase 1 | Pending |
| CD-06 | Phase 3 | Pending |
| CD-07 | Phase 12 | Pending |
| CD-08 | Phase 4 | Pending |
| SVC-01 | Phase 11 | Pending |
| SVC-02 | Phase 11 | Pending |
| SVC-03 | Phase 6 | Pending |
| SVC-04 | Phase 5 | Pending |
| SVC-05 | Phase 6 | Pending |
| SVC-06 | Phase 6 | Pending |
| SVC-07 | Phase 11 | Pending |
| SVC-08 | Phase 11 | Pending |
| SVC-09 | Phase 3 | Pending |
| SVC-10 | Phase 8 | Pending |
| EVT-01 | Phase 5 | Pending |
| EVT-02 | Phase 5 | Pending |
| EVT-03 | Phase 5 | Pending |
| EVT-04 | Phase 7 | Pending |
| EVT-05 | Phase 7 | Pending |
| EVT-06 | Phase 7 | Pending |
| SAGA-01 | Phase 7 | Pending |
| SAGA-02 | Phase 7 | Pending |
| SAGA-03 | Phase 7 | Pending |
| SAGA-04 | Phase 7 | Pending |
| SAGA-05 | Phase 7 | Pending |
| SAGA-06 | Phase 7 | Pending |
| SAGA-07 | Phase 7 | Pending |
| SAGA-08 | Phase 7 | Pending |
| SAGA-09 | Phase 7 | Pending |
| OBS-01 | Phase 5 | Pending |
| OBS-02 | Phase 6 | Pending |
| OBS-03 | Phase 6 | Pending |
| OBS-04 | Phase 6 | Pending |
| OBS-05 | Phase 5 | Pending |
| OBS-06 | Phase 9 | Pending |
| OBS-07 | Phase 5 | Pending |
| OBS-08 | Phase 9 | Pending |
| OBS-09 | Phase 9 | Pending |
| OBS-10 | Phase 9 | Pending |
| OBS-11 | Phase 9 | Pending |
| OBS-12 | Phase 9 | Pending |
| OBS-13 | Phase 9 | Pending |
| OBS-14 | Phase 9 | Pending |
| SEC-01 | Phase 10 | Pending |
| SEC-02 | Phase 10 | Pending |
| SEC-03 | Phase 10 | Pending |
| SEC-04 | Phase 10 | Pending |
| SEC-05 | Phase 10 | Pending |
| SEC-06 | Phase 3 | Pending |
| SEC-07 | Phase 3 | Pending |
| SEC-08 | Phase 10 | Pending |
| SEC-09 | Phase 10 | Pending |
| SEC-10 | Phase 10 | Pending |
| SEC-11 | Phase 10 | Pending |
| SEC-12 | Phase 10 | Pending |
| SEC-13 | Phase 10 | Pending |
| TEST-01 | Phase 14 | Pending |
| TEST-02 | Phase 14 | Pending |
| TEST-03 | Phase 14 | Pending |
| TEST-04 | Phase 14 | Pending |
| TEST-05 | Phase 14 | Pending |
| TEST-06 | Phase 14 | Pending |
| CHAOS-01 | Phase 13 | Pending |
| CHAOS-02 | Phase 13 | Pending |
| CHAOS-03 | Phase 13 | Pending |
| CHAOS-04 | Phase 12 | Pending |
| CHAOS-05 | Phase 13 | Pending |
| CHAOS-06 | Phase 13 | Pending |
| CHAOS-07 | Phase 13 | Pending |

**Coverage:**

- v1 requirements: 110 total
- Mapped to phases: 110 ✅
- Unmapped: 0
- Duplicated across phases: 0

**Per-phase counts:** P1: 11 · P2: 16 · P3: 5 · P4: 7 · P5: 8 · P6: 6 · P7: 12 · P8: 6 · P9: 9 · P10: 12 · P11: 4 · P12: 2 · P13: 6 · P14: 6

---
*Requirements defined: 2026-09-24*
*Last updated: 2026-09-24 after initialization*
