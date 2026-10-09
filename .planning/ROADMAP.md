# Roadmap: AWS EKS E-Commerce Microservices Practice Platform

## Overview

This roadmap builds a day-2 operations practice rig wearing an e-commerce costume. It is sequenced
around a single constraint: **the stack must die cleanly every night and come back tomorrow.**
Accordingly it inverts the intuitive order — the teardown verifier is written before there is
anything to tear down (Phase 1), and a hard gate of two consecutive zero-orphan `up`/`down`
round-trips on an empty cluster blocks all application code (Phase 2). From there the project
drives the thinnest possible vertical slice through every architectural layer — Argo CD and a
walking skeleton through the real ALB (Phase 4), the event envelope plus minimal Prometheus and
Tempo *before* the second service (Phase 5), and then the flagship: one unbroken trace spanning
gateway → order → EventBridge → SQS → inventory (Phase 6). Only once that feedback loop exists does
the project thicken each layer — the full saga with compensation and a pivot transaction (Phase 7),
Karpenter Spot with graceful drain (Phase 8), observability depth (Phase 9), security hardening
deliberately late (Phase 10), and finally the payoff: five chaos scenarios debugged with runbooks
written *during* the debugging (Phase 13).

**Ordering principle:** if a phase can be moved after the trace moment, move it after the trace
moment. The deliberate exceptions are Phase 1 (teardown) and Phase 5 (event envelope + minimal
observability), both of which are ruinous to retrofit.

**Phase structure derived from** `.planning/research/SUMMARY.md` Part 3 (reconciled 13-phase build
order). Two deviations are documented in "Deviations from Research" below.

## Milestones

- 🚧 **v1.0 Practice Platform** — Phases 1-14 (in progress)

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Account, L0 Bootstrap & Teardown Harness** - Immortal layer, cost guardrails, and `verify-teardown.sh` written before anything exists to tear down
- [ ] **Phase 2: Ephemeral Infrastructure & Drain Scripts** - VPC, EKS 1.34, system node group, drain scripts — gated on two clean zero-orphan round-trips
- [ ] **Phase 3: Service Scaffolding & CI Pipeline** - Six Spring Boot skeletons on a shared parent POM, arm64 GitHub Actions build/scan/publish (∥ Phase 2)
- [ ] **Phase 4: GitOps Seam & Walking Skeleton** - Argo CD app-of-apps, shared ALB IngressGroup, first HTTP request through real infrastructure
- [ ] **Phase 5: Event Backbone & Minimal Observability** - Event envelope contract, Prometheus + Tempo, `order` and `inventory` deployed
- [ ] **Phase 6: ★ The Trace Moment** - One trace spanning gateway → order → EventBridge → SQS → inventory, asserted automatically
- [ ] **Phase 7: The Complete Saga** - Pivot transaction, compensation, outbox, three-layer idempotency, executed DLQ redrive
- [ ] **Phase 8: Karpenter, Spot & Graceful Drain** - Spot capacity with real interruption handling and bounded cost limits (∥ Phase 9)
- [ ] **Phase 9: Observability Depth** - Loki, dashboards, DLQ alerts, exemplars, S3-backed long-term metrics, measured footprint (∥ Phase 8)
- [ ] **Phase 10: Security Hardening** - Pod Identity, ESO, NetworkPolicies with negative tests, Kyverno audit-first, WAF, Cognito (∥ Phases 11, 14)
- [ ] **Phase 11: Storefront, Catalog, Cart & Notification Lambda** - The choreographed contrast plus a minimal SPA that exercises the full backend (∥ Phases 10, 14)
- [ ] **Phase 12: Progressive Delivery & Load Generation** - Canary on `catalog` that auto-aborts on a broken build, k6 load heavy enough to cause real conflicts
- [ ] **Phase 13: Chaos Scenarios & Runbooks** - Five scenarios executed and debugged, runbooks written during the debugging (∥ Phase 14)
- [ ] **Phase 14: Testing Depth** - Testcontainers, LocalStack, contract tests, E2E gate covering both happy and compensated paths (∥ Phase 13)

## Phase Details

### Phase 1: Account, L0 Bootstrap & Teardown Harness

**Goal**: The operator has an isolated, cost-guardrailed AWS account with an immortal bootstrap layer, and can prove teardown correctness before there is anything to tear down
**Depends on**: Nothing (first phase)
**Requirements**: COST-01, COST-04, COST-05, COST-08, COST-09, LIFE-05, LIFE-07, LIFE-08, LIFE-09, LIFE-10, CD-05
**Success Criteria** (what must be TRUE):

  1. Operator can run `scripts/verify-teardown.sh` against the empty account and see it exit zero, and can make it exit non-zero by manually creating a single untagged EBS volume — proving the sweep actually checks ALBs, target groups, controller-created security groups, EC2 instances, EBS volumes, snapshots, Elastic IPs, ENIs, and CloudWatch log groups
  2. Operator can apply `layers/00-bootstrap` and see Terraform state land in a versioned S3 bucket with a `<key>.tflock` object appearing during apply and disappearing after — with no DynamoDB table anywhere
  3. Operator can deliberately provision a $1 resource and receive a Cost Anomaly Detection alert within one day, and see a zero-spend Budget alarm configured
  4. Operator can attribute every bootstrap resource's spend by layer in Cost Explorer via `default_tags`, and confirm idle cost sits at or below $5/month against a real billing period
  5. GitHub Actions can assume an AWS role via OIDC with a trust policy scoped to this repository and branch, and no long-lived access key exists anywhere in the account or in GitHub secrets

