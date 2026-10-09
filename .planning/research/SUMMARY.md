# Project Research Summary

**Project:** AWS EKS E-Commerce Microservices Practice Platform
**Domain:** Cost-constrained, teardown-per-day cloud-native practice platform (IaC + GitOps + event-driven saga + self-hosted observability)
**Researched:** 2026-09-24
**Confidence:** MEDIUM-HIGH — HIGH on version pins, API shapes, and upstream mechanics (fetched live from registries and vendor docs); MEDIUM on AWS unit pricing beyond EKS/PrivateLink, resource footprints, and timing estimates

---

## Executive Summary

This is not an e-commerce project. It is a **day-2 operations practice rig** wearing an e-commerce costume, and every architectural decision is downstream of a single constraint: *it must die cleanly every night and come back tomorrow*. All four researchers converged independently on the same conclusion — the thing that kills projects in this shape is not complexity, it is **a resource that survives `terraform destroy` and bills silently**. The second killer is friction: if `make up` takes 45 minutes, sessions stop happening. Everything else is recoverable.

The recommended approach is therefore inverted from the intuitive one. **Build the teardown before you build anything to tear down.** `verify-teardown.sh` is the Phase 0 deliverable, written before the first VPC exists. Terraform owns the AWS API, Argo CD owns the Kubernetes API, and the only seam is a two-resource `30-gitops` layer that installs Argo CD and nothing else — because the Terraform `kubernetes`/`helm` providers need a live API server at *plan* time, and on destroy that API server may already be gone, wedging state at 11pm. Three of the seven steps in `make down` are deliberately **not Terraform** (drain Ingresses, drain NodePools, drain PVCs), because Terraform's dependency graph cannot see through a controller: it deletes the ALB Controller in milliseconds and leaves the ALBs it created, which then block `aws_subnet` deletion with `DependencyViolation`.

The differentiation thesis is equally counter-intuitive and is the strongest single finding in the corpus. The Features researcher verified that **none of the well-known reference implementations has a real distributed-systems problem**: Online Boutique serves its catalog from a JSON file, has no message broker at all, and checks out via a synchronous gRPC fan-out; Sock Shop's README marks it DEPRECATED; Robot Shop's own README admits "the error handling is patchy and there is not any security built into the application." They are topology demos, not failure demos. So the differentiator is **depth of failure surface, not service count** — six services with a genuine saga (outbox, idempotency keys, compensation, a pivot transaction, and a `payment-sim` whose job is to fail) beats eleven with a synchronous fan-out, *and is less work*. The key risks are: (1) the budget arithmetic is tighter than PROJECT.md assumes and needs restructuring (see below), (2) OpenTelemetry trace context will silently fail to cross EventBridge unless deliberately engineered, and (3) the platform's own footprint (~2.1 vCPU / 6.1 GiB before any business pod) will starve the application if the cluster is sized for the app rather than the platform.

---

## Part 1 — Corrections to PROJECT.md the Roadmap Must Absorb

These are consolidated from all four researchers. Each is a **confirmed factual correction**, not a preference. The roadmapper should treat the "Corrected to" column as the requirement text.

| # | PROJECT.md says | Corrected to | Why | Confidence |
|---|---|---|---|---|
| **C1** | "VPC endpoints for AWS-native traffic" | **Gateway endpoints only (S3 + DynamoDB, $0). Interface endpoints behind `variable "enable_interface_endpoints" { default = false }`** | Interface endpoints bill **$0.01/endpoint/AZ/hr = $7.30/mo per endpoint per AZ** (verified from the AWS Price List API). Five endpoints × 2 AZs = **$73/mo — 24× the fck-nat instance and 2.2× the NAT Gateway that was rejected on cost.** The "endpoints instead of NAT" heuristic is correct at production data volumes and **inverts at this scale**. S3 gateway endpoint is *mandatory* (ECR image layers are served from S3). | **HIGH** ✅ |
| **C2** | "remote state in S3 + DynamoDB state locking" | **S3 remote state with native `use_lockfile = true` + bucket versioning** | `dynamodb_table` / `dynamodb_endpoint` are **documented as Deprecated** in the current S3 backend docs. Native locking writes a `<key>.tflock` object. Keeping DynamoDB means adopting a deprecated mechanism *and* one more immortal resource. | **HIGH** ✅ |
| **C3** | "tfsec/Checkov IaC scanning" | **Trivy `config` scanning + Checkov as a second opinion** | tfsec is dead — the repo's own GitHub page title reads *"Tfsec is now part of Trivy"*. Last release v1.28.14. Run both Trivy and Checkov; they catch different classes (Checkov is better at cross-resource graph checks) and **their disagreements are the lesson**. | **HIGH** ✅ |
| **C4** | "IRSA / EKS Pod Identity giving each service least-privilege" | **EKS Pod Identity throughout. IRSA once, as a deliberate named exercise, then discarded.** | Two independent reasons. (a) `terraform-aws-modules/eks` **v21 removed the Karpenter IRSA path entirely** and defaults `create_pod_identity_association = true`. (b) **Project-specific and decisive:** IRSA trust policies embed the cluster's OIDC provider ID, **which changes on every cluster recreate** — so every IAM role's trust policy goes stale on every rebuild. IRSA is actively hostile to a daily-teardown workflow. Pod Identity's trust policy is the static principal `pods.eks.amazonaws.com`. (Also: v21 changed the OIDC issuer host from `oidc.eks.*` to `oidc-eks.*`, so copied trust policies won't match.) | **HIGH** ✅ |
| **C5** | "EKS cluster ... with managed node groups on Spot instances" | **System managed node group must be ON-DEMAND (1–2 × `t4g.medium`/`t4g.small`, tainted `CriticalAddonsOnly`). Spot is Karpenter-provisioned only.** | Karpenter cannot provision the node it runs on. If Karpenter's own node is Spot-reclaimed or consolidated, there is no controller left to replace it — the cluster deadlocks at zero capacity. CoreDNS, the ALB Controller, and Argo CD's controllers belong here too. | **HIGH** ✅ |
| **C6** | (implied) `make down` = `terraform destroy` | **`make down` = disable Argo auto-sync → drain Ingress/Services (poll `elbv2`) → drain NodePools (poll `ec2`) → drain PVCs (poll `ec2`) → destroy L3→L2→L1 → `verify-teardown.sh` (non-zero exit on any orphan)** | ALBs, controller-created SGs, Karpenter EC2 instances, and PVC-provisioned EBS volumes are **not in Terraform state**. Add this as an explicit requirement. `kubectl delete ingress` returns *before* the ALB is gone — every drain step must **poll to an AWS-API-confirmed terminal state**, not fire-and-forget. A drain script that doesn't poll is a `make down` that fails 1 night in 4. | **HIGH** ✅ |
| **C7** | "`cart` — Spring Boot over ElastiCache Redis" | **In-cluster Redis pod by default; ElastiCache behind a toggle for one deliberate session** | ElastiCache creation is ~8–12 min and deletion adds ~5 min to `make down`. On a stack rebuilt daily, **`make up` minutes are the scarcest resource in the project.** `cart` is explicitly ephemeral TTL state, so nothing is lost. Cost saving ($0.016/hr) is secondary to the wall-clock saving. Architecture recommends keeping it for M1 but flags it as "the first thing to cut" — Pitfalls is more direct. **Take the cut.** | MEDIUM (judgement) |
| **C8** | "`order` — Spring Boot over RDS Postgres" | **`var.use_rds` toggle, defaulting to in-cluster Postgres; RDS for RDS-focused sessions.** Measure real create/restore time in Phase 1 before finalising. | See Open Question OQ1. RDS create is ~6–10 min, delete ~5 min. Both researchers who raised it agree on a toggle rather than a pre-commitment. | MEDIUM |
| **C9** | "External Secrets Operator syncing from AWS Secrets Manager" | **ESO with SSM Parameter Store (Standard tier, free) as the default provider; ≤2 consolidated JSON secrets in Secrets Manager for genuinely rotating credentials** | Secrets Manager is **$0.40/secret/month**. Ten secrets = $4/mo = **the entire idle budget**. ESO supports Parameter Store as a provider. The learning is identical. | **HIGH** ✅ |
| **C10** | "Self-hosted in-cluster stack — Prometheus, Grafana, Loki, Tempo" | Same, but: **Loki `deploymentMode: SingleBinary` (the chart default is the deprecated `SimpleScalable`), Tempo monolithic (not `tempo-distributed`), Grafana Alloy (not Promtail — EOL 2026-03-02), Loki+Tempo backed by an L0 S3 bucket, not EBS PVCs.** Loki deferred to a later phase than Prometheus+Tempo. | SSD mode is deprecated and **removed in Loki 4.0**, and it is still the chart's default — you must opt *out*. `tempo-distributed` spins up 5+ extra pods. S3 backing avoids the AZ-pinned-EBS orphan class **and lets yesterday's traces survive teardown**, which is a large practical win. | **HIGH** ✅ |
| **C11** | (unstated) Kubernetes version | **Pin EKS to `1.34`** explicitly; never float. | Standard support covers 1.36/1.35/1.34. 1.34 is chosen over 1.36 for *rebuild reliability*: 1.36 permanently disables `gitRepo` volumes and enables `StrictIPCIDRValidation` by default (rejects CIDRs third-party charts still ship). **Watch the 14-month window — extended support is $0.60/hr, a 6× cost increase.** In-place 1.34→1.35→1.36 upgrade is itself a high-value exercise later. | HIGH on facts, MEDIUM on the 1.34-vs-1.36 call |
| **C12** | "Budget: active session ≤ ~$0.30/hour" | **Reframe as per-profile, per-session.** See Part 2. | The single ceiling does not survive contact with the required cluster floor. | — |

