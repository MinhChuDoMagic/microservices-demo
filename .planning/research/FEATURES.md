# Feature Research

**Domain:** Learning-focused, cost-constrained AWS EKS e-commerce microservices practice platform
**Researched:** 2026-09-24
**Confidence:** HIGH (reference-implementation analysis and tool capabilities verified against primary sources — upstream READMEs, Argo CD/Rollouts docs, AWS FIS action reference, OpenCost/Chaos Mesh docs). MEDIUM on "what reads as production-grade to a reviewer", which is synthesised judgement rather than a citable spec.

---

## Framing: What "Feature" Means Here

This project has no users. It has one operator (SAP-C02 + CKA) who needs operational scar tissue. So the
success metric for every candidate feature is not user value but:

> **learning value ÷ implementation effort**, subject to a hard cost ceiling (~$5/mo idle, ~$0.30/hr active)
> and the same-day-teardown constraint.

Two feature classes are treated separately throughout:

- **(a) E-commerce domain features** — exist *only* as a substrate for distributed-systems failure. Judged by
  "what distributed-systems problem does this create?" A feature that creates no such problem is dead weight.
- **(b) Platform/DevOps capabilities** — the actual deliverables. ~70% of the value.

Every row carries **Effort** and **Learn** (learning value). Rows where Effort > Learn are candidates for
deletion regardless of how good they look on a README.

---

## Part A — E-Commerce Domain Features (30% weight)

### A1. The Instructive Set (features that generate real distributed-systems problems)

| Feature | DS problem it creates | Effort | Learn | Ratio | Notes |
|---------|----------------------|--------|-------|-------|-------|
| **Order saga orchestration** (order → payment → inventory) | Partial failure, compensating transactions, state machine persistence, timeout semantics | HIGH | **VERY HIGH** | ★★★ | The centrepiece. Everything else in the project is scaffolding for this. Orchestration (not choreography) chosen deliberately — the saga state is *inspectable*, which is what makes debugging teachable. |
| **Transactional outbox in `order`** | Dual-write problem; at-least-once delivery guarantee across a DB commit + broker publish | MED | **VERY HIGH** | ★★★ | Highest ratio in the whole project. ~200 lines + a poller/CDC. Teaches the single most misunderstood pattern in event-driven systems. Non-negotiable. |
| **Idempotent consumers** (dedup table / conditional write keyed on message ID) | Exactly-once *effects* over at-least-once delivery; SQS redelivery | MED | **VERY HIGH** | ★★★ | Only becomes real once you deliberately replay a DLQ. Pair with the chaos scenarios or it stays theoretical. |
| **Inventory reservation w/ optimistic locking** | Write-write conflict, lost update, ABA; DynamoDB conditional writes + `ConditionalCheckFailedException` retry loop | MED | **VERY HIGH** | ★★★ | The cleanest way to *feel* concurrency control. Must be exercised by concurrent load or it never fails. |
| **Compensating "release reservation" path** | Rollback without distributed transactions; compensation that must itself be idempotent and can itself fail | MED | **VERY HIGH** | ★★★ | The failure-of-the-compensation case is the lesson most people never reach. |
| **`payment-sim` with configurable failure injection** | Timeout vs. failure ambiguity — "did the charge go through?" | **LOW** | **VERY HIGH** | ★★★★ | Best ratio in the entire feature set. A Spring Boot service with an endpoint to set `failureRate`, `latencyMs`, `timeoutRate`. Enables the single most instructive scenario: *payment times out but actually succeeded*. |
| **Cart with Redis TTL** | Ephemeral state, cache-vs-truth divergence, session affinity-free design | LOW | MED | ★★ | Cheap. Teaches "state that is allowed to be lost" — a real design category. |
| **Catalog read path + cache** | Cache invalidation, read-your-writes, stale reads under HPA scaling | LOW | MED | ★★ | Worth it only if you actually implement invalidation-on-write and observe the stale window. |
| **Order status query (read model)** | Eventual consistency made *visible* to the caller; read/write skew | LOW | HIGH | ★★★ | Very cheap given the saga exists. A `GET /orders/{id}` that legitimately returns `PENDING` for 3 seconds is the most honest demonstration of eventual consistency you can build. |
| **DLQ + redrive tooling** | Poison-message handling, operational recovery ergonomics | LOW | HIGH | ★★★ | A `make redrive-dlq` target. Trivially cheap, and it is a genuine day-2 operations skill. |

### A2. CRUD Busywork — Stub, Fake, or Skip

| Feature | Why it teaches nothing | Verdict |
|---------|----------------------|---------|
| Product CRUD admin (create/edit/delete products) | Pure single-service CRUD. Zero distributed behaviour. | **Seed from a JSON/Terraform fixture.** No admin API. |
| User registration / profile management | Cognito already covers the instructive part (OIDC, JWT validation). A `users` table is boilerplate. | **Cognito only.** No profile service. Matches PROJECT.md M1 decision. |
| Address book, saved cards, wishlists | N× CRUD tables. No new failure mode. | **Skip entirely.** |
| Product search / faceting | Real learning is OpenSearch ops, not e-commerce. Already deferred to M2 in PROJECT.md. | **Skip in M1.** (Correctly deferred.) |
| Reviews / ratings / recommendations | Additive surface. Online Boutique has both and neither creates a consistency problem. | **Skip.** (Correctly deferred.) |
| Shipping-rate calculation | Online Boutique mocks it. So should you. | **Constant function.** |
| Real email/SMS delivery | SES sandbox + identity verification is 2 hours of AWS console friction for zero distributed-systems learning. | **`notification` Lambda logs the event + emits a metric.** Wire SES only if the sandbox proves painless. |
| Currency conversion | Online Boutique's highest-QPS service and it teaches nothing but RPC volume. | **Skip.** |
| Discounts / coupons / tax | Business-rule complexity, not systems complexity. | **Skip.** |

**The rule:** if a feature's failure mode is "returns 500", it is CRUD. If its failure mode is
"succeeded on one side and failed on the other", it is instructive.

### A3. Reference Implementation Analysis — What They Omit

Verified against upstream READMEs and repo structure (HIGH confidence on all "omits" claims below).