**Plans**: 6/10 plans executed

Plans:

- [x] 01-01-PLAN.md — Repo skeleton, exact version pinning, four-layer Terraform contract, Makefile entry point and `make doctor`
- [x] 01-02-PLAN.md — Wave-0 validation harness: bats, a stubbed `aws` replaying per-class fixtures, and the four assertion suites
- [x] 01-03-PLAN.md — Account prerequisites runbook, verified us-east-1 pricing in `COSTS.md`, and the console-only setup steps
- [x] 01-04-PLAN.md — **Tracer**: bootstrap state bucket, S3-native locking, baseline inventory and the teardown sweep spine end-to-end
- [x] 01-05-PLAN.md — Sweep expansion A: instance, snapshot, address and network-interface classes with fixture-proven exclusions
- [x] 01-06-PLAN.md — Cost guardrails: SNS topic and policy, monthly ceiling plus daily tripwire budgets, anomaly monitor, tag activation
- [ ] 01-07-PLAN.md — GitHub OIDC provider and the two branch-scoped CI roles, gated on the repository's subject-claim format
- [ ] 01-08-PLAN.md — Sweep expansion B: load balancer, target group, security group and log classes, tag layer, three region tiers
- [ ] 01-09-PLAN.md — **Hard gate**: three-arm `test-verify-teardown.sh`, no-long-lived-credential proof, log-retention convention guard
- [ ] 01-10-PLAN.md — CI workflows through the OIDC path with a negative scoping test, scheduled sweep, and the decommission escape hatch

**Research flag**: 🔬 **YES — blocker.** Verify current AWS unit pricing for the chosen region against the Pricing Calculator. Only EKS ($0.10/hr) and interface endpoints ($0.01/endpoint-AZ-hr) were authoritatively verified; the entire budget model rests on the rest.
**Hard gate**: `verify-teardown.sh` must exist and be demonstrably capable of failing before Phase 2 provisions anything.
**Pitfalls addressed**: 2, 3, 8, 36 (orphans, unverifiable teardown, runaway scale-out, loose OIDC trust)

### Phase 2: Ephemeral Infrastructure & Drain Scripts

**Goal**: The operator can stand up and completely destroy the full ephemeral infrastructure layer within the wall-clock budget, twice in a row, with zero orphans — before a single line of application code exists
**Depends on**: Phase 1
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-06, NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02
**Success Criteria** (what must be TRUE):

  1. Operator can run `make up` and reach a healthy EKS 1.34 cluster in 20 minutes or less, and `make down` back to a verified-empty account in 15 minutes or less, with both wall-clock times logged to `COSTS.md`
  2. Operator can run two consecutive `make up` → `make down` round-trips on an empty cluster and see `verify-teardown.sh` exit zero both times
  3. Operator can observe `make down` executing seven named ordered steps, with each drain step polling to an AWS-API-confirmed terminal state — demonstrable by killing the ALB mid-drain and watching the script wait rather than proceed
  4. Operator can confirm a pod receives an IP from a `/20` private subnet, that data-store subnets have no default route, and that egress traverses the fck-nat `t4g.nano` ENI — verified by replacing the instance and watching routing survive
  5. Operator can `grep -r "provider \"kubernetes\"\|provider \"helm\"" layers/` and find zero matches outside `30-gitops`, so no layer requires a live API server at plan time

**Plans**: TBD
**Research flag**: ⏭️ Standard patterns — EKS module v21 and VPC module v6 are well documented. **But read `UPGRADE-21.0.md` first**; every v19/v20 tutorial is wrong (`aws-auth` removed, Karpenter IRSA path removed, OIDC issuer host changed).
**Hard gate**: ✅ **Two consecutive clean round-trips, empty cluster, zero orphans, within the time budget. No application code until this passes.**
**Parallel with**: Phase 3 (service scaffolding needs no cluster)
**Pitfalls addressed**: 9, 10, 12, 18, 19, 40
**Note**: `make up`/`make down` wall-clock instrumentation starts here and feeds the OQ1 decision in Phase 5. A regression past 25 minutes is a defect, not an annoyance.

### Phase 3: Service Scaffolding & CI Pipeline