---

## Part 2 — The Budget: Does the Arithmetic Close?

### The three positions

1. **Pitfalls:** fixed overhead before a single pod runs is EKS control plane ($0.100) + ALB ($0.0225) + fck-nat ($0.0042) + 3 × public IPv4 ($0.015) = **$0.1417/hr = 47% of the budget**, leaving ~$0.16/hr for all workload compute ≈ 2–3 Spot nodes.
2. **Architecture:** the *platform itself* (Argo CD + kube-prometheus-stack + Loki + Tempo + Kyverno + ESO + LBC + kube-system) needs **~2.1 vCPU / 6.1 GiB** of requests before any business pod, implying a **~4 vCPU / 12 GiB cluster floor**. "You cannot fit this on 2 × `t3.small`. Attempting to is the classic failure."
3. **Features:** there is a **learning floor** below which cost-cutting destroys the point — **≥2 nodes, ≥2 replicas of the saga-critical services, ≥2 AZs**. Optimise below that and you have optimised away pod eviction, PDBs, Spot interruption, and rolling updates, i.e. all of the learning. *"Budget for that floor and cut elsewhere."*

### The verdict

**The $0.30/hour ceiling does NOT close as a single universal number for the full stack. It closes comfortably for a trimmed default profile, and is exceeded by ~10–20% by the full stack. The correct response is to restructure the budget, not to trim the cluster below the learning floor.**

Worked arithmetic (MEDIUM confidence on every line except EKS):

| Line item | Default profile | Full profile |
|---|---|---|
| EKS control plane | $0.1000 | $0.1000 |
| ALB (1, shared via IngressGroup) | $0.0225 | $0.0225 |
| fck-nat `t4g.nano` | $0.0042 | $0.0042 |
| Public IPv4 × 3 | $0.0150 | $0.0150 |
| System MNG (1 × `t4g.medium`, on-demand) | $0.0336 | $0.0336 |
| Karpenter Spot nodes | 2 × `t4g.large` = $0.0500 | 3 × `t4g.large` = $0.0750 |
| EBS (nodes) | $0.0060 | $0.0100 |
| RDS `db.t4g.micro` | — (in-cluster PG) | $0.0160 |
| ElastiCache `cache.t4g.micro` | — (in-cluster Redis) | $0.0160 |
| WAF (prorated) | — | $0.0080 |
| **Total** | **≈ $0.231/hr ✅** | **≈ $0.290/hr ⚠️** |

The "full" column technically lands under $0.30 — **but with a 3% margin on figures where only two line items were verified against authoritative AWS sources.** A 3% margin on MEDIUM-confidence estimates is not a margin; it is a rounding error. And it assumes 3 Spot nodes carry 6 services *plus* 2 replicas of the 3 saga-critical services (9 JVM pods × ~640 MiB ≈ 5.8 GiB) *plus* the 6.1 GiB platform — which is ~12 GiB against ~17 GiB allocatable. Tight but real.

### What must give — the decision

**Adopt session profiles, and make `$/session` the primary budget unit rather than `$/hour`.**

| Profile | Contents | Rate | Use |
|---|---|---|---|
| **A — `core` (default, ~80% of sessions)** | EKS + system MNG + 2 Spot nodes + in-cluster Postgres + in-cluster Redis + ALB + fck-nat + **Prometheus + Tempo only** (no Loki, no WAF, no ElastiCache, no RDS) | **~$0.21–0.23/hr** | Saga work, chaos, most debugging. Comfortable headroom. |
| **B — `full`** | + RDS + ElastiCache + Loki + WAF + 3rd Spot node + 2 replicas of saga services | **~$0.29–0.33/hr** | Deliberate, occasional. **Accept that this may exceed $0.30/hr** and bound it by session length instead. |
| **C — `managed`** | RDS/ElastiCache focus, trimmed observability (Prometheus only) | ~$0.25/hr | Parameter groups, failover, IAM auth practice. |

At 20 sessions/month × 3 hours, Profile A is **~$14/month of active spend**, Profile B occasional adds a few dollars. The **idle** ceiling of ~$5/month is met with room to spare (L0 ≈ $2–3/month: S3 state + ECR with a keep-last-3 lifecycle policy + observability bucket + CloudFront + ≤2 Secrets Manager secrets).

**Three hard guardrails that make this safe regardless of profile:**
1. **Karpenter `NodePool.spec.limits: { cpu: "8", memory: 32Gi }`** — described by the Pitfalls researcher as "the single best line of YAML in the project." It converts the "crashlooping workload scales forever" horror story from a $500 night into a bounded, debuggable `NodePool limit exceeded` event.
2. **An EC2 instance-type allowlist** so a `64Gi`-instead-of-`64Mi` typo cannot summon an `r6i.8xlarge`.
3. **A dedicated AWS account** with a zero-spend Budget and Cost Anomaly Detection at a **$1 absolute threshold** (the defaults are tuned for enterprise spend and will never fire here). Isolation also makes a blunt `nuke.sh` safe.

**Note on session length, not instance type:** the EKS control plane alone is 42–47% of the hourly cost. *There is no instance-type tuning that rescues a cluster you forgot to destroy.* The Budgets alarm and `verify-teardown.sh` are cost controls of the first order, not hygiene.

**On the 2-AZ conflict:** Pitfalls recommends single-AZ compute to eliminate cross-AZ transfer; Features requires ≥2 AZs as a learning floor. **Resolution: Features wins.** Cross-AZ transfer at practice volumes (<10 GB/session at $0.02/GB round-trip) is **~$0.20/session** — real but trivial, and Architecture independently reaches the same conclusion ("a second fck-nat costs more than the hairpin"). Keep subnets in 2 AZs (EKS and the ALB require it anyway) and compute in 2 AZs. Pitfalls overstates this one at this scale.