| | **Online Boutique** (GoogleCloudPlatform) | **Sock Shop** | **Robot Shop** (Instana) | **eShop** (dotnet) |
|---|---|---|---|---|
| **Status** | Actively maintained | **DEPRECATED** (README says so; Weave Scope/Weaveworks defunct) | Maintained, vendor demo | Actively maintained (.NET 10 + Aspire) |
| Services | 11, polyglot, gRPC | ~8, Spring Boot + Go kit + Node | ~8, NodeJS/Java/Python/Go/PHP | ~6 + Aspire AppHost |
| Catalog persistence | **A JSON file.** Not a database. | MongoDB | MongoDB | Postgres + pgvector |
| Async broker | **None** | RabbitMQ (shipping queue) | RabbitMQ | RabbitMQ (integration events) |
| **Saga / compensation** | **None** — `checkoutservice` is a *synchronous* gRPC fan-out to payment/shipping/email | **None** | **None** — queue is fire-and-forget dispatch | Partial — has integration events + an ordering process manager; closest of the four |
| Inventory / stock | **Does not exist** | Minimal | Minimal | Yes |
| Idempotency / outbox | None | None | None | Idempotency present; outbox not the canonical pattern |
| Failure handling | Mocked services always succeed | Minimal | **README self-declares: "the error handling is patchy and there is not any security built into the application"** | Reasonable |
| IaC / GitOps | Kustomize + Helm, no Terraform | Legacy scripts | Helm chart | None — local-first via Aspire |
| Cost model | Assumes GKE + Spanner/AlloyDB/Memorystore | n/a | n/a | Local Docker |

**The critical, unifying omission:** *none of these four demos has a real distributed-systems problem.*
Payment is a mock that always returns success. There is no inventory contention. There is no compensation
path. Online Boutique — by far the most popular — checkouts by calling four services synchronously in a row;
if one fails, the request fails, and that is the end of the story. They are **topology demos**, not
**failure demos**. Their purpose is to give a service mesh something to draw arrows between.

**Implication for this project — and it is the whole differentiation thesis:**
> Cloning Online Boutique's *shape* (a shop with N services) is worthless; there are a thousand such repos.
> The differentiator is building the ~1,200 lines those demos skip: outbox, idempotency keys, compensation,
> optimistic locking, and a `payment-sim` whose *job* is to fail. Six services with a real saga beats
> eleven services with a synchronous fan-out, and it is less work.

eShop is the only one worth borrowing patterns from (integration events, process manager). Sock Shop is
deprecated — do not use it as a reference. Robot Shop is useful only as a "what patchy error handling looks
like" counter-example.

---

## Part B — Platform / DevOps Capabilities (70% weight)

### B0. What Actually Separates Toy from Production-Grade

Be concrete. A senior reviewer scans for these specific tells, roughly in order:

| Tell | Toy | Production-grade |
|------|-----|------------------|
| **Teardown** | `README: "don't forget to delete the cluster"` | `make down` + an automated orphan-resource check that fails loudly |
| **Reproducibility** | Works on the author's laptop; one undocumented console click | Two consecutive `up`/`down` cycles from clean state, proven in CI |
| **Resource specs** | No `requests`/`limits`, no PDBs, no probes, or `readiness == liveness` | Requests set from observed usage, limits only on memory, distinct readiness/liveness/startup probes, PDBs, `terminationGracePeriodSeconds` tuned to actual drain time |
| **Secrets** | `kubectl create secret` in a script; base64 in Git | External Secrets Operator ← Secrets Manager; zero secret material in Git |
| **Identity** | One node role with `AdministratorAccess` | Per-service IRSA/Pod Identity with scoped, per-resource ARNs |
| **Failure evidence** | "Chaos engineering" section with one `kubectl delete pod` | Runbooks written *from an actual debugging session*, including the wrong hypotheses |
| **Cost** | Unmentioned | A stated ceiling, tagging, Budgets alarm, OpenCost dashboard, and teardown verification |
| **Rollback** | Not discussed | A demonstrated automated rollback triggered by a real metric |
| **Graceful shutdown** | Ignored | Spot interruption → drain → in-flight requests complete (this is the one almost nobody does) |

The single highest-signal artifact in the entire repo is **a runbook that documents a wrong hypothesis.**
Nothing else proves the work was actually done.

---

### B1. Table Stakes

Without these the project fails its stated purpose. Ordered by dependency.

| # | Capability | Why table stakes | Effort | Learn | Ratio | Notes |
|---|-----------|------------------|--------|-------|-------|-------|
| 1 | **Terraform + S3/DynamoDB remote state surviving teardown** | If state dies, the practice loop dies (PROJECT.md Core Value) | MED | HIGH | ★★★ | State backend must live in a *separate, never-destroyed* bootstrap stack. Getting this wrong on day 1 is the classic project-killer. |
| 2 | **`make up` / `make down` single-command lifecycle** | The constraint that makes everything else affordable | MED | HIGH | ★★★ | `down` must be idempotent and must succeed even from a half-broken state. |
| 3 | **Teardown verification (orphan sweep)** | The difference between "I think it's gone" and a $40 surprise | **LOW** | HIGH | ★★★★ | Tag-based Resource Groups Tagging API query + `aws ec2 describe-*` for untaggable leftovers (ENIs, EBS, EIPs, LBs from the LB Controller, log groups). ~60 lines. **Extremely underrated.** |
| 4 | **EKS + Karpenter on Spot with real graceful shutdown** | Spot + drain + in-flight requests is the highest-value K8s lesson here | MED | **VERY HIGH** | ★★★ | Requires `preStop` hooks, `terminationGracePeriodSeconds` > drain time, and PDBs. The interaction of these three is where CKA theory meets reality. |
| 5 | **Argo CD GitOps, pull-based** | Push-based `kubectl apply` from CI teaches the wrong thing | MED | HIGH | ★★★ | See B2 for layout. |
| 6 | **GitHub Actions → AWS via OIDC, zero long-lived keys** | Table stakes in 2026; a reviewer checks this first | LOW | MED | ★★★ | Trust policy `sub` condition scoping to branch/environment is the actual lesson. |
| 7 | **IRSA / Pod Identity per service** | Per-pod least privilege is *the* EKS security primitive | MED | HIGH | ★★★ | Do both: IRSA for some services, Pod Identity for others. Comparing them is free learning. |
| 8 | **External Secrets Operator ← Secrets Manager** | Zero secrets in Git is non-negotiable | LOW | MED | ★★ | Secrets Manager costs $0.40/secret/mo — keep the count low or use Parameter Store for non-secret config. |
| 9 | **Prometheus + Grafana, RED + USE dashboards** | Minimum credible observability | MED | MED | ★★ | See B3 — most people stop here and that is the mistake. |
| 10 | **OTel distributed tracing following one order across the full saga** | The single most valuable observability artifact in this project | MED | **VERY HIGH** | ★★★ | Trace context must survive the **async hop** (SNS/SQS message attributes). See B3 for why this is the hard part. |
| 11 | **Structured JSON logs with `trace_id` → Loki→Tempo correlation** | Log/trace correlation is what makes an incident tractable | LOW | HIGH | ★★★ | Cheap once tracing exists. Grafana derived fields. |
| 12 | **Unit + integration tests w/ Testcontainers** | Integration tests against real Postgres/Redis/LocalStack | MED | MED | ★★ | Testcontainers + LocalStack for SQS/SNS/DynamoDB is the high-value combination. |
| 13 | **Smoke/E2E suite gating deployment against the live cluster** | Proves the cluster actually works after `make up` | LOW | HIGH | ★★★ | Must include a **full happy-path order** and a **full compensated-failure order**. |
| 14 | **NetworkPolicies (default-deny + explicit allows)** | Zero-trust pod networking; requires a CNI that enforces them | MED | HIGH | ★★★ | Note: VPC CNI network policy enforcement must be explicitly enabled. A default-deny that silently does nothing is worse than none — **verify enforcement with a test**. |
| 15 | **Image scanning (Trivy + ECR scan-on-push) failing CI on HIGH/CRITICAL** | Table stakes supply-chain hygiene | LOW | LOW | ★★ | Cheap, expected, low learning. Do it, don't dwell. |
| 16 | **tfsec/Checkov in CI** | Same | LOW | LOW | ★★ | Budget an hour for baselining the inevitable false positives. |
| 17 | **AWS Budgets alarm + cost allocation tags** | Cost ceiling enforcement | LOW | MED | ★★★ | Budget alarms are *lagging* (up to 24h). Pair with #3 and #21. |
| 18 | **A runbook per chaos scenario, written by debugging** | PROJECT.md names this the highest-value component | MED | **VERY HIGH** | ★★★ | The deliverable is the *investigation narrative*, not the fix. |