**Goal**: The operator has a container and CI template established exactly once, so JVM sizing, probes, graceful shutdown, and supply-chain scanning are solved before being repeated six times
**Depends on**: Phase 1
**Requirements**: SVC-09, CD-04, CD-06, SEC-06, SEC-07
**Success Criteria** (what must be TRUE):

  1. Operator can generate a new Spring Boot service from the shared parent POM and inherit JVM sizing (`MaxRAMPercentage=65`, capped metaspace and direct memory, `ExitOnOutOfMemoryError`), startup/readiness/liveness probes, a `preStop` sleep, and `terminationGracePeriodSeconds` without writing any of it again
  2. Operator can push a commit and watch GitHub Actions build, test, scan, and publish an arm64 image to ECR on `ubuntu-24.04-arm` runners, with no QEMU emulation in the build log
  3. Operator can introduce a known high-severity CVE into a dependency and watch CI fail, and confirm ECR scan-on-push independently reports it
  4. Operator can introduce a deliberately insecure Terraform resource and watch both Trivy `config` and Checkov run — and can point to at least one finding where the two tools disagree, with the disagreement documented
  5. Operator can open a pull request and see `terraform plan` run through the OIDC path, and see `terraform apply` run only on merge

**Plans**: TBD
**Research flag**: 🔬 **YES** — (a) audit arm64 image availability across every chart before it is expensive to reverse; (b) confirm Spring Boot 4.1.1 third-party starter compatibility.
**Parallel with**: Phase 2 (needs no cluster)
**Decision gate**: **OQ6** — Spring Boot 4.1.1 vs 3.5.16. Decide once, pin the whole set in the parent POM, and fall back as a *set* (Boot 3.5.16 + Spring Cloud 2025.0.x + Spring Cloud AWS 3.4.2 + Gateway 4.3.5), never piecemeal.
**Pitfalls addressed**: 26, 27, 28, 29 — all "template it once" problems

### Phase 4: GitOps Seam & Walking Skeleton

**Goal**: Argo CD owns the Kubernetes API through a two-resource Terraform seam, and a real HTTP request traverses the real ALB — the antidote to "infrastructure forever, never ship a feature"
**Depends on**: Phase 2, Phase 3
**Requirements**: NET-06, OWN-01, OWN-03, CD-01, CD-02, CD-03, CD-08
**Success Criteria** (what must be TRUE):

  1. Operator can open a browser, hit the ALB DNS name, and get a response from a hello-world service deployed by Argo CD — then run `make down` and see `verify-teardown.sh` still exit zero, proving the Ingress drain step works against a real ALB
  2. Operator can open `layers/30-gitops` and count exactly two resources — `helm_release.argocd` and one root Application
  3. Operator can run `make up` on a freshly destroyed account and have Argo CD rebootstrap with zero manual intervention, logging in with a password deterministically pinned from Parameter Store rather than hunting for a generated secret
  4. Operator can confirm `make up` returns only after `argocd app wait root --health` succeeds, not when Terraform returns — verifiable by watching the shell block while CRDs sync ahead of the resources that use them
  5. Operator can read an ownership table in the README stating which system owns each resource class, authored before the first Argo Application was written

**Plans**: TBD
**Research flag**: ⏭️ Skip — Argo CD sync waves and app-of-apps are well documented.
**Hard gate**: ✅ **ALB serves traffic in a browser AND `make down` is still clean.**
**Pitfalls addressed**: 41, 42, 43 (OutOfSync loops, rebootstrap friction, Terraform/Argo ownership fights)
**Note**: Record Argo CD chart 10.9.2's real resource requests from `values.yaml` here — the estimate is `[UNVERIFIED]` (OQ6 sub-item). Also capture first `kubectl top` platform figures feeding OQ4.

### Phase 5: Event Backbone & Minimal Observability

**Goal**: The event envelope contract and the tracing stack exist *before* the second service, so the very first cross-service call produces a trace and no retrofit is ever needed
**Depends on**: Phase 4
**Requirements**: EVT-01, EVT-02, EVT-03, OBS-01, OBS-05, OBS-07, SVC-04, COST-02
**Success Criteria** (what must be TRUE):

  1. Operator can point to a written event envelope contract — `{ eventId, eventType, traceparent, version, occurredAt, payload }` — that existed in the repository before the second service was written
  2. Operator can query Prometheus and Tempo in Grafana before `inventory` is deployed, with Tempo's blocks landing in S3 rather than an EBS PVC — verified by destroying the cluster and finding yesterday's traces still queryable tomorrow
  3. Operator can open the Prometheus targets page and see zero permanently-red panels, because the etcd, scheduler, and controller-manager jobs EKS does not expose are disabled
  4. Operator can drive two concurrent stock decrements against `inventory` and observe exactly one succeed, the other rejected by a DynamoDB conditional write on the version attribute
  5. Operator can run a `core`-profile session and measure the hourly rate at or below ~$0.23/hr with in-cluster Postgres and Redis and Prometheus + Tempo only, recorded in `COSTS.md`