---

## Part 3 — Reconciled Build Order

### How the three proposals differed, and what I took

| Question | STACK | ARCHITECTURE | PITFALLS | **Taken** |
|---|---|---|---|---|
| State split | 3-way: `00-bootstrap` / `10-platform` / `20-cluster` | 4-way: `00-bootstrap` / `10-infra` / `20-data` / `30-gitops` | 4-way: `bootstrap` / `network` / `cluster` / `addons` | **ARCHITECTURE.** It explicitly argues against the network/cluster seam that Pitfalls proposes (identical lifetimes; the seam costs 40–60s per cycle and encodes an ordering Terraform can no longer enforce), and it isolates the `helm` provider into a 2-resource layer, which Stack's 3-way does not. Stack's concern about persisting CloudFront/ECR is fully absorbed by Architecture's L0. |
| Lifecycle timing | Bootstrap-and-teardown-first | P0 = teardown harness, before anything exists | Phase 1, "building them last is the number-one way this project dies" | **Unanimous — Phase 0/1, not polish.** `verify-teardown.sh` is written before there is anything to tear down. |
| First trace | — | P4 "★ THE MOMENT" | Walking skeleton by Phase 3 | **Both.** Walking skeleton (hello-world Ingress through the ALB) at Phase 2; full saga trace at Phase 4. |
| Observability timing | — | Tempo at P4, Prometheus at P7 | **Minimal Prometheus + Tempo before the *second* service** — "the single most valuable ordering change this research suggests" | **PITFALLS.** Pulled minimal Prometheus + Tempo forward into Phase 3, before `order`+`inventory` land. You cannot debug a distributed saga without traces, and debugging a system you have never seen working is exponentially harder. |
| Security/policy timing | — | P8, deliberately late | Late, Audit-first, "a strong argument for its own phase near the end" | **Unanimous — late.** Added early, every bug looks like a policy bug. |

### The sequence

> **Ordering principle:** build the thinnest vertical slice through every architectural layer first, then thicken each layer. *If a phase can be moved after the trace moment, move it after the trace moment.*

**Phase 0 — Account, L0 bootstrap, and the teardown harness**
**Rationale:** Everything depends on it, and the verifier must exist before there is anything to verify — writing it first is the forcing function that makes the constraint real rather than aspirational.
**Delivers:** Dedicated AWS account + zero-spend Budget + Cost Anomaly Detection at $1. `layers/00-bootstrap`: S3 state (`use_lockfile`, versioned), ECR + keep-last-3 lifecycle + `force_delete = true`, GitHub OIDC provider + two scoped roles, observability S3 bucket (3-day lifecycle), SPA bucket + CloudFront, cost-allocation tags via `default_tags`. Makefile skeleton. **`sh/verify-teardown.sh`.** `VERSIONS.md`.
**Avoids:** Pitfalls 2, 3, 8, 36 (orphans, unverifiable teardown, runaway scale-out, loose OIDC trust).
**Research flag:** 🔬 **YES** — verify current AWS pricing for the chosen region. The entire budget rests on it and only EKS + PrivateLink rates were authoritatively verified.

**Phase 1 — L1 ephemeral infra + drain scripts** *(∥ with 1b)*
**Rationale:** Subnet sizing and CIDR layout are irreversible without a VPC rebuild. The TF-layer split must be right before anything is built on it — retrofitting means a painful state migration.
**Delivers:** VPC `10.42.0.0/16`, 2 AZs, **private subnets `/20` not `/24`** (VPC CNI warm-pool IP exhaustion), intra subnets with no default route for data stores, fck-nat ASG(1) routing via **ENI not instance-id**, S3 + DynamoDB gateway endpoints, EKS 1.34, on-demand system MNG, EKS managed addons incl. Pod Identity Agent, all Pod Identity roles, Karpenter's AWS side (IAM + interruption SQS + EventBridge rules — **in Terraform, not the upstream CloudFormation**). Subnet tags with a **deterministic `cluster_name`**. `drain-ingress.sh` / `drain-nodes.sh` / `drain-pvcs.sh`.
**GATE:** ✅ **Two consecutive clean `make up` → `make down` round-trips, empty cluster, zero orphans. `make up` ≤ 20 min, `make down` ≤ 15 min, both timed and logged to `COSTS.md`.**
**Avoids:** Pitfalls 9, 10, 12, 18, 19, 40.
**Research flag:** ⏭️ Standard patterns — the EKS v21 module and VPC v6 module are well documented. *But* read `UPGRADE-21.0.md` first; v19/v20 tutorials are wrong.

**Phase 1b — Service scaffolding + CI** *(∥ with Phase 1, needs no cluster)*
**Rationale:** Establish the Spring Boot container template **once** and reuse it six times. Getting JVM sizing, probes, and graceful shutdown right on service #1 saves it six times.
**Delivers:** Six Spring Boot 4.1.1 skeletons on a shared parent POM, Dockerfile with the OTel agent baked in, `JAVA_TOOL_OPTIONS` template, startup/readiness/liveness probe template, `preStop` sleep + `terminationGracePeriodSeconds`, GitHub Actions build → ECR on **`ubuntu-24.04-arm` runners** (QEMU arm64 emulation is 5–10× slower), Trivy image + config scan, Checkov.
**Avoids:** Pitfalls 26, 27, 28, 29 — all of which are "template it once" problems.
**Research flag:** 🔬 **YES** — **arm64 image availability audit across every chart** before it is expensive to reverse. Also: confirm Spring Boot 4.1.1 third-party starter compatibility; if it breaks, fall back as a *set* (Boot 3.5.16 + Spring Cloud 2025.0.x + Spring Cloud AWS 3.4.2 + Gateway 4.3.5) and pin it in the parent POM.

**Phase 2 — Argo CD seed + first platform apps + walking skeleton**
**Rationale:** Every subsequent phase deploys through Argo CD, so it must come early. And a hello-world request traversing the real ALB is the antidote to "infrastructure forever, never ship a feature."
**Delivers:** `layers/30-gitops` — `helm_release.argocd` + one root Application, **two resources total**. App-of-apps with sync waves. ALB Controller + metrics-server. Hello-world Ingress in the shared IngressGroup with an **anchor Ingress** owning all Exclusive annotations. Argo admin password pinned deterministically from Parameter Store. `make up` ends with `argocd app wait root --health`, not when Terraform returns.
**GATE:** ✅ **ALB serves traffic in a browser AND `make down` is still clean — drain step 1 now exercised for real.**
**Avoids:** Pitfalls 41, 42, 43 (OutOfSync loops, rebootstrap friction, TF/Argo ownership fights). **Deliverable: the ownership table, written in the README before the first Argo Application.**
**Research flag:** ⏭️ Skip — Argo CD sync waves and app-of-apps are well documented.