### B2. GitOps Repo Layout — Table Stakes vs Advanced

Verified: ApplicationSet has been bundled with Argo CD since v2.3 and is the current idiom.

**Table stakes**
- A single `manifests/` tree, one Argo CD `Application` per workload, `automated` sync with `prune: true` and `selfHeal: true`. *`prune` and `selfHeal` off is the #1 tell of a GitOps demo that was never actually operated.*
- Kustomize `base/` + `overlays/{dev,prod}` — or Helm chart + per-env `values-*.yaml`. Pick **one**. Mixing both is a common self-inflicted wound.
- **App-of-apps**: one root `Application` pointing at a directory of child `Application`s. Bootstraps the whole cluster with one `kubectl apply` — which is exactly what `make up` needs.
- **Sync waves** (`argocd.argoproj.io/sync-wave`) to order CRDs → operators → platform addons → workloads. Without these, first-boot on a fresh cluster race-fails, and on a same-day-teardown project you hit that race *every single session*. This is table stakes **here** specifically.
- Separate `AppProject`s for `platform` vs `apps`, with source/destination restrictions.

**Advanced / differentiator**
- **ApplicationSet with a Git directory generator** to auto-discover services — new service = new directory, no Argo manifest to write. Genuinely elegant and ~30 lines.
- **ApplicationSet matrix generator** (services × environments) — the real payoff, but only if you actually run 2+ environments. On this budget you likely run one. **Probably over-engineering here.**
- Argo CD Image Updater or a CI write-back commit that bumps the image tag — closes the CI→CD loop properly and avoids the anti-pattern of `:latest`.
- `ignoreDifferences` for HPA replicas / mutating-webhook injections — a small thing that signals real operational experience.

**Recommendation:** app-of-apps + sync waves + Kustomize overlays + a Git-directory-generator
ApplicationSet for the services. Skip the matrix generator. Effort MED, Learn HIGH.

### B3. Observability — Minimum Credible, and What Is Done Badly

**Minimum credible set**
1. RED (rate/errors/duration) per service, USE (utilisation/saturation/errors) per node — Effort MED, Learn MED.
2. **One trace spanning the entire saga, including the async hops** — Effort MED, Learn VERY HIGH.
3. Log ↔ trace correlation via `trace_id` (Loki derived field → Tempo) — Effort LOW, Learn HIGH.
4. **Exemplars**: Prometheus histogram → click the p99 outlier → land on that exact trace. Effort LOW (OTel emits them), Learn HIGH. Wildly underused and looks extremely senior.
5. One real SLO (e.g. `order-submission availability 99%`) with **multi-window multi-burn-rate** alerting — Effort MED, Learn HIGH.

**Commonly done badly — avoid all of these**
- **Tracing that stops at the queue.** 90% of "distributed tracing" demos trace only synchronous HTTP. The moment the order goes to SNS/SQS, the trace ends. **Propagating W3C `traceparent` through SNS/SQS message attributes and resuming the span in the consumer is the single highest-value observability task in this project** — and it is exactly what Online Boutique et al. never have to solve, because they have no queue in the critical path.
- Dashboard sprawl: 40 imported community dashboards nobody reads. Ship 3 you wrote and can defend.
- Alerting on symptoms nobody acts on (`CPU > 80%`). Alert on **burn rate** and page-worthy symptoms only.
- Single-window threshold alerts (`error_rate > 1% for 5m`) — flappy and slow. Use the fast-burn (e.g. 1h/5m windows) + slow-burn (6h/30m) pair.
- Logging at `DEBUG` in a Loki instance with no retention cap — this is also a **cost** bug on a $5/mo budget. Cap retention hard (e.g. 24h — you destroy the cluster daily anyway).
- Metrics cardinality explosions from unbounded labels (`order_id`, `user_id`). Prometheus OOMKills on a Spot node is itself a good lesson, but only once.

### B4. Progressive Delivery

Verified: Argo Rollouts provides blue-green/canary CRDs with metric-provider-driven analysis and automated
rollback; Flagger is the Flux-ecosystem equivalent.

**Verdict: table stakes for *one* service, differentiator for the analysis.**