**Plans**: TBD
**Research flag**: 🔬 **YES — highest priority.** Confirm Spring Cloud AWS `@SqsListener` + OTel agent end-to-end `traceparent` propagation against the pinned agent version, before Phase 6 depends on it.
**Decision gates**:

- **OQ1** — Is RDS viable under same-day teardown? `var.use_rds` defaults false. Measure real create/delete timings with the Phase 2 instrumentation, record in `COSTS.md`, and flip the default only if total `make up` stays under 20 minutes. Keep the module either way. **Do not silently assume.**
- **OQ3** — ElastiCache vs in-cluster Redis. Resolved *with low confidence* in favour of in-cluster Redis by default, module retained behind a toggle. Reverse freely if `make up` time proves not to be the binding constraint. Re-evaluate when `cart` lands in Phase 11.

**Pitfalls addressed**: 22, 24, 25, 32, 34, 35, 45

### Phase 6: ★ The Trace Moment

**Goal**: A single `curl` produces one unbroken trace across four services and an async broker hop — the earliest end-to-end proof that the whole vertical slice works
**Depends on**: Phase 5
**Requirements**: SVC-03, SVC-05, SVC-06, OBS-02, OBS-03, OBS-04
**Success Criteria** (what must be TRUE):

  1. Operator can run `curl -X POST /api/orders` and see **one** trace in Tempo spanning gateway → order → EventBridge → SQS → inventory, having confirmed the spans are parent-child and not merely Linked
  2. CI fails when trace propagation breaks, because an automated assertion queries the Tempo API and verifies a single `traceID` contains spans from all four services
  3. Operator can point to explicit `traceparent` injection into `detail` and manual extraction with `W3CTraceContextPropagator` at the EventBridge boundary, having deliberately not relied on broker-level propagation
  4. Shopper can POST an order and receive an order ID immediately while fulfilment proceeds asynchronously — the response does not block on inventory
  5. Operator can flip `payment-sim` into a failure mode at runtime via an API call and see the next authorize fail, with no redeploy and no pod restart

**Plans**: TBD
**Research flag**: 🔬 **YES** — inherited from Phase 5. This is the single technical risk that can sink the phase.
**Decision gate**: **OQ5** — OTel trace context across SNS/SQS/EventBridge. Resolved *in approach* (manual envelope), **unverified in practice**. Watch for the false negative that wastes days: OTel's SQS instrumentation often creates a **Link** rather than a parent-child relationship, and Tempo does not render linked spans as one trace by default. Check Links vs Parent in the Tempo UI before concluding propagation is broken.
**Pitfalls addressed**: 25
**Note**: `api-gateway` is Spring Cloud Gateway **Server Web MVC**, not WebFlux. SVC-06's Cognito JWT validation clause is wired here as a stub and fully exercised in Phase 10 alongside SEC-12.

### Phase 7: The Complete Saga

**Goal**: The system has a genuine distributed-transaction failure surface — a pivot transaction, real compensations, and an outbox — so that it becomes worth breaking on purpose
**Depends on**: Phase 6
**Requirements**: SAGA-01, SAGA-02, SAGA-03, SAGA-04, SAGA-05, SAGA-06, SAGA-07, SAGA-08, SAGA-09, EVT-04, EVT-05, EVT-06
**Success Criteria** (what must be TRUE):

  1. Operator can place an order and watch it execute `ReserveInventory → AuthorizePayment → CapturePayment (pivot) → ConfirmOrder → OrderConfirmed`, then query `saga_instance` and `saga_step_log` to see every step recorded — with inventory reserved before payment is touched
  2. Operator can force a pre-pivot failure and observe `ReleaseInventory` and `VoidAuthorization` run, leaving zero stranded reservations and zero stranded authorizations — confirmed by querying both stores directly
  3. Operator can configure `payment-sim` to fail the *void* specifically, and watch the saga land in `COMPENSATION_FAILED`, raise an alert, and appear in a manual queue rather than failing silently
  4. Operator can kill the `order` pod mid-saga and watch the saga resume from its persisted state, and can stall a saga past the threshold and watch the timeout sweeper advance or compensate it
  5. Operator can replay a duplicate SQS message and observe zero double-charges and zero double-reservations, with the duplicate caught at a nameable layer (`Idempotency-Key`, `event_id`, or conditional write)
  6. Operator can point to a DLQ redrive they actually executed — messages moved, reprocessed, and confirmed — not merely a redrive policy they configured

**Plans**: TBD
**Research flag**: ⏭️ Skip — saga/outbox/idempotency patterns are well-established, and `ARCHITECTURE.md` contains concrete stack-specific implementations.
**Pitfalls addressed**: 31, 32, 33, 34, 35; anti-patterns AP4, AP5, AP10
**Note**: Outbox uses a polling publisher with `FOR UPDATE SKIP LOCKED`, **not Debezium** — `wal_level = logical` means a custom parameter group and an instance reboot on every `make up`. `traceparent` is an outbox *column*, because the relay publishes long after the original context is gone.