**Phase 3 — Event backbone + minimal observability + two services**
**Rationale:** ⚠️ **This is the reordering that matters.** The event envelope must be designed *before* six services exist (retrofitting it is painful), and minimal Prometheus + Tempo must exist *before* the second service, so the very first cross-service call produces a trace.
**Delivers:** `layers/20-data` (minimal): in-cluster Postgres (or RDS via toggle) + DynamoDB + one SQS command/reply pair + DLQs + EventBridge bus. **The event envelope contract: `{ eventId, eventType, traceparent, version, occurredAt, payload }`.** Prometheus (6h retention, 60s scrape, etcd/scheduler/controller-manager jobs **disabled** — AWS doesn't expose them and permanently-red panels train you to ignore red) + Tempo (S3-backed). `order` + `inventory` deployed. Flyway + idempotent seed as an Argo `PreSync` Job.
**Avoids:** Pitfalls 22, 24, 25, 32, 34, 35, 45.
**Research flag:** 🔬 **YES — highest priority.** Confirm Spring Cloud AWS `@SqsListener` + OTel agent end-to-end `traceparent` propagation against the pinned agent version.

**Phase 4 — ★ THE TRACE MOMENT**
**Rationale:** The single highest-value milestone in the project. One unbroken trace proves the whole vertical slice works, and everything after this hangs off it.
**Delivers:** `api-gateway` (Spring Cloud Gateway **Server Web MVC**, not WebFlux) + `payment-sim`. Minimal 3-step saga, happy path only. OTel Java agent → Tempo → Grafana.
**Target:** `curl -X POST /api/orders` produces **one trace** spanning gateway → order → EventBridge → SQS → inventory → reply.
**Acceptance criterion (make it testable, not hoped-for):** an automated assertion against the Tempo API that a **single `traceID` contains spans from all four services**.
**Avoids:** Pitfall 25 — see Open Question OQ5. This is the one technical risk that can sink the phase.
**Research flag:** 🔬 **YES** — inherited from Phase 3.

**Phase 5 — Complete the saga**
**Rationale:** Only after this can the system be broken on purpose, which unblocks Karpenter chaos and runbooks.
**Delivers:** Full step sequence `T1 ReserveInventory → T2 AuthorizePayment → T3 CapturePayment (PIVOT) → T4 ConfirmOrder → T5 emit OrderConfirmed`, with compensations `C1 ReleaseInventory` / `C2 VoidAuthorization`. Persisted `saga_instance` + `saga_step_log` state machine. Transactional outbox via **polling publisher with `FOR UPDATE SKIP LOCKED`** (not Debezium — `wal_level = logical` means a custom parameter group and an **instance reboot on every `make up`**). Timeout sweeper. **`COMPENSATION_FAILED` state + alert + manual queue.** Three-layer idempotency (API `Idempotency-Key` → producer-generated `event_id` → store-native conditional write). DLQs + an actually-executed redrive. `payment-sim` runtime failure injection — **including the ability to fail the *void*specifically**, or the compensation-fails path is never exercised.
**Design choices worth preserving:** reserve inventory *before* touching payment (releasing a reservation is free and always succeeds; refunding money is not). Split Authorize from Capture so C2 is a *void*, not a *refund* — and so there is a clean **pivot transaction**, the single most important concept in saga design and the one most tutorials omit.
**Avoids:** Pitfalls 31, 32, 33, 34, 35. Anti-patterns AP4, AP5, AP10.
**Research flag:** ⏭️ Skip — saga/outbox/idempotency patterns are well-established and ARCHITECTURE.md contains concrete, stack-specific implementations.

**Phase 6 — Karpenter + Spot + graceful drain** *(∥ with 7)*
**Rationale:** **Deliberately after Phase 5** — a Spot interruption *mid-saga* is the scenario you actually want, and it doesn't exist until the saga does.
**Delivers:** Karpenter chart + `NodePool`/`EC2NodeClass` via Argo CD (AWS side already exists from Phase 1). **`karpenter.sh/v1` API** — all v1beta1 YAML is dead (`kubelet` moved to EC2NodeClass, `nodeClassRef` needs group+kind+name, `amiSelectorTerms` now required). `consolidateAfter: 5m` (the default is `0s` and thrashes a small cluster), disruption budget `nodes: "1"`, `expireAfter` **and** `terminationGracePeriod` both set, `limits` set. ≥10 instance types across ≥2 families. PDBs: **`maxUnavailable: 1` for single-replica workloads, `minAvailable: 1` only at replicas ≥2.** Drain step 2 becomes live.
**Avoids:** Pitfalls 13, 14, 15, 16, 17. Anti-pattern AP6.
**Research flag:** ⏭️ Skip — Karpenter v1 docs are excellent. **But verify the `Balanced` consolidation policy exists in the pinned version before relying on it.**

**Phase 7 — Observability depth** *(∥ with 6)*
**Delivers:** kube-prometheus-stack tuned, Loki (SingleBinary, S3), Grafana Alloy, RED/USE dashboards (**3 you wrote and can defend, not 40 imported**), **DLQ-depth alerts on every `-dlq` queue at >0**, Prometheus exemplars (metric → one click → the exact trace), cardinality guards (`enforcedSampleLimit`, `enforcedLabelLimit`). SLO burn-rate decision (see OQ2).
**Avoids:** Pitfalls 20, 22, 23, 24. Anti-patterns AP7, AP8.
**Research flag:** ⏭️ Skip, **but measure**: record actual `kubectl top` figures for the platform stack and correct the ~2.1 vCPU / 6.1 GiB estimate.

**Phase 8 — Security hardening** *(∥ with 9)*
**Rationale:** **Deliberately late.** Added after things work, every failure is attributable; added early, every bug looks like a policy bug. Debugging NetworkPolicy without metrics and logs is miserable.
**Delivers:** ESO + Parameter Store, Cognito at the gateway + ALB-native auth on platform paths, NetworkPolicies default-deny **namespace by namespace with a negative enforcement test** (VPC CNI does not enforce by default — the dangerous failure is applying policies, nothing breaking, and believing zero-trust works when *nothing is being enforced*), Kyverno **Audit-first, always**, with system namespaces excluded and `failurePolicy: Ignore` on this cluster, WAF on the anchor Ingress, a Kyverno policy rejecting Exclusive annotations on non-anchor IngressGroup members, EKS envelope encryption.
**Avoids:** Pitfalls 20, 36, 37, 38, 39. Anti-pattern AP9. **Keep `kubectl delete validatingwebhookconfiguration ...` at the top of the runbook, in bold.**
**Research flag:** 🔬 **YES** — Kyverno policy authoring for the Exclusive-annotation guard, and VPC CNI NetworkPolicy enforcement verification.

**Phase 9 — Frontend + notification Lambda + CloudFront** *(∥ with 8)*
**Rationale:** The `notification` Lambda is a **choreographed** consumer — it reacts to `OrderConfirmed` off EventBridge and `order` has no knowledge it exists. Adding it requires **zero changes to `order`**, which proves loose coupling concretely. One system, both saga styles, contrast made real.
**Delivers:** Minimal React 19 + Vite 8 SPA → S3 + CloudFront with **OAC (not OAI — legacy, feature-frozen)**, `PriceClass_100`, `custom_error_response` for SPA routing. `notification` Lambda logs + emits a metric (SES optional).
**Critical:** **CloudFront must never be in the daily loop** — 5–15 min to deploy, **15–45 min to delete**. It lives in L0.
**Research flag:** ⏭️ Skip.

**Phase 10 — Progressive delivery + load generation**
**Delivers:** k6 load generation (needed to *cause* optimistic-locking conflicts — they don't occur at 1 RPS) and Argo Rollouts canary on `catalog` gated by a Prometheus `AnalysisTemplate` that **automatically aborts and rolls back** a deliberately-broken build.
**Note:** **Skip canary on the saga services.** Mid-saga version skew (event schema compatibility across versions) is a legitimately hard problem and a rabbit hole, not a phase.
**Research flag:** 🔬 **YES** — Argo Rollouts + ALB `TargetGroupBinding` traffic-splitting mechanics.

**Phase 11 — Chaos + runbooks**
**Rationale:** The payoff. The Features researcher's judgement: *"The single highest-signal artifact in the entire repo is a runbook that documents a wrong hypothesis."* Unfakeable — no LLM and no tutorial produces it.
**Delivers:** Chaos Mesh (in-cluster faults, GitOps-able CRDs) + **AWS FIS** (the only way to get an authentic 2-minute Spot interruption notice via `aws:ec2:send-spot-instance-interruptions`). ≥5 scenarios ranked by learning value: (1) real Spot interruption mid-saga, (2) payment timeout that actually succeeded, (3) SQS consumer killed between processing and delete, (4) DNS failure, (5) network latency on inventory, (6) OOMKill. **FIS experiment templates are free to keep** (you pay only per action-minute), so they live in Terraform permanently without touching the idle budget.
**Exit criterion:** a phase is not complete until its runbook exists and a cold reader could follow it. Write **during**, not after.
**Research flag:** ⏭️ Skip.

**Phase 12 — Testing depth** *(∥ with 11)*
**Delivers:** Testcontainers 2.0.5 (**note: artifact IDs changed — `testcontainers-postgresql`, not `postgresql`; every pre-2026 tutorial is wrong**) + LocalStack for the outbox poller and idempotent consumers. **Spring Cloud Contract over Pact** — a Pact Broker is another service to host and destroy daily, directly conflicting with the teardown constraint. Event-schema backward-compatibility tests. E2E smoke gate covering **happy path AND compensated-failure path**. Chaos-as-test in CI.
**Research flag:** ⏭️ Skip.

### Parallelizable work

```
P0 ──┬──▶ P1 ──▶ P2 ──▶ P3 ──▶ P4 ★ ──▶ P5 ──┬──▶ P6 ──┬──▶ P11
     └──▶ P1b ───────────┘                    ├──▶ P7 ──┴──▶ P10
                                              ├──▶ P8
                                              ├──▶ P9
                                              └──▶ P12
```
- **P1 ∥ P1b** — service scaffolding needs no cluster.
- **P6 ∥ P7** — Karpenter and observability depth are independent.
- **P8 ∥ P9 ∥ P12** — security, frontend, and testing all hang off P5 independently.
- P10 requires P7 (needs metrics for canary analysis). P11 requires P5 + P6 + P7.

---

## Part 4 — Open Questions and Unresolved Disagreements

These are surfaced deliberately. The roadmapper should treat each as a decision gate, not a detail.

### 🔴 OQ1 — Is RDS viable under same-day teardown?
**The conflict:** RDS create is ~6–10 min and delete ~5 min (snapshot-restore is *slower* than create, 10–20 min), eating a disproportionate share of a 3-hour practice session. Architecture argues strongly for **seed-from-scratch with `skip_final_snapshot = true`** — a snapshot chain is "precisely the hidden state that produces *works on my rebuild*." Features recommends **measuring restore time in the first infra phase** with in-cluster Postgres as fallback and explicitly says *"do not pre-commit — this is the single constraint most likely to force an architecture change."* Pitfalls goes further: in-cluster Postgres as the **default**, with `var.use_rds` for RDS-focused sessions.
**Recommendation:** `var.use_rds`, defaulting **false**. Measure real create/delete time in Phase 1 and record it in `COSTS.md`. If `make up` with RDS stays under 20 min total, flip the default. Keep the RDS module either way — deleting it loses parameter-group, backup, and IAM-auth practice. Also keep `var.preserve_final_snapshot` (default false) for the genuinely valuable case: you have produced an *interesting broken state* mid-chaos-exercise and want to resume debugging tomorrow.
**Status:** **UNRESOLVED — decide in Phase 1 with measured data.**

### 🔴 OQ2 — Prometheus data loss vs the SLO burn-rate requirement
**The conflict, stated plainly:** PROJECT.md requires "alerting rules on SLO burn." Multi-window multi-burn-rate alerting is only meaningful with multi-day history. Every `make down` destroys the TSDB. **These two requirements are genuinely incompatible as written.** Features separately notes the trigger for SLO work should be "2+ weeks of real metric history to set a defensible target" — which this architecture cannot produce.
**The three options (Pitfalls):** (a) Thanos/Mimir with S3 as long-term storage, bucket out of the teardown — costs pennies, real complexity, *and is exactly the kind of thing worth practising*; (b) accept the loss and compress the SLO window to 1 hour instead of 30 days — honest, cheap, less realistic; (c) keep an EBS PVC alive across teardowns — **do not**, it is precisely the orphan pattern that kills the project.
**Recommendation:** **(a), deferred to Phase 7 or later.** Loki and Tempo are already S3-backed, so the pattern is established; extending it to Prometheus blocks is incremental. Until then, practise *writing* burn-rate rules against a compressed window and be explicit in `DECISIONS.md` that you have never seen one fire on real history.
**Status:** **UNRESOLVED — must be an explicit, recorded decision. An undecided answer here means you default to losing everything and are quietly frustrated.**

### 🟠 OQ3 — ElastiCache vs in-cluster Redis
**The conflict:** Architecture recommends ElastiCache for M1 *"precisely because it exercises subnet groups, security groups, an intra-subnet with no egress, and a real network boundary — which is the learning"* — but flags it as **"the first thing to cut."** Pitfalls and the wall-clock arithmetic favour cutting it now.
**Recommendation:** **Cut it from the default profile (Profile A); keep the Terraform module behind a toggle for Profile B/C sessions.** The subnet-group/SG/intra-subnet learning is delivered by RDS anyway when `use_rds=true`, so almost nothing is lost. `cart` is explicitly ephemeral TTL state.
**Status:** **Resolved with low confidence — reverse freely if `make up` time turns out not to be the binding constraint.**

### 🟠 OQ4 — Does the full observability stack + six Spring Boot services actually fit?
**The conflict:** Architecture's ~2.1 vCPU / 6.1 GiB platform figure is **MEDIUM confidence, composed from typical chart defaults**. Stack independently estimates ~2.5–4 GiB for observability alone and tags it `[UNVERIFIED]`. Pitfalls estimates 3.5–6.5 GiB for observability and warns it "plausibly consumes 40–60% of the entire cluster before a single Spring Boot service starts." Nobody measured it.
**Recommendation:** **Sequence the signals separately so each one's footprint can be measured** — Prometheus + Tempo in Phase 3, Loki in Phase 7. Give the observability stack **its own Karpenter NodePool with its own `limits` and a taint**, so it physically cannot starve the application — this converts a silent degradation into an explicit, visible `Pending` pod. Record actual `kubectl top` figures and correct the estimate.
**Status:** **UNRESOLVED until measured. Treat all three estimates as hypotheses.**

### 🔴 OQ5 — OTel trace context across SNS/SQS/EventBridge
**Flagged by three of four researchers as the single most likely thing to silently break distributed tracing — and it is the flagship demo.**
The specific mechanics:
- **SQS:** the OTel Java agent's AWS SDK v2 instrumentation injects `traceparent` into `MessageAttributes` — but **SQS allows only 10 message attributes** and injection silently fails if you've used them.
- **SNS→SQS:** message attributes are lost unless raw message delivery is configured, or they end up wrapped inside the SNS envelope body where the consumer instrumentation doesn't look.
- **EventBridge: `PutEvents` has no message-attribute channel at all.** `traceparent` **must ride inside `detail`** (e.g. `detail.traceparent`) and be extracted manually with `W3CTraceContextPropagator`. This is *not* automatic, and PROJECT.md's backbone is EventBridge, so **this will happen**.
- **The outbox makes it worse:** the event is written to Postgres in one transaction and published later by a relay, at which point the original context is long gone. **Store `traceparent` as a column in the outbox table.** Without this, the outbox pattern *guarantees* trace breakage — a subtlety most tutorials miss entirely.
- **The false negative that wastes days:** OTel's SQS instrumentation often creates a span with a **Link** rather than a parent-child relationship (semantically correct for batch consumption), and **Tempo/Grafana do not render linked spans as one trace by default**. Propagation worked; you still see two traces. Check Links vs Parent in the Tempo UI before concluding it's broken.
**Recommendation:** **Do not rely on broker-level propagation.** Define the envelope explicitly in Phase 3 and inject/extract manually. More code, but deterministic, debuggable, broker-agnostic, and what you'd do in production anyway. Make it an **explicit named task in Phase 4, not an afterthought**, with an automated Tempo assertion as the acceptance criterion.
**Status:** **Resolved in approach, unverified in practice. Highest-priority research flag.**

### 🟡 OQ6 — Smaller open items
- **Spring Boot 4.1.1 vs 3.5.16** — Boot 4 restructured autoconfiguration into fine-grained modules; some third-party starters lag. Decide once in Phase 1b and pin in a shared parent POM; fall back as a *set*, never piecemeal.
- **Argo CD chart 10.9.2 default resource requests** — `[UNVERIFIED]`. Read `values.yaml` and record real numbers.
- **`kubernetes` and `helm` Terraform provider versions** — placeholder constraints in STACK.md. Pin exactly.
- **Terraform vs OpenTofu** — OpenTofu 1.12.6 is a viable drop-in with native state encryption. Not recommended *only* because registry modules (EKS v21) are CI-tested against Terraform. Reasonable to revisit.
- **Public IPv4 rate ($0.005/hr), CloudWatch Logs rates, CloudFront free-tier terms, ECR rate** — all MEDIUM, none re-verified. Folded into the Phase 0 pricing research flag.

---

## Part 5 — Key Findings by Source

### Recommended stack (from STACK.md)

Every version below was fetched live on 2026-09-24 from GitHub release redirects, Maven Central `maven-metadata.xml`, the npm registry, the Terraform Registry API, Helm `index.yaml` files, AWS docs, and the AWS Price List API. **Confidence: HIGH unless tagged.** `[U]` = `[UNVERIFIED]`, carried forward from the source — **do not launder these into apparent certainty.**

| Layer | Component | Version | Confidence |
|---|---|---|---|
| **IaC** | Terraform | `1.16.4` (pin `>= 1.13`) | HIGH |
| | `hashicorp/aws` | `~> 6.66` (6.66.0) — **v6 mandatory**, EKS v21 requires `>= 6.0` | HIGH |
| | `hashicorp/tls` | `~> 4.0` — required `>= 4.0` by EKS v21 | HIGH |
| | `hashicorp/kubernetes` | `~> 2.38` | **`[U]`** — placeholder, verify |
| | `hashicorp/helm` | `~> 3.0` | **`[U]`** — placeholder, verify |
| | `terraform-aws-modules/eks/aws` | `~> 21.26` (21.26.0) — **no `kubernetes` provider required** | HIGH |
| | `terraform-aws-modules/vpc/aws` | `~> 6.7` (6.7.3) | HIGH |
| | `terraform-aws-modules/iam/aws` | `~> 6.8` (6.8.2) | HIGH |
| | `RaJiska/fck-nat/aws` | `~> 1.6` (1.6.1, pub. 2026-08-15, 813k dl/mo) | HIGH |
| **Cluster** | Amazon EKS / Kubernetes | **`1.34`** (standard support: 1.36/1.35/1.34) | HIGH |
| | Karpenter | `1.14.1` — **`karpenter.sh/v1` API** | HIGH |
| | AWS Load Balancer Controller | app `v3.5.0` / chart `3.5.0` — **major v3**, v2 values not drop-in | HIGH |
| | External Secrets Operator | chart `2.11.0` — API is **`external-secrets.io/v1`** | HIGH |
| | Kyverno | app `v1.19.1` / chart `3.9.1` | HIGH |
| | metrics-server | `v0.9.0` | HIGH |
| | EBS CSI driver | `v1.66.0` — as an **EKS managed addon**, not Helm | HIGH |
| **GitOps** | Argo CD | `3.5.3` / chart `argo-cd` `10.9.2` — **major v3** | HIGH |
| **Observability** | kube-prometheus-stack | chart `91.5.1` / operator `v0.94.1` | HIGH |
| | Loki | chart `7.3.0` / app `3.6.12` — **must set `deploymentMode: SingleBinary`** | HIGH |
| | Tempo | chart `1.24.4` / app `2.9.0` — **monolithic `tempo` chart** | HIGH |
| | Grafana | `10.5.15` | HIGH |
| | Grafana Alloy | chart `1.12.1` / `v1.19.2` — **Promtail EOL 2026-03-02** | HIGH |
| | OTel Java agent | `v2.31.1` — explicit Spring Boot 4 support in CHANGELOG | HIGH |
| | OTel Java BOM | `1.66.0` | HIGH |
| **Java** | Temurin JDK | **25 (LTS)** — compact object headers, generational ZGC | HIGH |
| | Spring Boot | `4.1.1` (fallback `3.5.16`) | HIGH |
| | Spring Cloud | `2025.1.3` | HIGH |
| | Spring Cloud Gateway | `5.0.3` — **`-server-webmvc` flavour, not WebFlux** | HIGH |
| | Spring Cloud AWS | `4.1.1` | HIGH |
| | AWS SDK for Java v2 | `2.55.4` | HIGH |
| | Testcontainers | `2.0.5` — **artifact IDs changed: `testcontainers-<module>`** | HIGH |
| | LocalStack | `4.14.0` | HIGH |
| **Frontend** | React / React DOM | `19.3.0` | HIGH |
| | Vite | `8.3.0`, `@vitejs/plugin-react` `6.1.1` | HIGH |
| | TypeScript | `7.0.2` (TS 5.x is long stale) | HIGH |
| **CI** | `aws-actions/configure-aws-credentials` | `v6.3.0` — **pin by commit SHA, not tag** | HIGH |
| | Trivy | `v0.74.0` — image **and** IaC misconfig | HIGH |
| | Checkov | `3.3.19` | HIGH |
| | ~~tfsec~~ | ☠️ **DEAD** — absorbed into Trivy | HIGH |

**Five things that will break your tutorials:** (1) EKS module v21 removed `aws-auth` and Karpenter IRSA; (2) Karpenter v1beta1 YAML is dead; (3) Loki SSD is deprecated *and is still the chart default*; (4) tfsec is Trivy; (5) ALB Controller v3 and Argo CD v3 both crossed major versions.

**JVM flags that matter on tiny Spot nodes** (MEDIUM — well-established practice, not doc-verified this session):
`-XX:MaxRAMPercentage=65.0` (**65, not 75 — the OTel agent adds 50–100 MiB**), `-XX:+UseSerialGC` below ~2 GiB, `-XX:MaxMetaspaceSize=128m`, `-XX:MaxDirectMemorySize=64m` (defaults to *heap size* — Netty/OTLP buffers can silently double your footprint), `-XX:+ExitOnOutOfMemoryError`, `-Dnetworkaddress.cache.ttl=30` (the JVM historically caches DNS forever — matters for RDS failover), **`requests == limits` for memory (Guaranteed QoS)**. Realistic sizing: a Spring Boot service with the OTel agent, JPA, and an AWS SDK client needs **~640–768 MiB limit**, not 512.

### Expected features (from FEATURES.md)

Success metric here is **learning value ÷ implementation effort**, not user value. The rule: *if a feature's failure mode is "returns 500", it is CRUD. If its failure mode is "succeeded on one side and failed on the other", it is instructive.*

**Must have (table stakes):**
- Terraform remote state in a never-destroyed bootstrap stack — if state dies, the practice loop dies
- `make up` / `make down` + **teardown verification sweep** (LOW effort, HIGH learn — *the highest-ratio item in the entire platform section*)
- EKS + Karpenter on Spot with **real graceful shutdown** (preStop + `terminationGracePeriodSeconds` + PDBs — where CKA theory meets reality)
- Argo CD app-of-apps + **sync waves** (load-bearing *here specifically*: on a cluster provisioned from zero every session, the CRD-before-CR race is not an edge case, it is your default experience)
- Pod Identity per service; GitHub Actions OIDC; ESO ← Parameter Store
- **The saga**: outbox, idempotent consumers, optimistic locking, compensation, DLQs
- **`payment-sim` runtime failure injection** — *the best effort-to-learning ratio in the entire project* (LOW effort, VERY HIGH learn). Enables the single most instructive scenario: *payment times out but actually succeeded.*
- **OTel trace across the async hop** — VERY HIGH learn; the thing every tracing demo skips
- Smoke/E2E covering happy path **and** compensated-failure path
- ≥5 chaos scenarios with runbooks written by debugging

**Should have (differentiators — ranked by signal ÷ effort):**
1. A real saga with outbox + idempotency + compensation — *none of the four reference implementations has this*
2. Runbooks documenting **wrong hypotheses** — unfakeable, the strongest proof-of-work in the repo
3. Trace propagation across SNS/SQS/EventBridge
4. Real Spot interruption chaos via FIS with proven graceful drain mid-saga
5. Teardown verification + documented cost model + Infracost CI gate — cost discipline as an engineering artifact
6. Automated canary rollback driven by Prometheus analysis
7. Chaos-as-test in CI (turns chaos from a party trick into a gate)
8. Kyverno in **`enforce`**, not `audit` — most repos never flip it
9. Prometheus exemplars: p99 spike → one click → the exact trace (LOW effort, reads as genuinely expert)
10. OpenCost → Prometheus → Grafana cost dashboard (**OpenCost over Kubecost** — the free Kubecost tier adds a SaaS dependency for no extra learning)

**Defer / never build:** service mesh for mTLS (Istio's control plane alone is ~1 GB RAM plus sidecar overhead — materially changes your instance sizing); **more services** (service count is the most seductive fake-progress metric — Online Boutique has 11 services and 0 sagas); self-hosted Kafka via Strimzi (3 brokers + persistent volumes on daily-destroyed Spot nodes is a nightmare; the "cheap MSK workaround" is the trap); full Pact + broker (another service to host daily, solving an inter-team problem a single author doesn't have); custom operators or a custom chaos framework; a polished frontend; Backstage; 90% coverage chasing; real SES delivery; product/user/address CRUD (seed from a fixture).

**Where "realistic" crosses into "never finishes":** (1) operating stateful infrastructure you didn't need; (2) breadth over depth; (3) building tooling instead of using tooling; and the subtle fourth — **(4) making it too cheap to be instructive.**

### Architecture approach (from ARCHITECTURE.md)

**The one-sentence thesis:** every decision is downstream of *it must die cleanly every night*, and the decision that determines whether that works is **where the Terraform/Kubernetes boundary sits**.

**Major components:**
1. **L0 `00-bootstrap` (immortal, ~$2–3/mo)** — state, ECR, OIDC, secrets, observability bucket, SPA+CloudFront, Budgets. Everything whose loss makes a rebuild slow or expensive.
2. **L1 `10-infra` (per session)** — VPC, fck-nat, gateway endpoints, EKS control plane, system MNG, EKS addons, all IAM/Pod Identity, Karpenter's AWS side. *Network and cluster deliberately merged: identical lifetimes, and the cluster's destroy is what releases the VPC's ENIs.*
3. **L2 `20-data` (per session)** — RDS, DynamoDB, ElastiCache, EventBridge bus + rules, SQS + DLQs, SNS, Cognito. Split from L1 because lifetimes genuinely can diverge.
4. **L3 `30-gitops` (per session)** — `helm_release.argocd` + one root Application. **Two resources.** The only Terraform that touches the Kubernetes API, and the first thing destroyed.
5. **Argo CD** — owns every Kubernetes API object: platform, observability, ecommerce.
6. **The six services + one Lambda** — `api-gateway` (edge, JWT, `Idempotency-Key` enforcement), `order` (**saga orchestrator**, owns the state machine and outbox), `inventory` (conditional decrement + reservation-as-dedupe-record), `payment-sim`, `catalog`, `cart`, `notification` (**choreographed** consumer — `order` doesn't know it exists).

**Key patterns:** Orchestration over choreography (*the saga state is a table you can query, and for someone building debugging skill a saga you can **see** is worth an order of magnitude more than one you must infer*) — but build both styles, with `notification` as the choreographed contrast. Polling publisher over Debezium (Debezium needs `wal_level = logical` → custom parameter group → **instance reboot on every `make up`**). Shared ALB via IngressGroup co-hosting Grafana and Argo CD (saves ~$0.045/hr, 15% of the hourly budget) **with one anchor Ingress owning all Exclusive annotations** — one careless annotation on the Grafana Ingress *freezes reconciliation for the entire group, silently*. Conditional decrement for `inventory` stock; `@DynamoDbVersionAttribute` optimistic locking for `catalog` documents — both practised, each where it is actually correct.

### Critical pitfalls (top 5 from PITFALLS.md)

1. **Interface VPC endpoints cost more than the NAT they replace** 🔴 — $73/mo for five endpoints across 2 AZs. **Already latent in PROJECT.md.** → Gateway endpoints only; interface endpoints behind a default-false flag. *A textbook case of applying a production heuristic outside its validity range — exactly the gap certifications leave.*
2. **Resources orphaned by `terraform destroy`** 🔴 — ALBs, controller-created SGs, Karpenter instances, PVC-provisioned EBS. The mental model "Terraform manages my infrastructure" is **false** the moment a Kubernetes controller with an IAM role exists; Argo CD, the ALB Controller, Karpenter, and the EBS CSI driver are **a second infrastructure-provisioning system running inside the first one's product.** → Ordered drain → destroy → verify, with polling.
3. **The Terraform `kubernetes`/`helm` provider cannot reach a cluster that no longer exists** 🔴 — destroy wedges, state is stuck, and the VPC and ALBs keep billing while you panic-`state rm`. A **structural limitation**, not a bug you can configure away. → Split state; confine the providers to L3; destroy L3 first.
4. **The observability stack eats the cluster** 🔴 — kube-prometheus-stack + Loki + Tempo at default values plausibly consumes 40–60% of a 2–3 node cluster. App pods OOMKill, Karpenter adds nodes, cost doubles, and **you spend a week debugging "flaky services."** *The single most under-anticipated pitfall*, because the mental model is "Prometheus is just a scraper." → Explicit requests+limits, 6h retention, 60s scrape, disable the etcd/scheduler/controller-manager jobs EKS doesn't expose, its own NodePool with its own `limits`.
5. **"Infrastructure forever, never ship a feature"** 🟠 — three months in, the Terraform is beautiful and **not one HTTP request has ever traversed the system.** Infrastructure work has endless legitimate depth and, with no deadline, no forcing function. *The highest-quality-feeling work is always "tighten the IAM policy" rather than "write a controller."* → Walking skeleton by Phase 2, vertical slices not horizontal layers, time-boxed infra phases, a visible artifact per session.

**Honourable mentions that will each cost a session:** JVM `OOMKilled` despite a correct `-Xmx` (the cgroup kills you, the JVM never sees an `OutOfMemoryError` — *that silence is the signature*); liveness probes pointing at bare `/actuator/health`, converting a 5-second RDS blip into a fleet-wide restart storm; the `preStop` deregistration race (graceful shutdown solves *in-flight* requests, not *newly-arriving* ones during the 10–30s ALB deregistration window); Kyverno `Enforce` locking you out of your own cluster while the bill climbs; and `minAvailable: 1` PDBs on single-replica workloads making pods permanently undrainable, blocking Karpenter consolidation forever.

---

## Confidence Assessment

| Area | Confidence | Notes |
|---|---|---|
| **Stack** | **HIGH** | Every version fetched live from authoritative registries on 2026-09-24. Ten items explicitly tagged `[UNVERIFIED]` and carried forward above. Recommendations (Web MVC over WebFlux, agent over starter, Boot 4 over 3.5) are MEDIUM — clearly marked as opinion in the source. |
| **Features** | **HIGH** | Reference-implementation analysis verified against upstream READMEs; FIS/Chaos Mesh/Argo Rollouts/OpenCost capabilities verified against primary docs. "What reads as production-grade to a reviewer" and all effort/learn ratings are **MEDIUM — synthesis, not citation.** |
| **Architecture** | **HIGH on mechanics, MEDIUM on numbers** | TF/K8s boundary, S3 native locking, IngressGroup semantics, Karpenter v1, Loki chart defaults all read directly from primary sources. **AWS unit pricing beyond EKS was not re-verified.** The 2.1 vCPU / 6.1 GiB capacity table is composed from chart defaults and must be measured. |
| **Pitfalls** | **HIGH on cost/pricing and Karpenter/ALB mechanics, MEDIUM on operational folklore** | EKS, PrivateLink, ELB, Route 53, EBS pricing all verified live. Teardown orphan inventory, OTel async breakage, bill horror stories, and observability memory figures are synthesized community patterns — **a threat model, not a citation.** |

**Overall confidence: MEDIUM-HIGH.** The four documents agree with each other far more than they disagree, and where they disagree it is on judgement calls (ElastiCache, AZ count, RDS) rather than facts. That convergence is itself evidence. The main exposure is the **cost model**, where only two rates were authoritatively verified and the entire budget rests on the rest.

### Gaps to Address

| Gap | Handling |
|---|---|
| **AWS unit pricing for the chosen region** | **Phase 0 blocker.** Only EKS ($0.10/hr) and interface endpoints ($0.01/endpoint-AZ-hr) were fetched from authoritative AWS sources. Validate the entire model against the Pricing Calculator before the roadmap commits to the budget. |
| **Real platform resource footprint** | Measure with `kubectl top` in Phases 2 and 7; sequence Prometheus+Tempo separately from Loki so each is measurable. Correct the estimate in `DECISIONS.md`. |
| **`make up` / `make down` wall-clock** | Instrument from Phase 1. Non-functional requirement: **≤20 min up, ≤15 min down.** A regression past 25 min is a defect, not an annoyance. Log to `COSTS.md`. |
| **OTel `traceparent` across EventBridge** | Design the envelope in Phase 3; assert it automatically against the Tempo API in Phase 4. Do not rely on broker-level propagation. |
| **arm64 image availability across every chart** | Audit in Phase 1b, before it is expensive to reverse. Graviton is ~20% cheaper but means `buildx` on `ubuntu-24.04-arm` runners. |
| **Spring Boot 4.1.1 third-party starter compatibility** | Decide once in Phase 1b, pin in a shared parent POM, fall back as a *set*. |
| **RDS create/restore time** | Measure in Phase 1; it decides OQ1. |
| **Argo CD chart 10.9.2 default resource requests** | Read `values.yaml`; record real numbers in Phase 2. |
| **SLO burn-rate history** | Explicit recorded decision required (OQ2). Do not leave undecided. |

---

## Sources

### Primary (HIGH confidence — fetched live 2026-09-24)
- GitHub `releases/latest` redirects across 26 repos — all tool and controller versions
- `repo1.maven.org` `maven-metadata.xml` — all Java artifact versions (note: `search.maven.org`'s solr index returned **stale** data and was discarded)
- `registry.npmjs.org`, `registry.terraform.io/v1/modules/*`, Helm `index.yaml` (prometheus-community, grafana, aws/eks-charts, argoproj, kyverno)
- `pricing.us-east-1.amazonaws.com/.../AmazonVPC/...` — interface endpoint $0.01/endpoint-hr; gateway endpoints free
- `aws.amazon.com/eks/pricing/` — $0.10/cluster-hr standard, $0.60/hr extended
- `aws.amazon.com/privatelink/pricing/`, `/elasticloadbalancing/pricing/`, `/route53/pricing/`, `/ebs/pricing/`
- `docs.aws.amazon.com/eks/.../kubernetes-versions.html`, `/pod-identities.html`, `/cni-increase-ip-addresses.html`
- `terraform-aws-eks/docs/UPGRADE-21.0.md` — full v20→v21 breaking changes
- `karpenter.sh/docs/concepts/{nodepools,nodeclasses,disruption}/` + `/upgrading/compatibility/`
- `kubernetes-sigs/aws-load-balancer-controller` v3.5.0 `docs/guide/ingress/annotations.md` + subnet discovery
- HashiCorp `web-unified-docs` `language/backend/s3.mdx` — `use_lockfile`; `dynamodb_table` **Deprecated**
- `grafana/loki` `production/helm/loki/values.yaml` (chart 7.3.0) + deployment-modes + Promtail EOL notice
- `docs.spring.io/spring-boot/system-requirements.html`, spring-cloud-gateway reference, `external-secrets.io`, `java.testcontainers.org`
- `opentelemetry-java-instrumentation/CHANGELOG.md` — explicit Spring Boot 4 support entries
- `github.com/aquasecurity/tfsec` page title — *"Tfsec is now part of Trivy"*
- Upstream READMEs: `GoogleCloudPlatform/microservices-demo`, `microservices-demo/microservices-demo` (Sock Shop, DEPRECATED), `instana/robot-shop`, `dotnet/eShop`, `chaos-mesh/chaos-mesh`, `argoproj/argo-rollouts`, `fluxcd/flagger`, `opencost/opencost`
- AWS FIS fault injection actions reference

### Secondary (MEDIUM confidence)
- AWS list pricing for EC2/RDS/ElastiCache/ALB/EBS/ECR/CloudWatch/public IPv4 — long-stable, **not re-verified this session**
- Observability stack memory figures — typical observed defaults, **measure yours**
- Create/delete timings — order-of-magnitude, **record actuals in Phase 1**
- `db.t4g.micro` `max_connections` ≈ 80–100 — formula-derived (`LEAST({DBInstanceClassMemory/9531392}, 5000)`)
- JVM flag impact percentages; `t4g.nano` baseline bandwidth
- Argo CD chart default resource requests

### Tertiary (LOW confidence — needs validation)
- The `terraform destroy` orphan inventory for EKS — community-reported, consistent across many issue threads
- Learner bill horror-story causes — a threat model, not a citation
- OTel SQS/EventBridge context-propagation failure modes — strongly reported in community issues; verify against the pinned agent version
- "What reads as production-grade to a reviewer" and all effort/learning ratings — synthesis

### Detailed research
- `.planning/research/STACK.md` — versions, compatibility matrix, what-not-to-use, cost model
- `.planning/research/FEATURES.md` — feature prioritization matrix, anti-features, competitor analysis, MVP definition
- `.planning/research/ARCHITECTURE.md` — layer design, teardown choreography, saga design, capacity, anti-patterns
- `.planning/research/PITFALLS.md` — 47 pitfalls with prevention/verification, pitfall-to-phase mapping, "looks done but isn't" checklist, recovery strategies

---
*Research completed: 2026-09-24*
*Ready for roadmap: yes*