- Deploying a `Rollout` CRD with a manual-promotion canary: **Effort LOW, Learn LOW.** Anyone can do this. It proves nothing.
- A canary gated by an **`AnalysisTemplate` querying Prometheus** for the canary's error rate, which **automatically aborts and rolls back** when you deploy a deliberately broken build: **Effort MED, Learn HIGH.** *This* is the differentiator — the demo is "watch it roll itself back", and it closes the loop between observability and delivery. Do this on `catalog` (stateless, read-heavy, safe).
- **Tool choice: Argo Rollouts.** Coherent with Argo CD; Flagger is the Flux-side equivalent and mixing ecosystems buys nothing.
- Traffic-weighted canary needs ALB target-group weighting via the LB Controller — this works but is the fiddly part. Budget for it.
- **Skip**: canary on the saga services. A mid-saga version skew is a legitimately hard problem (event schema compatibility across versions) and is a rabbit hole, not a phase.

### B5. Chaos Engineering

Verified capabilities: AWS FIS has native `aws:eks:pod-*` actions (delete, cpu/memory/io stress, network
latency/packet-loss/blackhole-port), `aws:eks:terminate-nodegroup-instances`, and critically
`aws:ec2:send-spot-instance-interruptions` which delivers a **real 2-minute Spot interruption notice**.
Chaos Mesh (CNCF incubating) covers pod/network/DNS/HTTP/IO/time/stress/JVM faults as CRDs with
Schedule/Workflow/StatusCheck orchestration.

**Tool recommendation: Chaos Mesh for in-cluster faults + AWS FIS for Spot/node/control-plane faults.**
They are complementary, not competing. Chaos Mesh is free and GitOps-able (CRDs → Argo CD). FIS is
pay-per-action-minute but is the **only** way to get an authentic Spot interruption. LitmusChaos is a
reasonable alternative to Chaos Mesh but is heavier; Chaos Mesh's CRD model fits the GitOps story better.

**Scenarios ranked by learning value for an EKS/Spot environment specifically:**

| # | Scenario | Tool | Effort | Learn | Why it matters here |
|---|----------|------|--------|-------|---------------------|
| 1 | **Real Spot interruption mid-saga** | FIS `send-spot-instance-interruptions` | LOW | **VERY HIGH** | *The* signature scenario. Tests Karpenter's interruption handling, PDBs, `preStop`, grace period, and saga resumption — all at once. Nobody else's demo does this. |
| 2 | **Payment timeout that actually succeeded** | `payment-sim` config | **LOW** | **VERY HIGH** | Best ratio. Forces idempotency keys to be real. No chaos tool needed at all. |
| 3 | **SQS consumer killed between processing and delete** | Chaos Mesh `PodChaos` | LOW | **VERY HIGH** | Redelivery → proves (or destroys) your idempotency claim. |
| 4 | **DNS failure to a dependency** | Chaos Mesh `DNSChaos` | LOW | HIGH | CoreDNS + `ndots:5` + VPC endpoint resolution is a classic EKS pathology. |
| 5 | **Network latency injection on inventory** | Chaos Mesh `NetworkChaos` | LOW | HIGH | Surfaces missing timeouts and absent circuit breakers. Cascading-failure demo. |
| 6 | **OOMKill under memory limit** | Chaos Mesh `StressChaos` | LOW | HIGH | JVM heap vs. container limit is a genuine Spring Boot trap (`MaxRAMPercentage`). |
| 7 | **RDS failover / reboot** | FIS `aws:rds:*` | LOW | HIGH | Connection-pool recovery — HikariCP behaviour under failover is not what people assume. |
| 8 | **Node group termination** | FIS `terminate-nodegroup-instances` | LOW | MED | Overlaps heavily with #1. Do #1 instead. |
| 9 | **AZ evacuation / zonal shift** | FIS | MED | MED | Interesting, but multi-AZ cost pressure on this budget makes it awkward. Defer. |

**Constraint note:** every scenario must be runnable inside one session and leave no billable residue.
Chaos Mesh CRDs are destroyed with the cluster; FIS experiment *templates* are free to keep (you pay only
per action-minute when running), so they can live in Terraform permanently without touching the idle budget.

### B6. Testing Layers

| Layer | Expected? | Effort | Learn | Verdict |
|-------|-----------|--------|-------|---------|
| Unit | Yes | LOW | LOW | Do it, don't obsess. Chase behaviour, not coverage %. |
| **Integration w/ Testcontainers** (Postgres, Redis, LocalStack for SQS/SNS/DynamoDB) | Yes | MED | **HIGH** | **Commonly skipped, shouldn't be.** LocalStack-backed tests for the outbox poller and idempotent consumer are where the patterns are actually validated. Also keeps most iteration off AWS = cost win. |
| **Contract testing** (Pact or Spring Cloud Contract) | Often claimed, rarely real | MED-HIGH | MED | **The most over-claimed layer in microservices repos.** With 6 services and one author, the coupling problem contract testing solves does not exist. *However:* **schema/compatibility testing on the event payloads** is the genuinely valuable subset — one test that fails when an event schema breaks backward compatibility. Do that; skip the full Pact broker. |
| **E2E/smoke against the live cluster** | Yes | LOW | **HIGH** | **Most commonly skipped, absolutely shouldn't be.** Must cover happy path *and* compensated-failure path. This is what makes `make up` trustworthy. |
| Load test (k6) | Differentiator | LOW | HIGH | Needed to *cause* the optimistic-locking conflicts and to feed canary analysis with real traffic. Low effort, high leverage. |
| Chaos-as-test (assert the saga compensates while chaos is running) | Rare | MED | **VERY HIGH** | Chaos Mesh `Workflow` + `StatusCheck` + a k6 run. This is genuinely senior-level and very few repos have it. |

### B7. Cost Engineering — The Underrated Differentiator

Reviewers notice this because almost nobody does it, and it is the direct evidence of operational maturity.

| Capability | Effort | Learn | Notes |
|-----------|--------|-------|-------|
| **Teardown verification / orphan sweep** | LOW | HIGH | See B1 #3. **Highest-ratio item in Part B.** Target the classic orphans: LB-Controller-created ALBs/TGs, leaked ENIs, unattached EBS, EIPs, snapshots, CloudWatch log groups (charged for storage forever), ECR image storage. |
| Cost allocation tags enforced by **Kyverno at admission** + Terraform `default_tags` | LOW | HIGH | Enforcing tags at admission rather than by convention is a nice, cheap flex. |
| AWS Budgets + anomaly detection alert | LOW | MED | Necessary but lagging. Never the only control. |
| **OpenCost → Prometheus → Grafana cost dashboard** | LOW | HIGH | OpenCost exports to Prometheus via `/metrics`, so cost becomes just another dashboard next to RED/USE. Free, CNCF, no license. **Choose OpenCost over Kubecost** — the free Kubecost tier adds a SaaS dependency for no extra learning here. |
| **Documented per-hour cost breakdown in the README** | LOW | MED | A table showing each component's hourly cost and the tradeoff taken (fck-nat vs NAT GW, Spot vs on-demand, self-hosted vs AMP). Costs an hour; reads as extremely senior. |
| **A cost *regression* check in CI** (Infracost on `terraform plan`) | LOW | MED | Fails the PR if monthly estimate crosses the ceiling. Novel, cheap, directly enforces the project's own constraint. Nice differentiator. |
| Scheduled auto-shutdown (EventBridge → scale nodegroup to 0 at a fixed hour) | LOW | MED | Pure insurance against the "left it running overnight" failure that kills these projects. Worth the 30 minutes. |
| ECR lifecycle policies | LOW | LOW | Trivial, but image sprawl is a real slow leak on a daily-rebuild project. |