### Phase 8: Karpenter, Spot & Graceful Drain

**Goal**: All application capacity runs on Spot with real interruption handling and a hard cost ceiling — deliberately sequenced after the saga, because a Spot interruption *mid-saga* is the scenario worth having
**Depends on**: Phase 7
**Requirements**: EKS-03, EKS-05, EKS-06, COST-06, COST-07, SVC-10
**Success Criteria** (what must be TRUE):

  1. Operator can schedule a workload and watch Karpenter provision a Spot node from a pool of at least 10 instance types across at least 2 families using the `karpenter.sh/v1` API, then watch it consolidate away after `consolidateAfter: 5m`
  2. Operator can trigger a Spot interruption and observe the node drain gracefully with zero dropped in-flight requests — observed in the access log and the traces, not assumed
  3. Operator can request an absurd amount of CPU and see a bounded `NodePool limit exceeded` event rather than an unbounded bill, and can attempt to summon an oversized instance type and be refused by the allowlist
  4. Operator can roll out a new version of any service under load and see zero dropped requests, with the `preStop` sleep covering the ALB deregistration window
  5. Operator can confirm every single-replica workload uses `maxUnavailable: 1` and no PDB blocks consolidation forever — verified by draining a node hosting each

**Plans**: TBD
**Research flag**: ⏭️ Skip — Karpenter v1 docs are excellent. **But verify the `Balanced` consolidation policy exists in the pinned version (1.14.1) before relying on it.**
**Parallel with**: Phase 9
**Pitfalls addressed**: 13, 14, 15, 16, 17; anti-pattern AP6
**Note**: All v1beta1 YAML is dead — `kubelet` moved to `EC2NodeClass`, `nodeClassRef` needs group+kind+name, `amiSelectorTerms` is now required. Karpenter's AWS side (IAM, interruption SQS, EventBridge rules) already exists in Terraform from Phase 2.

### Phase 9: Observability Depth

**Goal**: The operator can debug a failure they have never seen before using only the dashboards, logs, traces, and alerts this system produces — and knows the platform's real resource footprint rather than an estimate
**Depends on**: Phase 7
**Requirements**: OBS-06, OBS-08, OBS-09, OBS-10, OBS-11, OBS-12, OBS-13, OBS-14, EKS-07
**Success Criteria** (what must be TRUE):

  1. Operator can query logs in Grafana from Loki running in `SingleBinary` mode with Grafana Alloy collecting them, S3-backed, with no Promtail anywhere
  2. Operator can open three RED/USE dashboards they wrote themselves and explain every panel on each — rather than forty imported ones
  3. Operator can push a single message to any DLQ and receive an alert, from a rule that covers *every* `-dlq` queue rather than a hand-listed subset
  4. Operator can spot a p99 latency spike on a Grafana panel and reach the exact causing trace in one click via a Prometheus exemplar
  5. Operator can deploy a workload emitting a high-cardinality label and see Prometheus reject it via `enforcedSampleLimit`/`enforcedLabelLimit` rather than OOM
  6. Operator has *seen a multi-window multi-burn-rate SLO alert fire* against real multi-day history read from S3-backed long-term storage — not merely written the rule
  7. Operator can produce real `kubectl top` figures for the platform stack in `COSTS.md`, correcting the ~2.1 vCPU / 6.1 GiB estimate, and can force a platform pod to sit `Pending` rather than starve an application pod, because the observability stack has its own tainted NodePool with its own limits

**Plans**: TBD
**Research flag**: ⏭️ Skip the patterns, **but measure**: recording actual footprint is a deliverable, not a nicety.
**Parallel with**: Phase 8
**Decision gates**:

- **OQ2** — Prometheus TSDB dies nightly, but burn-rate alerting needs multi-day history. **These are incompatible as written.** Resolved in principle via S3-backed long-term storage (OBS-12), realised here. If the decision is deferred again, record explicitly in `DECISIONS.md` that burn-rate rules have never fired against real history. **Do not leave undecided — an undecided answer defaults to losing everything and being quietly frustrated.**
- **OQ4** — Does the observability stack plus six JVM services fit the node shape? All three researcher estimates (2.1 / 2.5–4 / 3.5–6.5 GiB) are hypotheses. Loki was deliberately sequenced separately from Prometheus + Tempo so each footprint is independently measurable. **Resolve with measurement here.**

**Pitfalls addressed**: 20, 22, 23, 24; anti-patterns AP7, AP8

### Phase 10: Security Hardening