### B8. Developer Experience

| Capability | Effort | Learn | Verdict |
|-----------|--------|-------|---------|
| **Makefile/Taskfile lifecycle** (`up`, `down`, `deploy`, `test`, `chaos`, `verify-teardown`, `cost`) | LOW | MED | Table stakes. This *is* the project's interface. Taskfile is nicer; Make is universal — either is fine, but be consistent. |
| **`docker compose` local stack + LocalStack** | MED | MED | **The most important cost control in the project.** Every hour of iteration done locally is an hour of EKS not running. Higher ROI than most "features". |
| Pre-commit hooks (`terraform fmt`, `tflint`, `kubeconform`/`kubeval`, `gitleaks`) | LOW | LOW | Table stakes. `gitleaks` matters given the no-secrets-in-Git constraint. |
| **Architecture Decision Records** | LOW | MED | The cheapest credibility signal that exists. The PROJECT.md Key Decisions table is already 80% of this — promote it to `docs/adr/`. |
| **README with an architecture diagram + cost table + "what breaks and why"** | LOW | MED | For a portfolio artifact, this is arguably the single highest-leverage deliverable. |
| Tilt / Skaffold for in-cluster hot reload | MED | LOW | **Skip.** Optimises an inner loop you don't have (you iterate locally, then deploy via GitOps). Would also fight Argo CD's self-heal. |
| devcontainer | LOW | LOW | Nice-to-have, single operator. Skip. |

---

### B9. Differentiators — What Makes This Stand Out

Ranked by (learning value + signal value) ÷ effort. These are the things the other thousand EKS demo
repos do not have.

| # | Differentiator | Effort | Learn | Why it stands out |
|---|---------------|--------|-------|-------------------|
| 1 | **A real saga with outbox + idempotency + compensation** | HIGH | VERY HIGH | Verified: none of Online Boutique, Sock Shop, or Robot Shop has this. It is *the* gap in the reference implementations. |
| 2 | **Runbooks written from actual debugging, including wrong hypotheses** | MED | VERY HIGH | Unfakeable. No LLM and no tutorial produces this. The strongest proof-of-work in the repo. |
| 3 | **Trace propagation across the SNS/SQS async boundary** | MED | VERY HIGH | The thing "distributed tracing" demos almost universally skip. |
| 4 | **Real Spot interruption chaos (FIS) with proven graceful drain mid-saga** | LOW | VERY HIGH | Combines cost engineering with resilience. Extremely rare. |
| 5 | **Teardown verification + documented cost model + Infracost CI gate** | LOW | HIGH | Cost discipline as an engineering artifact. Almost nobody does this; it reads as directly production-relevant. |
| 6 | **Automated canary rollback driven by Prometheus analysis** | MED | HIGH | Closes the observability→delivery loop. Demo-able in 90 seconds. |
| 7 | **Chaos-as-test in CI** (assert compensation completes under injected failure) | MED | VERY HIGH | Turns chaos from a party trick into a gate. |
| 8 | **Kyverno admission policies that actually block** (tags, PSS, registry provenance) | LOW | HIGH | Most repos run Kyverno in `audit`. Running in `enforce` and hitting your own policies is the learning. |
| 9 | **Prometheus exemplars: p99 spike → one click → the exact trace** | LOW | HIGH | Cheap, and reads as genuinely expert. |
| 10 | **`payment-sim` as a first-class, runtime-configurable failure generator** | LOW | VERY HIGH | Best effort-to-learning ratio in the entire project. |

---

## Anti-Features — Deliberately Do Not Build

Opinionated. Each of these is something practice projects routinely burn weeks on.

| Anti-Feature | Surface appeal | Why it's a trap | Do instead |
|--------------|---------------|-----------------|------------|
| **Service mesh (Istio/Linkerd) for mTLS** | "Production-grade!" | Istio control plane alone is ~1GB RAM + sidecar overhead on every pod — on a Spot node budget of $0.30/hr this materially changes your instance sizing. Weeks of yak-shaving that teaches *Istio*, not distributed systems. Already correctly deferred in PROJECT.md. | NetworkPolicies + ALB TLS termination. Revisit in M2 only if the mesh itself is the learning goal. |
| **More services** (10+, auth svc, search, reviews, recommendations) | "Looks like a real microservices estate" | Service count is the most seductive fake-progress metric there is. Each new service is ~4h of Spring Boot boilerplate for ~0 new failure modes. Online Boutique has 11 services and 0 sagas — that is the cautionary tale. | 6 + 1 Lambda, as PROJECT.md already decided. Add *depth* (outbox, idempotency) not *breadth*. |
| **Multi-cluster / multi-region / active-active** | "Enterprise-grade" | Multiplies cost and destroys same-day teardown. Correctly out of scope. | Single cluster. Read about the patterns. |
| **Kafka / MSK (or self-hosted Strimzi as a "cheap" workaround)** | "Real event streaming" | MSK ~$180/mo is out. **The trap is self-hosting Strimzi to dodge the cost** — 3 brokers + ZK/KRaft + persistent volumes on Spot nodes is a daily-teardown nightmare (EBS re-provisioning, broker state, rebalancing) and you'd spend the project operating Kafka. | SNS/SQS/EventBridge, as decided. Teaches fan-out, DLQ, retry, ordering tradeoffs at ~$0. |
| **A polished frontend** | Portfolio vanity | The reviewer for *this* project is looking at Terraform and runbooks. Hours spent on React are hours not spent on the saga. | Minimal React+Vite SPA, S3+CloudFront. Deliberately plain. |
| **Full Pact contract-testing setup with a broker** | "Mature microservices practice" | Solves an inter-team coordination problem that a single author does not have. The broker is another thing to host. | Event-schema backward-compatibility tests. Same protection, ~5% of the effort. |
| **Custom Kubernetes operator / CRD for something** | "Deep K8s expertise" | Enormous effort. Teaches controller-runtime, not operations. | Use others' operators (Karpenter, ESO, Kyverno, Chaos Mesh) and debug *them* — that is the applicable skill. |
| **CDK/Pulumi alongside Terraform "to compare"** | "Breadth" | Doubles the surface, halves the depth. | Terraform only. |
| **Chasing 90% test coverage** | "Rigour" | Coverage percentage on a project whose point is infrastructure is pure busywork. | Test the saga's failure paths exhaustively. Everything else: smoke-level. |
| **Real SES email delivery** | "End-to-end complete" | SES sandbox escape, identity verification, bounce handling. AWS console friction, zero distributed-systems learning. | `notification` Lambda logs + emits a metric. Optionally SNS→email for one address. |
| **Custom domain + ACM + Route 53** | "Professional" | Registrar cost, DNS propagation delays that fight same-day teardown. Correctly out of scope. | ALB DNS name + CloudFront default domain. |
| **Managed Grafana / AMP / heavy CloudWatch use** | "AWS-native" | Breaks the cost ceiling and removes the operational learning. Correctly out of scope. | Self-hosted LGTM-lite (Prometheus/Grafana/Loki/Tempo) with aggressive retention caps. |
| **Multi-AZ RDS, RDS Proxy, Aurora** | "HA" | Multi-AZ doubles RDS cost for a database you destroy daily. | Single-AZ `db.t4g.micro`, or **strongly consider RDS-in-a-container on EKS** if RDS snapshot/restore time proves to be the thing that kills your session ramp-up. (Worth measuring early — see dependency notes.) |
| **"Zero-downtime" everything** | "Production!" | Zero-downtime *stateful migrations* (expand/contract, dual-write) is a multi-week topic on its own. | Do zero-downtime for stateless services (canary). Note schema migrations as a known limitation in the README — honest limitations read better than fake completeness. |
| **Backstage / developer portal** | "Platform engineering" | A portal for one developer. Weeks of setup, pure surface area. | A good README. |
| **Building your own chaos framework** | "Custom = impressive" | It is a `kubectl delete pod` loop with extra steps. | Chaos Mesh + FIS. |

### Where "realistic" crosses into "never finishes"

Three specific lines, each of which has killed projects like this:

1. **Operating stateful infrastructure you didn't need.** Self-hosted Kafka, Elasticsearch, or a
   multi-node Postgres cluster on daily-destroyed Spot nodes. Storage + daily teardown is the single
   most expensive combination of constraints in this project. Managed or nothing.
2. **Breadth over depth.** Every "one more service" decision. The reference implementations prove
   service count ≠ instructiveness: 11 services, 0 sagas.
3. **Building tooling instead of using tooling.** Custom operators, custom chaos frameworks, custom
   dashboards-as-code frameworks. The learning goal is *operating* distributed systems, not building
   platform tools.

A fourth, subtler one: **making it too cheap to be instructive.** If cost optimisation drives you to a
single-node cluster with one replica of everything, you have optimised away the pod eviction, the PDB, the
Spot interruption, and the rolling update — i.e. all of the learning. The floor is: **≥2 nodes, ≥2 replicas
of at least the saga-critical services, in ≥2 AZs.** Budget for that floor and cut elsewhere.

---

## Feature Dependencies

```
Terraform remote state (bootstrap, never destroyed)
    └──requires──> nothing        [MUST BE PHASE 1]
         │
         v
VPC + fck-nat + VPC endpoints
    └──> EKS + Karpenter (Spot)
             ├──> AWS Load Balancer Controller ──> ALB Ingress ──> WAF
             ├──> Argo CD ──┬──> app-of-apps + sync waves
             │              ├──> External Secrets Operator ──requires──> Secrets Manager + IRSA
             │              ├──> Kyverno
             │              ├──> Prometheus/Grafana/Loki/Tempo
             │              ├──> OpenCost ──requires──> Prometheus
             │              ├──> Chaos Mesh
             │              └──> Argo Rollouts
             └──> IRSA / Pod Identity  [gates EVERY service that touches AWS]

Services
  catalog (DynamoDB) ────┐
  cart (Redis) ──────────┤
  payment-sim ───────────┼──> order (Postgres, saga orchestrator)
  inventory (DynamoDB) ──┘        │
                                  ├──requires──> SNS/SQS/EventBridge + DLQs
                                  ├──requires──> Transactional outbox
                                  └──> notification (Lambda)

OTel SDK in every service
    └──> Tempo traces
            └──requires──> trace context propagated through SNS/SQS msg attributes
                    └──> full-saga trace  [THE differentiator]
                            └──enables──> exemplars, log↔trace correlation

Saga + payment-sim failure injection
    └──enables──> chaos scenarios
            └──enables──> runbooks  [highest-value artifact]
            └──enables──> chaos-as-test in CI

Prometheus + k6 load gen
    └──enables──> Argo Rollouts AnalysisTemplate ──> automated canary rollback
    └──enables──> SLO burn-rate alerting

Cost allocation tags (Terraform default_tags + Kyverno enforce)
    └──enables──> teardown verification sweep
    └──enables──> OpenCost per-namespace attribution
    └──enables──> AWS Budgets by tag
```

### Dependency Notes

- **Remote state must precede everything and must never be destroyed.** A separate bootstrap Terraform
  stack. If `make down` can delete the state bucket, the project is one bad command from unrecoverable.
- **IRSA/Pod Identity gates every AWS-touching service.** Build the OIDC provider + role module before the
  first service, or you will retrofit it six times.
- **Argo CD sync waves gate everything else on a fresh cluster.** On a project that provisions from zero
  *every session*, the CRD-before-CR race is not an edge case — it is your default experience. Sync waves
  are load-bearing here in a way they aren't on a long-lived cluster.
- **Outbox must precede idempotent consumers.** Without the outbox, lost events masquerade as consumer
  bugs and you will debug the wrong layer.
- **Trace propagation must precede chaos runbooks.** Debugging a chaos scenario without a full-saga trace
  is masochism, not learning — you'll conclude "distributed systems are hard" rather than learning *why*.
- **Load generation must precede optimistic locking work.** Conflicts don't occur at 1 RPS. Without k6 the
  conditional-write retry path is untested code.