**Goal**: The system enforces least privilege, zero-trust networking, and admission policy — added deliberately late, so that every failure remains attributable rather than looking like a policy bug
**Depends on**: Phase 7
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-08, SEC-09, SEC-10, SEC-11, SEC-12, SEC-13, COST-03
**Success Criteria** (what must be TRUE):

  1. Operator can confirm each service assumes a distinct least-privilege IAM role via EKS Pod Identity with no wildcard resource ARNs, and can point to a written account of the IRSA exercise explaining why its OIDC-bound trust policy breaks on every rebuild
  2. Operator can `grep` the entire repository and every ConfigMap and find zero secret material, with all secrets arriving via External Secrets Operator from SSM Parameter Store
  3. Operator can run a **negative enforcement test** per namespace proving blocked traffic is actually blocked — because the dangerous failure is NetworkPolicies that appear to work while enforcing nothing
  4. Operator can deploy a policy-violating pod and see Kyverno *report* it in Audit mode with system namespaces excluded and `failurePolicy: Ignore`, before any policy is promoted to Enforce — and can watch a Kyverno policy reject an Exclusive ALB annotation on a non-anchor IngressGroup member
  5. Shopper traffic is authenticated by Cognito at the gateway and platform paths are protected by ALB-native auth, while the EKS public API endpoint answers only the operator's IP and Kubernetes secrets are envelope-encrypted
  6. Operator can follow a documented break-glass procedure to remove a lockout-causing admission webhook, found at the top of the runbook, and has measured a `full`-profile session rate of ~$0.29–0.33/hr with WAF, RDS, ElastiCache, and Loki enabled

**Plans**: TBD
**Research flag**: 🔬 **YES** — Kyverno policy authoring for the Exclusive-annotation guard, and VPC CNI NetworkPolicy enforcement verification (it does **not** enforce by default).
**Parallel with**: Phases 11, 14
**Pitfalls addressed**: 20, 36, 37, 38, 39; anti-pattern AP9
**Note**: Keep `kubectl delete validatingwebhookconfiguration ...` at the top of the runbook, in bold. Kyverno in `Enforce` while the bill climbs is a real failure mode.

### Phase 11: Storefront, Catalog, Cart & Notification Lambda

**Goal**: The system exercises both saga styles — orchestrated and choreographed — and has a browsable storefront that drives the full backend end to end
**Depends on**: Phase 7
**Requirements**: SVC-01, SVC-02, SVC-07, SVC-08
**Success Criteria** (what must be TRUE):

  1. Shopper can browse a product catalog served by `catalog` from DynamoDB, and operator can drive load until the HPA scales it
  2. Shopper can add and remove cart items served by `cart` from Redis, and operator can watch a cart key expire on its TTL
  3. Operator can deploy the `notification` Lambda and confirm it reacts to `OrderConfirmed` off EventBridge with **zero changes to `order`** — a `git diff` on the `order` service showing nothing is the proof of loose coupling
  4. Shopper can complete browse → cart → checkout entirely through a React + Vite SPA served from S3 behind CloudFront with OAC, with SPA routing working on a deep-link refresh

**Plans**: TBD
**Research flag**: ⏭️ Skip.
**Parallel with**: Phases 10, 14
**UI hint**: yes
**Note**: **CloudFront must never enter the daily loop** — 5–15 min to deploy, 15–45 min to delete. It lives in L0 from Phase 1. Use OAC, not OAI (legacy, feature-frozen), `PriceClass_100`, and `custom_error_response` for SPA routing.

### Phase 12: Progressive Delivery & Load Generation

**Goal**: A deliberately broken build is caught and rolled back by the system itself, under load heavy enough to surface conflicts that do not occur at 1 RPS
**Depends on**: Phase 9, Phase 11
**Requirements**: CD-07, CHAOS-04
**Success Criteria** (what must be TRUE):

  1. Operator can push a deliberately broken `catalog` build and watch an Argo Rollouts canary, gated by a Prometheus `AnalysisTemplate`, abort and roll back automatically — with no human touching `kubectl`
  2. Operator can run a k6 load profile that actually causes optimistic-locking conflicts in `inventory`, observable as rejected conditional writes in the metrics
  3. Operator can point to a written decision that canary is deliberately *not* applied to the saga services, with mid-saga version skew named as the reason

**Plans**: TBD
**Research flag**: 🔬 **YES** — Argo Rollouts + ALB `TargetGroupBinding` traffic-splitting mechanics.
**Depends on Phase 9** because canary analysis needs metrics; **on Phase 11** because `catalog` is the canary subject.

### Phase 13: Chaos Scenarios & Runbooks

**Goal**: The operator has debugged five real distributed-systems failures and written the runbooks during the debugging — the unfakeable payoff the whole project exists to produce
**Depends on**: Phase 8, Phase 9, Phase 10
**Requirements**: CHAOS-01, CHAOS-02, CHAOS-03, CHAOS-05, CHAOS-06, CHAOS-07
**Success Criteria** (what must be TRUE):

  1. Operator can trigger in-cluster faults through Chaos Mesh CRDs managed by Argo CD, and an authentic 2-minute Spot interruption notice through AWS FIS `aws:ec2:send-spot-instance-interruptions`, with FIS templates living permanently in Terraform at zero idle cost
  2. Operator has executed and debugged at least five scenarios — a Spot interruption mid-saga, a payment that timed out but actually succeeded, an SQS consumer killed between processing and delete, a DNS failure, latency on `inventory`, and an OOMKill
  3. A cold reader can follow any scenario's runbook and reproduce both the failure and the diagnosis, because each was written *during* the debugging rather than reconstructed after
  4. At least one runbook documents a hypothesis that turned out to be **wrong**, and what the evidence actually showed

**Plans**: TBD
**Research flag**: ⏭️ Skip.
**Parallel with**: Phase 14
**Exit criterion**: A scenario is not complete until its runbook exists. Write during, not after.

### Phase 14: Testing Depth

**Goal**: The system's correctness — including its failure paths — is defended automatically, so a change that breaks compensation or event compatibility cannot reach a cluster
**Depends on**: Phase 7
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06
**Success Criteria** (what must be TRUE):

  1. Operator can run the full test suite in CI for every service with Testcontainers 2.0.5 providing real Postgres and Redis, and LocalStack covering the outbox poller and idempotent consumers with no AWS account involved
  2. Operator can make a breaking change to an inter-service contract or an event schema and watch CI fail — via Spring Cloud Contract and backward-compatibility tests, with no Pact Broker to host or destroy
  3. Operator can run an E2E smoke suite against a freshly provisioned cluster that gates deployment and covers **both** the happy path and the compensated-failure path
  4. Operator can watch a chaos scenario run as an automated CI test, turning chaos from a party trick into a gate

**Plans**: TBD
**Research flag**: ⏭️ Skip.
**Parallel with**: Phase 13
**Note**: Testcontainers 2.0.5 changed artifact IDs — `testcontainers-postgresql`, not `postgresql`. Every pre-2026 tutorial is wrong.

## Parallelization

```
P1 ──┬──▶ P2 ──▶ P4 ──▶ P5 ──▶ P6 ★ ──▶ P7 ──┬──▶ P8 ──┬──▶ P13
     └──▶ P3 ─────────┘                       ├──▶ P9 ──┴──▶ P12
                                              ├──▶ P10
                                              ├──▶ P11 ─────▶ P12
                                              └──▶ P14
```

| Marker | Phases | Why independent |
|--------|--------|-----------------|
| **P2 ∥ P3** | Ephemeral infra ∥ Service scaffolding | Service scaffolding and CI need no cluster |
| **P8 ∥ P9** | Karpenter ∥ Observability depth | Compute autoscaling and telemetry are independent concerns |
| **P10 ∥ P11 ∥ P14** | Security ∥ Storefront ∥ Testing | All three hang off the completed saga independently |
| **P13 ∥ P14** | Chaos ∥ Testing depth | Chaos consumes the system; testing defends it |

**Serialization requirements:** P12 requires P9 (canary analysis needs metrics) and P11 (`catalog` is the canary subject). P13 requires P8 (Spot interruption), P9 (debugging telemetry), and P10 (break-glass procedure).

## Hard Gates

| Gate | Phase | Condition |
|------|-------|-----------|
| **Teardown verifier exists** | 1 | `verify-teardown.sh` written and demonstrably able to fail, before anything is provisioned |
| **Two clean round-trips** | 2 | Two consecutive `make up` → `make down` on an empty cluster, zero orphans, ≤20 min up / ≤15 min down. **No application code until this passes.** |
| **Walking skeleton** | 4 | ALB serves traffic in a browser AND `make down` is still clean |
| **The trace moment** | 6 | One `traceID` contains spans from all four services, asserted automatically against the Tempo API |
| **Runbook per scenario** | 13 | A scenario is not complete until a cold reader could follow its runbook |

## Open Decision Gates

Each is a decision gate during its phase, **not a detail to be assumed away**.

| ID | Question | Resolves in | Status entering the phase |
|----|----------|-------------|---------------------------|
| **OQ1** | Is RDS viable under same-day teardown? | **Phase 5** (measured with Phase 2 instrumentation) | 🔴 Unresolved — `var.use_rds` defaults false; flip only if `make up` stays under 20 min |
| **OQ2** | Prometheus TSDB dies nightly vs SLO burn-rate needing multi-day history | **Phase 9** | 🔴 Unresolved — resolved in principle via S3-backed LTS (OBS-12); must be an explicit recorded decision |
| **OQ3** | ElastiCache or in-cluster Redis? | **Phase 5** (re-evaluate at Phase 11) | 🟠 Resolved with low confidence — in-cluster default, module behind a toggle |
| **OQ4** | Does the observability stack + six JVM services fit the node shape? | **Phase 9** | 🔴 Unresolved until measured — all three estimates are hypotheses |
| **OQ5** | Does OTel trace context survive SNS/SQS/EventBridge? | **Phase 6** (researched in Phase 5) | 🔴 Resolved in approach, unverified in practice — highest-priority research flag |
| **OQ6** | Spring Boot 4.1.1 or fall back to 3.5.16? | **Phase 3** | 🟡 Decide once, pin in the parent POM, fall back as a *set* |