- **Cost tagging must precede teardown verification.** The sweep is tag-driven.
- **Conflict — RDS Postgres vs. same-day teardown:** RDS create/restore is ~10–20 min, eating a
  disproportionate share of a practice session. Mitigations, in order of preference: (a) accept it and use
  the wait productively, (b) snapshot-restore rather than seed-from-scratch, (c) fall back to
  Postgres-in-cluster. **Measure the actual restore time in the first infra phase and decide then** —
  do not pre-commit. This is the single constraint most likely to force an architecture change.
- **Conflict — Argo CD `selfHeal` vs. manual `kubectl` experimentation.** During chaos debugging you will
  `kubectl edit` something and Argo CD will revert it within seconds. Plan for a documented "break-glass"
  procedure (disable auto-sync on a named app). This friction is itself a real GitOps lesson.
- **Conflict — NetworkPolicies vs. everything, during bring-up.** Default-deny will break the observability
  stack, ESO, and Argo CD in confusing ways. Introduce policies *after* the platform is stable, namespace
  by namespace.

---

## MVP Definition

### Launch With (M1 core — the project is not credible without these)

- [ ] **Bootstrap Terraform stack** (S3 + DynamoDB state, separate lifecycle) — everything depends on it
- [ ] **VPC + fck-nat + VPC endpoints** — cost model foundation
- [ ] **EKS + Karpenter on Spot, ≥2 nodes/2 AZs** — the learning floor
- [ ] **`make up` / `make down` + teardown verification sweep** — the constraint that makes practice possible
- [ ] **IRSA/Pod Identity module** — gates every service
- [ ] **Argo CD app-of-apps with sync waves** — GitOps bootstrap; load-bearing on a daily-rebuild cluster
- [ ] **ESO + Secrets Manager** — no secrets in Git
- [ ] **The saga: order + payment-sim + inventory** with **outbox, idempotent consumers, optimistic locking, compensation, DLQs** — *the entire point of the project*
- [ ] **`payment-sim` runtime failure injection** — best effort/learning ratio; enables everything downstream
- [ ] **catalog + cart** — minimum viable shop around the saga
- [ ] **notification Lambda** (log + metric; SES optional) — proves the async fan-out
- [ ] **Minimal React SPA** — deliberately plain
- [ ] **GitHub Actions via OIDC**: build, test, Trivy, ECR push, Terraform plan/apply
- [ ] **Prometheus/Grafana/Loki/Tempo + OTel with async trace propagation** — the full-saga trace
- [ ] **Smoke/E2E covering happy path AND compensated-failure path**
- [ ] **Testcontainers + LocalStack integration tests** for outbox and consumers
- [ ] **≥5 chaos scenarios with runbooks written from real debugging** — incl. the FIS Spot interruption
- [ ] **Cost tags + Budgets alarm + documented cost table in README**

### Add After Core Works (M1.x — once the saga is trustworthy)

- [ ] **Argo Rollouts canary with Prometheus AnalysisTemplate + automated rollback** on `catalog` — trigger: saga stable and metrics trustworthy
- [ ] **SLO + multi-window multi-burn-rate alerting** — trigger: 2+ weeks of real metric history to set a defensible target
- [ ] **NetworkPolicies default-deny, namespace by namespace, with an enforcement test** — trigger: platform stable (doing this early will cost you a day of confusion)
- [ ] **Kyverno in `enforce` mode** (PSS, required tags, registry provenance) — trigger: after workloads are stable
- [ ] **OpenCost dashboard** — trigger: after Prometheus is stable; ~1h of work
- [ ] **WAF on ALB/CloudFront** — trigger: anytime; low effort, low learning
- [ ] **k6 load generation** — trigger: needed *before* optimistic-locking work can be validated; may pull earlier
- [ ] **Prometheus exemplars wiring** — trigger: after tracing works; ~1h, high signal
- [ ] **Chaos-as-test gate in CI** — trigger: after runbooks exist (you need to know what "correct" looks like first)
- [ ] **Infracost cost-regression gate** — trigger: anytime; novel differentiator
- [ ] **ApplicationSet Git-directory generator** — trigger: once the service count and layout have stopped churning
- [ ] **Scheduled auto-shutdown safety net** — trigger: the first time you leave the cluster running overnight

### Defer to M2+

- [ ] Service mesh / mTLS — only if the mesh itself becomes the learning goal
- [ ] Falco, GuardDuty, Security Hub, Cosign/SBOM — valuable, but each is its own project
- [ ] Dedicated auth service, image-processor, OpenSearch search, reviews, recommendations — additive surface
- [ ] Multi-cluster / multi-region — cost and teardown make this incoherent now
- [ ] Zero-downtime schema migration (expand/contract) — a multi-week topic; document as a known limitation instead
- [ ] Full contract-testing with a Pact broker — event-schema compatibility tests cover the real risk

---

## Feature Prioritization Matrix

**Priority key:** P1 = core, project fails without it · P2 = add after core works · P3 = defer/never

### Sorted by learning-value ÷ effort (the most useful ordering for requirements)

| Feature | Learning Value | Effort | Priority |
|---------|---------------|--------|----------|
| `payment-sim` configurable failure injection | VERY HIGH | LOW | **P1** |
| Teardown verification / orphan sweep | HIGH | LOW | **P1** |
| FIS Spot interruption chaos scenario | VERY HIGH | LOW | **P1** |
| Idempotent consumers (+ DLQ redrive) | VERY HIGH | MED | **P1** |
| Transactional outbox | VERY HIGH | MED | **P1** |
| Log ↔ trace correlation via `trace_id` | HIGH | LOW | **P1** |
| Smoke/E2E incl. compensated-failure path | HIGH | LOW | **P1** |
| Runbooks written from real debugging | VERY HIGH | MED | **P1** |
| Trace propagation across SNS/SQS | VERY HIGH | MED | **P1** |
| Optimistic locking + compensation | VERY HIGH | MED | **P1** |
| Karpenter Spot + graceful drain (preStop/PDB/grace) | VERY HIGH | MED | **P1** |
| `make up` / `make down` lifecycle | HIGH | MED | **P1** |
| Terraform remote state surviving teardown | HIGH | MED | **P1** |
| Argo CD app-of-apps + sync waves | HIGH | MED | **P1** |
| IRSA / Pod Identity per service | HIGH | MED | **P1** |
| GitHub Actions OIDC | MED | LOW | **P1** |
| ESO + Secrets Manager | MED | LOW | **P1** |
| Cost tags + Budgets + README cost table | MED | LOW | **P1** |
| Saga orchestration (order state machine) | VERY HIGH | HIGH | **P1** |
| Testcontainers + LocalStack integration tests | HIGH | MED | **P1** |
| RED/USE dashboards | MED | MED | **P1** |
| Local `docker compose` + LocalStack dev stack | MED | MED | **P1** (cost control) |
| Trivy / tfsec / Checkov in CI | LOW | LOW | **P1** (table stakes, low learning) |
| Prometheus exemplars | HIGH | LOW | **P2** |
| k6 load generation | HIGH | LOW | **P2** |
| OpenCost dashboard | HIGH | LOW | **P2** |
| Infracost CI cost gate | MED | LOW | **P2** |
| Kyverno `enforce` (tags, PSS, provenance) | HIGH | LOW | **P2** |
| Scheduled auto-shutdown safety net | MED | LOW | **P2** |
| Chaos Mesh scenarios 3–6 (pod kill, DNS, latency, OOM) | HIGH | LOW | **P2** |
| NetworkPolicies default-deny + enforcement test | HIGH | MED | **P2** |
| Argo Rollouts canary w/ automated analysis rollback | HIGH | MED | **P2** |
| SLO + multi-burn-rate alerting | HIGH | MED | **P2** |
| Chaos-as-test in CI | VERY HIGH | MED | **P2** |
| ApplicationSet Git-directory generator | MED | LOW | **P2** |
| WAF on ALB/CloudFront | LOW | LOW | **P2** |
| ADRs promoted from PROJECT.md decisions | MED | LOW | **P2** |
| Event-schema compatibility tests | MED | MED | **P2** |
| Service mesh / mTLS | MED | HIGH | **P3** |
| Full Pact contract testing + broker | LOW | HIGH | **P3** |
| Additional services (auth, search, reviews, recs) | LOW | HIGH | **P3** |
| Multi-region / multi-cluster | MED | VERY HIGH | **P3** |
| Custom operator / custom chaos framework | LOW | VERY HIGH | **P3 — never** |
| Polished frontend | LOW | MED | **P3 — never** |
| Self-hosted Kafka (Strimzi) | MED | VERY HIGH | **P3 — never** |
| Backstage developer portal | LOW | HIGH | **P3 — never** |
| Real SES delivery | LOW | MED | **P3** |

---

## Competitor Feature Analysis

| Capability | Online Boutique | Sock Shop (deprecated) | Robot Shop | eShop | **This project** |
|-----------|----------------|----------------------|-----------|-------|------------------|
| Checkout flow | Sync gRPC fan-out | Sync + one queue | Sync + one queue | Integration events + process manager | **Async orchestrated saga w/ outbox** |
| Payment | Mock, always succeeds | Mock | Mock | Mock | **Configurable failure/latency/timeout generator** |
| Inventory contention | Absent | Minimal | Minimal | Present | **DynamoDB conditional writes + retry + compensation** |
| Idempotency | None | None | None | Present | **Explicit dedup, proven by DLQ replay** |
| Catalog store | **A JSON file** | MongoDB | MongoDB | Postgres | DynamoDB |
| Tracing across async hop | No queue to cross | No | Vendor agent | Partial | **W3C context via SNS/SQS attributes — full saga** |
| IaC | Kustomize/Helm only | Legacy scripts | Helm | None (Aspire) | **Terraform, whole stack, destroyable** |
| GitOps | No | No | No | No | **Argo CD app-of-apps + sync waves** |
| Chaos | No | No | No | No | **Chaos Mesh + AWS FIS, 5+ scenarios w/ runbooks** |
| Cost engineering | No (assumes Spanner/AlloyDB) | No | No | Local only | **Ceiling, tags, Budgets, OpenCost, teardown verify** |
| Progressive delivery | No | No | No | No | **Argo Rollouts w/ Prometheus-gated auto-rollback** |
| Stated limitations | Implicit | Deprecated | **"error handling is patchy... not any security"** | Implicit | **Explicit `docs/LIMITATIONS.md`** |

**Read of the table:** competing on service count or UI polish is a losing, expensive game. The entire
column of empty cells in rows 1–3 and 7–12 is the opportunity. Depth in the saga, honesty about failure,
and cost discipline are where this project is differentiated — and all three are *cheaper* than breadth.

---

## Sources

- `GoogleCloudPlatform/microservices-demo` README (service table, languages, gRPC, JSON-file catalog, mock payment/shipping/email, synchronous `checkoutservice`) — primary, HIGH
- `microservices-demo/microservices-demo` (Sock Shop) README — explicit `DEPRECATED` marker, Weave Scope tooling — primary, HIGH
- `instana/robot-shop` README — self-declared "error handling is patchy and there is not any security built into the application"; RabbitMQ + polyglot stores — primary, HIGH
- `dotnet/eShop` README — .NET 10 + Aspire, Playwright E2E, local-first, no cloud IaC — primary, HIGH
- AWS Fault Injection Service — Fault injection actions reference (`aws:eks:pod-*`, `aws:eks:terminate-nodegroup-instances`, `aws:ec2:send-spot-instance-interruptions` w/ 2-minute notice, zonal shift) — primary, HIGH
- `chaos-mesh/chaos-mesh` README — CNCF incubating; fault coverage, CRD API, Schedule/Workflow/StatusCheck — primary, HIGH
- Argo CD docs — Declarative Setup; ApplicationSet controller introduction (bundled since v2.3, generators, security implications) — primary, HIGH
- `argoproj/argo-rollouts` README — blue-green/canary CRDs, traffic shaping, metric-provider analysis driving automated promotion/rollback — primary, HIGH
- `fluxcd/flagger` README — canary/A-B/blue-green mirroring, Flux ecosystem — primary, HIGH
- `opencost/opencost` README — CNCF, allocation granularity, cloud billing API integration, Prometheus `/metrics` export — primary, HIGH
- `.planning/PROJECT.md` — constraints, decisions, scope boundaries — primary, HIGH
- Judgement calls (MEDIUM confidence, clearly marked as such above): "what reads as production-grade to a reviewer" (B0), effort/learning ratings, the RDS-vs-teardown mitigation ordering, and the ~$5/mo·$0.30/hr feasibility of each recommendation. These are synthesis, not citation, and should be pressure-tested during phase planning.

---
*Feature research for: cost-constrained AWS EKS e-commerce microservices practice platform*
*Researched: 2026-09-24*