## Research Flags

| Phase | Flag | Scope |
|-------|------|-------|
| 1 | 🔬 **YES — blocker** | AWS unit pricing for the chosen region; the entire budget rests on it |
| 2 | ⏭️ Standard | But read `UPGRADE-21.0.md` — v19/v20 tutorials are wrong |
| 3 | 🔬 **YES** | arm64 image availability across every chart; Spring Boot 4.1.1 starter compatibility |
| 4 | ⏭️ Skip | Argo CD sync waves and app-of-apps well documented |
| 5 | 🔬 **YES — highest priority** | `@SqsListener` + OTel agent `traceparent` propagation against the pinned agent version |
| 6 | 🔬 **YES** | Inherited from Phase 5; the one technical risk that can sink the phase |
| 7 | ⏭️ Skip | Saga/outbox/idempotency patterns well-established |
| 8 | ⏭️ Skip | But verify `Balanced` consolidation exists in Karpenter 1.14.1 |
| 9 | ⏭️ Skip, **but measure** | Record real `kubectl top` figures; correct the estimate |
| 10 | 🔬 **YES** | Kyverno Exclusive-annotation guard; VPC CNI NetworkPolicy enforcement verification |
| 11 | ⏭️ Skip | — |
| 12 | 🔬 **YES** | Argo Rollouts + ALB `TargetGroupBinding` traffic-splitting mechanics |
| 13 | ⏭️ Skip | — |
| 14 | ⏭️ Skip | — |

## Deviations from Research

The roadmap follows `SUMMARY.md` Part 3's reconciled build order. Two deliberate deviations:

1. **Phase 1b promoted to a full phase (Phase 3).** Research listed it as a parallel sub-phase. It is
   promoted to a first-class phase because it owns five requirements, carries a research flag, and
   resolves OQ6 — it needs its own verification. The `P2 ∥ P3` parallelization marker preserves the
   original intent. Net phase count: 14, against the research's 13. Granularity is `fine` (8-12
   target); the overrun is accepted because each phase maps to a distinct, individually verifiable
   infrastructure concern.

2. **`catalog` and `cart` placed in Phase 11 — a genuine coverage gap in the research.** The
   reconciled build order never explicitly places these two of the six services, yet research Phase
   10 (here Phase 12) runs a canary on `catalog`, which presupposes it exists. They are grouped with
   the storefront phase because that is where they are actually exercised, and Phase 12 is
   consequently made to depend on Phase 11 as well as Phase 9.

Three smaller placement judgements worth naming:

- **EKS-07** (observability on its own tainted NodePool) sits in Phase 9 rather than Phase 8, because
  its purpose is resolving OQ4 by measurement, not Karpenter mechanics.
- **COST-02/COST-03** (session profile rates) sit in Phases 5 and 10 respectively, because a profile
  rate can only be measured once the profile's contents exist — `core` completes at Phase 5, `full`
  completes when WAF lands in Phase 10.
- **SVC-06** (`api-gateway`) sits in Phase 6 where the gateway is built; its Cognito JWT-validation
  clause is fully exercised in Phase 10 alongside SEC-12.

## Progress

**Execution Order:** Phases execute in numeric order, honouring the parallelization markers above.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Account, L0 Bootstrap & Teardown Harness | 6/10 | In Progress|  |
| 2. Ephemeral Infrastructure & Drain Scripts | 0/TBD | Not started | - |
| 3. Service Scaffolding & CI Pipeline | 0/TBD | Not started | - |
| 4. GitOps Seam & Walking Skeleton | 0/TBD | Not started | - |
| 5. Event Backbone & Minimal Observability | 0/TBD | Not started | - |
| 6. ★ The Trace Moment | 0/TBD | Not started | - |
| 7. The Complete Saga | 0/TBD | Not started | - |
| 8. Karpenter, Spot & Graceful Drain | 0/TBD | Not started | - |
| 9. Observability Depth | 0/TBD | Not started | - |
| 10. Security Hardening | 0/TBD | Not started | - |
| 11. Storefront, Catalog, Cart & Notification Lambda | 0/TBD | Not started | - |
| 12. Progressive Delivery & Load Generation | 0/TBD | Not started | - |
| 13. Chaos Scenarios & Runbooks | 0/TBD | Not started | - |
| 14. Testing Depth | 0/TBD | Not started | - |

---
*Roadmap created: 2026-09-24*
*Coverage: 110/110 v1 requirements mapped, zero orphans*
