# Architecture Research

**Domain:** Cost-constrained AWS EKS e-commerce microservices practice platform (saga + event-driven + GitOps + same-day teardown)
**Researched:** 2026-09-24
**Confidence:** HIGH on Terraform/EKS/LBC/Karpenter mechanics (verified against upstream docs); MEDIUM on AWS unit pricing (not re-verified against the pricing API — figures are long-stable list prices, marked inline); HIGH on saga/outbox/idempotency patterns (well-established, reasoned from first principles against this stack).

> **The one-sentence thesis of this document:** every architectural decision in this project is downstream of one constraint — *it must die cleanly every night* — and the single decision that determines whether that works is **where the Terraform/Kubernetes boundary sits**. Get that wrong and the practice loop dies in week two.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│  L0  BOOTSTRAP — IMMORTAL (never destroyed, ~$2-3/mo)                     │
├──────────────────────────────────────────────────────────────────────────┤
│  ┌──────────┐ ┌──────┐ ┌────────────┐ ┌─────────┐ ┌──────────┐ ┌───────┐ │
│  │ S3 tfstate│ │ ECR  │ │ GH OIDC +  │ │ Secrets │ │ S3 obs.  │ │Budgets│ │
│  │ +lockfile │ │repos │ │ CI IAM role│ │ Manager │ │ bucket   │ │ +tags │ │
│  └──────────┘ └──────┘ └────────────┘ └─────────┘ └──────────┘ └───────┘ │
│  ┌──────────────────────────┐  (S3 SPA bucket + CloudFront live here too: │
│  │ S3 frontend + CloudFront │   ~free at idle, slow to propagate)         │
│  └──────────────────────────┘                                             │
└──────────────────────────────────────────────────────────────────────────┘
        ▲ terraform_remote_state (read-only) ─────────────────────────┐
        │                                                             │
┌───────┴──────────────────────────────────────────────────────────────────┐
│  L1  INFRA — EPHEMERAL (VPC + cluster in ONE state; see rationale)        │
├──────────────────────────────────────────────────────────────────────────┤
│  VPC 10.42.0.0/16, 2 AZ                                                   │
│  ┌── public /24 ×2 ──────────────┐   ┌── private /20 ×2 ───────────────┐  │
│  │  ALB (LBC-managed, NOT in TF) │   │  EKS nodes: 1× on-demand t4g.   │  │
│  │  fck-nat t4g.nano (ASG=1)     │◄──┤  medium (system) + Karpenter    │  │
│  └───────────────────────────────┘   │  Spot NodePool                  │  │
│  ┌── intra /24 ×2 (no default route)─┴─────────────────────────────────┐  │
│  │  RDS subnet group · ElastiCache subnet group                        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│  Gateway endpoints: S3, DynamoDB ($0).  Interface endpoints: NONE.        │
│  EKS control plane · aws_eks_addon (CNI, CoreDNS, kube-proxy, EBS CSI,    │
│  Pod Identity Agent) · all IAM roles + Pod Identity associations ·        │
│  Karpenter IAM + interruption SQS queue (AWS side only)                   │
└──────────────────────────────────────────────────────────────────────────┘
        ▲                                                             ▲
┌───────┴────────────────────────────┐  ┌─────────────────────────────┴────┐
│ L2  DATA — EPHEMERAL               │  │ L3  GITOPS-SEED — EPHEMERAL      │
├────────────────────────────────────┤  ├──────────────────────────────────┤
│ RDS pg db.t4g.micro (single-AZ)    │  │ helm_release "argo-cd"  ◄─ the   │
│ DynamoDB (catalog, inventory,      │  │ kubernetes_manifest "app-of-apps" │
│   processed_events) PAY_PER_REQUEST│  │                                   │
│ ElastiCache Redis t4g.micro        │  │ THE ONLY TF THAT TOUCHES K8S API  │
│ EventBridge bus + rules            │  └───────────────────────────────────┘
│ SQS queues + DLQs · SNS topic      │                  │ syncs
│ Cognito user pool                  │                  ▼
└────────────────────────────────────┘  ┌──────────────────────────────────┐
                                        │  ARGO CD — owns everything in    │
                                        │  the Kubernetes API              │
                                        ├──────────────────────────────────┤
                                        │ platform/  LBC · ESO · Kyverno · │
                                        │   metrics-server · Karpenter     │
                                        │   chart + NodePool/EC2NodeClass  │
                                        │ observability/  kube-prom-stack ·│
                                        │   Loki(S3) · Tempo(S3) · Grafana │
                                        │   · OTel Collector · Alloy       │
                                        │ ecommerce/  api-gateway · catalog│
                                        │   · cart · order · payment-sim · │
                                        │   inventory                      │
                                        └──────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility (what it *owns*) | Implementation |
|-----------|--------------------------------|----------------|
| L0 bootstrap | Identity, artifacts, state, cost guardrails. Everything whose loss would make a rebuild slow or expensive. | Terraform, own state, applied manually |
| L1 infra | Every AWS networking + cluster-control-plane resource | Terraform, `terraform-aws-modules/vpc` v6.x, `terraform-aws-modules/eks` v21.x |
| L2 data | Every AWS *stateful/messaging* resource. Depends on L1 only for RDS/Redis subnets+SGs | Terraform, remote-state read of L1 |
| L3 gitops-seed | Argo CD and nothing else. Resolves the bootstrap paradox. | Terraform `helm` provider, 2 resources total |
| Argo CD | Every Kubernetes API object in the cluster | app-of-apps → per-domain `ApplicationSet` |
| `api-gateway` | North–south edge: JWT validation (Cognito), routing, rate limit, `Idempotency-Key` enforcement | Spring Cloud Gateway |
| `order` | **Saga orchestrator.** Owns order aggregate, saga state machine, transactional outbox | Spring Boot + RDS Postgres + Flyway |
| `inventory` | Stock levels + reservations. Owns the conditional-decrement invariant | Spring Boot + DynamoDB |
| `payment-sim` | Authorize / Capture / Void with injectable failure | Spring Boot, in-memory |
| `catalog` | Read-heavy product reads | Spring Boot + DynamoDB, HPA |
| `cart` | Ephemeral pre-checkout state | Spring Boot + ElastiCache Redis, TTL |
| `notification` | Choreographed side-consumer — proves loose coupling | Python Lambda ← EventBridge rule |
| fck-nat | Egress for private subnets. **Single point of failure by design** (cost) | t4g.nano in ASG(1), `RaJiska/fck-nat` v1.6.1 |

---

## Decision 1 — The Terraform ⇄ Kubernetes boundary (the consequential one)

### The rule

> **Terraform owns resources in the AWS API. Argo CD owns resources in the Kubernetes API. The sole exception is Argo CD itself.**

### Why — three independent arguments

**(a) The `kubernetes`/`helm` providers fail at *plan* time, not apply time.**
Those providers must reach a live kube-apiserver to produce a plan. Two consequences that specifically destroy a teardown-heavy stack:

- On a first `apply`, the cluster endpoint/CA are unknown values → `Provider configuration ... cannot be unknown` or a silent plan against the *wrong* cluster. The standard workaround (two-phase apply, `-target`) is exactly the kind of manual step the project forbids.
- On `destroy`, the cluster may already be gone or unreachable → the provider cannot authenticate → destroy of a `helm_release` hangs or errors → the state file is wedged with a resource Terraform can neither read nor delete. You recover with `terraform state rm`, i.e. by hand, at 11pm.

Confining these providers to **L3, containing exactly two resources, destroyed first**, bounds the worst case to `terraform state rm` on one resource.

**(b) Terraform's dependency graph cannot see through a controller.**
This is the root cause of every "cannot destroy VPC" story in this domain. Terraform destroys a `helm_release` for the AWS Load Balancer Controller in milliseconds; the ALBs that controller created are *not in Terraform's state* and are not deleted. Thirty seconds later `aws_subnet` destroy fails with `DependencyViolation`. Terraform did nothing wrong — it has no edge from `aws_subnet` to "an ALB a controller made".

Verified upstream behaviour that gives us the fix: *"If an IngressGroup no longer contains any Ingresses, the ALB for that IngressGroup will be deleted and any deletion protection of that ALB will be ignored."* (aws-load-balancer-controller docs, v3.5.0). So deleting the **Kubernetes Ingress objects** is what reliably deletes the ALB — a cluster operation, not a Terraform operation. That belongs in a drain script, and a drain script only makes sense if Argo CD, not Terraform, owns those objects.

**(c) GitOps is a stated requirement.** Running platform add-ons through Argo CD *is* the practice being sought. Managing them with `helm_release` would be push-based delivery wearing a GitOps t-shirt.

### The exception list — things that LOOK like Kubernetes but stay in Terraform

| Resource | Why it stays in Terraform |
|---|---|
| `aws_eks_addon` (VPC CNI, CoreDNS, kube-proxy, EBS CSI, **Pod Identity Agent**) | These are AWS API resources, not Helm. VPC CNI must exist *before* nodes join — Argo CD isn't running yet. EKS module v21 sets `addons.most_recent = true` and `resolve_conflicts_on_create = "NONE"` by default. |
| Karpenter's **AWS side**: controller IAM role, node IAM role + instance profile, interruption SQS queue, Pod Identity association | Pure IAM/SQS. EKS module v21's `karpenter` submodule now defaults `create_pod_identity_association = true` and has **removed native IRSA support** for Karpenter. The Helm chart and the `NodePool`/`EC2NodeClass` CRs go to Argo CD. |
| All IRSA / Pod Identity roles for workloads | IAM. The ServiceAccount annotation/association is the seam. |
| EKS access entries | v21 removed the `aws-auth` submodule entirely; access entries are an AWS API resource, so the `kubernetes` provider is no longer needed for cluster auth at all. **This is why v21 requires only the `aws`, `time`, and `tls` providers — no `kubernetes` provider in its requirements block.** |

### Verified fact worth noting

`terraform-aws-modules/eks` **v21.26.0** requirements: `terraform >= 1.5.7`, `aws >= 6.59`, `time >= 0.9`, `tls >= 4.0`. **No `kubernetes` provider.** The module authors removed the need; don't reintroduce it. *(Confidence: HIGH — read from module README + UPGRADE-21.0.md.)*

---

## Decision 2 — Terraform layering: 4 layers, not 5

### Recommended layout

| # | Dir | State key | Lifetime | Contents |
|---|-----|-----------|----------|----------|
| L0 | `layers/00-bootstrap` | `bootstrap/terraform.tfstate` | **Immortal** | S3 state bucket, ECR, GH OIDC + CI role, Secrets Manager, observability S3 bucket, SPA S3 + CloudFront, Budgets, cost tags |
| L1 | `layers/10-infra` | `infra/terraform.tfstate` | Per session | VPC, subnets, RTs, fck-nat, gateway endpoints, SGs, EKS control plane, system node group, EKS addons, all IAM/Pod-Identity, Karpenter AWS side |
| L2 | `layers/20-data` | `data/terraform.tfstate` | Per session | RDS, DynamoDB, ElastiCache, EventBridge bus + rules, SQS + DLQs, SNS, Cognito |
| L3 | `layers/30-gitops` | `gitops/terraform.tfstate` | Per session | `helm_release.argocd` + root `Application`. Nothing else. |

### Why merge network and cluster (rejecting the canonical 5-way split)

The common `bootstrap → network → cluster → addons → app-infra` split puts a seam between network and cluster. **That seam buys nothing here and costs plenty:**

- VPC and EKS have *identical* lifetimes — both die every night. A seam is only useful where lifetimes differ.
- The destroy of the cluster is precisely what releases the VPC's ENIs. Splitting them means the network layer's destroy is *blocked* on the cluster layer's destroy having fully completed — you've encoded an ordering dependency that Terraform can no longer enforce for you, and you must enforce it in `make down` by hand anyway.
- It adds a `terraform_remote_state` read for subnet IDs, a second lock/plan/refresh cycle (~40–60 s of wall clock per `up` and per `down`), and a second place for drift.

Conversely, **do** split L2 data from L1 infra, because their lifetimes genuinely can diverge (see Decision 5 — you may want to iterate on services without recreating the VPC, and DynamoDB/SQS/SNS/Cognito have no VPC dependency at all).

**Layer count is bounded by teardown choreography, not by tidiness.** Every layer is another `terraform destroy` you must sequence correctly at 11pm.

### Remote state

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-<acct>-<region>"
    key          = "infra/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true    # native S3 locking
  }
}
```

**Drop DynamoDB state locking.** *(Confidence: HIGH — read from hashicorp/web-unified-docs `language/backend/s3.mdx`, v1.13.x–v1.16.x.)* The official S3 backend docs now state locking is enabled with `use_lockfile = true` (writes a `<key>.tflock` object), and mark **`dynamodb_table` and `dynamodb_endpoint` as Deprecated**. The lock file needs `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` on `<key>.tflock`.

> ⚠️ **This contradicts PROJECT.md**, which specifies "remote state in S3 + DynamoDB state locking". Recommend amending that requirement to "S3 remote state with native `use_lockfile` locking". Keeping the DynamoDB table would mean adopting a deprecated mechanism plus one more immortal resource. Enable **S3 bucket versioning** (docs strongly recommend it) — that is your state-recovery mechanism.

Verified current versions to pin against: Terraform **1.16.4**; `hashicorp/aws` **6.66.0**; `terraform-aws-modules/vpc` **6.7.3**; `terraform-aws-modules/eks` **21.26.0**; `RaJiska/fck-nat` **1.6.1**.

---

## Decision 3 — Teardown choreography (the `make down` contract)

This is the crown jewel of the whole project. **Three of the seven steps are not Terraform**, and that is the entire point.

```
make down:
  0. argocd app set root --sync-policy none        # stop self-heal recreating what you delete
  1. ./scripts/drain-ingress.sh                    # k8s: delete Ingress + type=LoadBalancer Services,
                                                   #      POLL aws elbv2 until none remain in the VPC
  2. ./scripts/drain-nodes.sh                      # k8s: delete nodepools.karpenter.sh --all,
                                                   #      POLL until no EC2 tagged karpenter.sh/nodepool
  3. ./scripts/drain-pvcs.sh                       # k8s: delete PVCs, POLL until EBS volumes gone
  4. terraform -chdir=layers/30-gitops destroy
  5. terraform -chdir=layers/20-data    destroy    # RDS is the long pole: 5-10 min
  6. terraform -chdir=layers/10-infra   destroy
  7. ./sh/verify-teardown.sh                  # orphan + cost-leak sweep
```

### Orphan classes — the complete list

| Orphan | Created by | Not in TF state because | Blocks | Handled by |
|---|---|---|---|---|
| ALB + TargetGroups | AWS Load Balancer Controller | Controller-created from an Ingress | `aws_subnet` / `aws_security_group` destroy → `DependencyViolation` | Step 1 |
| `k8s-traffic-*` / `k8s-<group>-*` SGs | LBC | Controller-created | `aws_vpc` destroy | Step 1, swept in 7 |
| EC2 instances | Karpenter | Karpenter creates instances via the EC2 API; Terraform never knew | Nothing directly — but they hold ENIs *and* cost money | Step 2 |
| ENIs `aws-K8S-*` | VPC CNI | Attached to nodes | Subnet + SG destroy | Resolved by step 2 + control-plane delete |
| EBS volumes | EBS CSI driver | Dynamically provisioned from PVCs | Nothing — **pure silent cost leak** | Step 3 |
| CloudWatch log groups | EKS/Lambda/controllers | Auto-created on first write | Nothing — silent cost leak with default ∞ retention | Set `retention_in_days = 1` on every explicit group; sweep in 7 |
| RDS automated backups + manual snapshots | RDS | Survive instance deletion | Nothing — silent cost leak | `skip_final_snapshot = true`; sweep in 7 |

**Polling, not fire-and-forget.** `kubectl delete ingress` returns before the ALB is gone. Every drain step must poll to an actual AWS-API-confirmed terminal state with a timeout. A drain script that doesn't poll is a `make down` that fails 1 night in 4, which is exactly how the practice loop dies.

**`verify-teardown.sh` must check, scoped by the project cost-allocation tag:** running EC2 · ELBv2 · unattached EBS · unattached EIP · NAT gateways · RDS instances + snapshots + automated backups · ElastiCache · EKS clusters · non-empty VPCs · log groups with retention ≠ 1 · orphaned ENIs. Exit non-zero on any hit.

> **Build this script in Phase 0, before there is anything to tear down.** Writing the verifier first is the forcing function that makes the constraint real rather than aspirational.

### Terraform-side hygiene that makes destroy fast and safe

- `skip_final_snapshot = true`, `deletion_protection = false` on RDS (with a `var.preserve_snapshot` escape hatch — see Decision 5).
- **Do not** put `prevent_destroy` lifecycle blocks anywhere in L1–L3.
- Avoid `create_before_destroy` on anything with a name collision (SGs, IAM roles) — it doubles resources transiently on an already-tight account limit.
- Set short `timeouts { delete = "20m" }` on `aws_eks_cluster` and RDS so a hang surfaces as an error rather than a 60-minute stall.

---

## Decision 4 — Network architecture

### AZ count: **2**

| | 2 AZ | 3 AZ |
|---|---|---|
| Interface endpoint cost | ×2 per endpoint | ×3 per endpoint (~$7.30/mo each ea.) |
| Cross-AZ NAT hairpin | 1 AZ crosses | 2 AZs cross |
| RDS single-AZ | 2 AZs of which 1 unused | 3 AZs of which 2 unused |
| Spot capacity risk | Moderate | Lower |

Spot capacity crunch in one of two AZs is the only real argument for 3, and it is mitigated by instance-type diversification in the Karpenter `NodePool`. For a single-tenant practice platform, a 20-minute Spot squeeze is a *learning event*, not an incident.

**Recommend 2 AZs, with the third AZ's CIDR ranges reserved-but-unallocated** so adding AZ-c later is purely additive and non-destructive.

### CIDR plan — `10.42.0.0/16`

| Purpose | AZ-a | AZ-b | (reserved AZ-c) | Route table default route |
|---|---|---|---|---|
| Public | `10.42.0.0/24` | `10.42.1.0/24` | `10.42.2.0/24` | IGW |
| Private (nodes/pods) | `10.42.16.0/20` | `10.42.32.0/20` | `10.42.48.0/20` | fck-nat ENI |
| Intra (RDS/Redis) | `10.42.64.0/24` | `10.42.65.0/24` | `10.42.66.0/24` | **none** |

**Private subnets must be /20, not /24.** The VPC CNI in default (secondary-IP) mode pre-allocates a full ENI's worth of secondary IPs per node and holds a warm pool. On a /24 you will hit `failed to assign an IP address to container` as `Pending` pods with a misleading error — a classic, hard-to-diagnose failure. /20 gives ~4090 usable and removes the class of bug entirely for free.

**Intra subnets with no default route** for RDS/ElastiCache: cheaper (zero NAT data transfer), better practice, and removes an egress path you'd otherwise have to reason about in NetworkPolicy/SG review.

Required subnet tags: public → `kubernetes.io/role/elb = 1`; private → `kubernetes.io/role/internal-elb = 1` **and** `karpenter.sh/discovery = <cluster-name>`. Tag security groups with `karpenter.sh/discovery` too (the `EC2NodeClass` selects by it).

### fck-nat placement

- **One** instance, `t4g.nano`, in **one** public subnet (AZ-a), managed as an **ASG of size 1** so an instance or Spot loss self-heals.
- **Both** private route tables get `0.0.0.0/0 → <fck-nat ENI>`. The target must be the **ENI**, not the instance id (ENI survives instance replacement; the ASG re-attaches it). `source_dest_check = false` is mandatory.
- Use `RaJiska/fck-nat` v1.6.1 with `update_route_table_ids` — let the module own the routes. If you also declare those routes in your own `aws_route` resources you get a permanent diff and a teardown race.
- AZ-b private traffic hairpins to AZ-a. Cross-AZ transfer is ~$0.01/GB each way *(MEDIUM confidence — list price)*; at practice volumes (<10 GB/session) that is cents. A second fck-nat costs more than the hairpin.
- **Accepted failure mode / chaos scenario:** fck-nat dies → all egress dies → ECR API auth fails → cluster-wide `ImagePullBackOff` with a confusing error. This is an excellent scripted chaos scenario; write its runbook.

### VPC endpoints — the cost math, and the uncomfortable answer

An interface endpoint costs ~**$0.01/hr per ENI per AZ** *(MEDIUM confidence — long-stable list price)*. At 2 AZs that is **~$0.02/hr ≈ $14.60/mo per endpoint**.

- The **idle** budget is $5/mo total. The **active** budget is $0.30/hr total.
- One interface endpoint at 2 AZs is **$0.02/hr — 6.7% of the entire hourly budget, for one endpoint.** Five endpoints (ECR API, ECR DKR, STS, Secrets Manager, SQS) would be **$0.10/hr = 33% of budget**, more than all the compute combined, to save a rounding error of fck-nat data transfer.

**Recommendation for M1:**

| Endpoint | Type | Cost | Verdict |
|---|---|---|---|
| **S3** | Gateway | **$0** | **Mandatory.** ECR image *layers* are served from S3 — this is far and away the largest NAT data-transfer item, and removing it is free. |
| **DynamoDB** | Gateway | **$0** | **Mandatory.** Catalog + inventory are hot paths. Free. |
| ECR API / ECR DKR / STS / Secrets Manager / SQS / EventBridge / SNS | Interface | $14.60/mo ea. | **No.** These carry tiny control-plane-sized payloads (auth tokens, JSON API calls). fck-nat handles them for pennies. |

Gate the interface endpoints behind `variable "enable_interface_endpoints" { default = false }`. Flipping it on for one deliberate session and reading the Cost Explorer delta *is* the lesson; leaving it on is how the budget dies.

> **Correction to a common assumption:** people adopt interface endpoints "to save NAT costs". With a managed NAT Gateway ($0.045/hr + $0.045/GB) that arithmetic sometimes works. With a **$0.0042/hr fck-nat** it never does. Endpoints here are a *security/latency* choice, not a cost choice — and this project doesn't need that security posture.

### Ingress: shared ALB via IngressGroup — **validated, with a caveat**

*(Confidence: HIGH — read from aws-load-balancer-controller v3.5.0 `docs/guide/ingress/annotations.md`.)*

`alb.ingress.kubernetes.io/group.name` merges rules from multiple Ingresses onto **one** ALB; `group.order` sets rule priority. Confirmed. One ALB ≈ $0.0225/hr + LCUs; six per-service ALBs would be 6×.

**Honest nuance:** with Spring Cloud Gateway doing in-cluster routing, the app side needs exactly *one* Ingress (`/api/*` → api-gateway). IngressGroup would be redundant if the app were the only tenant. It is not — **use the group to co-host the platform UIs on the same ALB:**

| Ingress | `group.order` | Path | Backend |
|---|---|---|---|
| `api-gateway` | 10 | `/api/*` | api-gateway svc |
| `grafana` | 20 | `/grafana/*` | grafana svc (Cognito-authed) |
| `argocd` | 30 | `/argocd/*` | argocd-server (Cognito-authed) |

That saves two ALBs (~$0.045/hr, 15% of the hourly budget) and practises the pattern properly.

**The IngressGroup trap you must design around (from the docs):** annotations have **Exclusive** vs **Merge** merge-semantics. Exclusive annotations (scheme, subnets, security-groups, certificate-arn, load-balancer-attributes, wafv2-acl-arn) must be identical across *all* members, and *"the controller will fail with an error for the entire IngressGroup until the conflict is resolved — no updates will be applied to any member."* One careless annotation on the Grafana Ingress silently freezes reconciliation for your API.

**Mitigation:** designate one **anchor Ingress** that carries every Exclusive annotation, or better, push them into an `IngressClassParams` resource and let member Ingresses carry only Merge-semantics annotations (healthcheck, target-type, actions). Add a Kyverno policy that rejects Exclusive annotations on non-anchor Ingresses in the group — that turns an invisible outage into an admission error, and is a great use of Kyverno.

Security note from the docs: explicit IngressGroups are only safe when everyone with RBAC to create Ingresses is inside the trust boundary. Single-operator cluster — fine.

WAF attaches via `alb.ingress.kubernetes.io/wafv2-acl-arn` on the anchor Ingress. AWS WAF is ~$5/mo/WebACL + $1/rule/mo, prorated hourly *(MEDIUM confidence)* → ~$0.008/hr. Acceptable.

---

## Decision 5 — The saga

### Orchestration, firmly. Here is the *learning-value* argument.

Correctness-wise both work. For this project's stated goal — operational scar tissue — orchestration wins decisively:

1. **Choreography's failure modes are emergent and invisible.** When a choreographed saga wedges, there is no artefact that represents "the saga". You reconstruct it by reading five services' logs and inferring. Orchestration puts the state machine in a table you can query: `SELECT * FROM saga_instance WHERE state = 'COMPENSATING'`. For someone deliberately building debugging skill, a saga you can *see* is worth an order of magnitude more than one you must infer.
2. **Compensation is the actual learning objective**, and in choreography it is scattered across services, each of which must know who to notify on failure. In orchestration each step has an explicit `compensate()` sibling — the concept becomes a code structure rather than a vibe.
3. **Timeouts need an owner.** A choreographed saga has nowhere to put "step 2 never replied". An orchestrator has an obvious home for a timeout sweeper — and lost replies are the failure you will inject most often.
4. **It gives distributed tracing something to hang on.** One root span per saga, with the orchestrator as the parent. Choreography produces a forest, not a tree.

**Acknowledged cost:** the orchestrator couples to every participant and is a semi-central point of failure. Rather than argue it away, **build both**: `notification` (Python Lambda) is a *choreographed* consumer — it reacts to `OrderConfirmed` off EventBridge and the orchestrator does not know it exists. Adding a second choreographed consumer later requires zero changes to `order`. One system, both styles, contrast made concrete.

### Step definition

```
T1  ReserveInventory        C1  ReleaseInventory        (always succeeds, retriable)
T2  AuthorizePayment        C2  VoidAuthorization       (free, no money moved)
T3  CapturePayment          ── PIVOT ──                 (no compensation after this)
T4  ConfirmOrder            (retriable-forward only)
T5  emit OrderConfirmed     (retriable-forward only)
```

Two deliberate design choices:

- **Reserve inventory before touching payment.** Releasing a reservation is a local, free, always-succeeding operation. Refunding money is a real financial movement with its own failure modes. Reserve-then-charge minimises the window in which you have taken money for something you cannot ship.
- **Split Authorize from Capture.** This is how real PSPs work, and it makes C2 a *void* (free, near-infallible) rather than a *refund*. It also creates a clean **pivot transaction** at T3 — the point after which the saga can only roll *forward*. Understanding where the pivot is, is the single most important concept in saga design and most tutorials omit it.

Configure `payment-sim` to occasionally fail the **void** as well, so you are forced to build the case no tutorial builds: **compensation itself failed** → `state = COMPENSATION_FAILED` → alert → manual intervention queue. Real systems have this. Build it.

### Saga state, in Postgres

```sql
CREATE TABLE saga_instance (
  saga_id       uuid PRIMARY KEY,
  order_id      uuid NOT NULL REFERENCES orders(id),
  state         text NOT NULL,          -- STARTED|AWAITING_STEP|COMPENSATING|COMPLETED|FAILED|COMPENSATION_FAILED
  current_step  smallint NOT NULL,
  payload       jsonb NOT NULL,         -- snapshot of cart at saga start (see consistency traps)
  step_deadline timestamptz NOT NULL,   -- drives the timeout sweeper
  version       integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON saga_instance (state, step_deadline);   -- the sweeper's index

CREATE TABLE saga_step_log (                            -- audit trail AND debugging surface
  saga_id uuid, step_no smallint, name text,
  direction text,   -- FORWARD | COMPENSATE
  status    text,   -- PENDING | OK | FAILED
  attempt   smallint, correlation_id uuid, detail jsonb,
  ts timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (saga_id, step_no, direction, attempt)
);
```

`saga_step_log` is the thing you will actually stare at during every chaos exercise. Treat it as a first-class deliverable, not logging.

### Transactional outbox: **polling publisher**, not Debezium

| | Polling publisher | Debezium CDC |
|---|---|---|
| Infra | Zero — a `@Scheduled` method | Kafka Connect / Debezium Server pod, ~512 Mi–1 Gi |
| RDS config | None | `wal_level = logical` → custom parameter group → **instance reboot** on every `make up` |
| Hidden hazard | Outbox table growth | A replication slot that, if not dropped cleanly, pins WAL and fills the disk |
| Fit for ~10 events/min on db.t4g.micro | Perfect | Absurd |
| Learning value | Teaches the *pattern* | Teaches Debezium ops |

**Recommend the polling publisher.** Adding minutes and a reboot to every single `make up` to move ten events per minute is a direct violation of the project's core constraint.

```java
@Scheduled(fixedDelay = 500)
@Transactional
public void publishBatch() {
  // FOR UPDATE SKIP LOCKED is the whole trick: N replicas of `order` can run this
  // concurrently with zero coordination and zero leader election.
  var rows = jdbc.query("""
      SELECT id, event_id, event_type, aggregate_id, payload
      FROM outbox WHERE published_at IS NULL
      ORDER BY id LIMIT 100
      FOR UPDATE SKIP LOCKED""", MAPPER);
  if (rows.isEmpty()) return;
  eventBridge.putEvents(toPutEventsRequest(rows));            // batched, max 10 per call
  jdbc.update("UPDATE outbox SET published_at = now() WHERE id = ANY(?)", ids(rows));
}
```

**Three things people get wrong about the outbox — state them in the runbook:**

1. **The outbox guarantees *no lost* events. It does not guarantee *no duplicate* events.** `putEvents` can succeed and the `UPDATE` can fail (pod killed, Spot reclaim) → the row is re-read and republished. Delivery is **at-least-once, always**. Idempotent consumers are therefore mandatory, not a nice-to-have.
2. **Ordering is not preserved end-to-end.** `ORDER BY id` gives per-publisher ordering into EventBridge; EventBridge and standard SQS give none downstream. Design consumers to be order-independent, or carry a monotonic `sequence` per aggregate and drop stale.
3. **The outbox table grows without bound.** Needs `DELETE FROM outbox WHERE published_at < now() - interval '1 hour'`. On a nightly-destroyed database **you would never notice this** — which is itself a lesson about what daily teardown *hides* from you. Write the cleanup job anyway and note why.

### Idempotency: three layers, three mechanisms

**Layer 1 — API edge (without this, nothing downstream helps).** `POST /api/orders` requires an `Idempotency-Key` header, enforced at the gateway, persisted as a unique index on `orders(idempotency_key)`. A client retry that creates two orders cannot be fixed by any amount of consumer-side dedupe.

**Layer 2 — the key itself.** The idempotency key is the **`event_id`**: a UUID generated in the *same transaction* as the business write and stored in the outbox row. It travels as an EventBridge `detail.eventId` / SQS message attribute.

> **Do NOT use the SQS `MessageId`.** It differs per subscription and is regenerated by a DLQ redrive — dedupe keyed on it silently fails exactly when you need it.

**Layer 3 — consumer-side, per data store:**

| Consumer | Store | Mechanism |
|---|---|---|
| `order` (replies) | Postgres | `INSERT INTO processed_events(event_id, consumer) VALUES (?, ?) ON CONFLICT DO NOTHING` **inside the same transaction as the business effect**. 0 rows affected → already processed → ack and return. This is the only *provably* correct form: dedupe and effect commit atomically. |
| `inventory` | DynamoDB | **No separate dedupe table needed.** The reservation item *is* the dedupe record: `PK=SKU#<sku>`, `SK=RSV#<event_id>`, written with `ConditionExpression: attribute_not_exists(SK)`. One round trip, atomic, self-cleaning via TTL. Prefer this — it's the elegant answer. |
| `notification` (Lambda) | DynamoDB `processed_events` + TTL 24 h | Dedupe-then-act, with a small non-atomic window. Acceptable: a duplicate email is harmless, and Lambda has no transaction to enlist in. Be explicit that this is a *deliberate* weakening, not an oversight. |

### Compensating transactions — concretely

**`ReleaseInventory` — the silent-bug trap.** The naive implementation is `available += qty`. A retried release then **double-credits stock**, and because releases only happen on failure paths you will not notice until an inventory audit. Correct form — flip the reservation's status *and* credit stock in one conditional operation:

```
UpdateItem  PK=SKU#123, SK=RSV#<event_id>
  UpdateExpression:    SET #s = :RELEASED
  ConditionExpression: #s = :RESERVED         ← makes the retry a no-op
```
with the stock credit in the same `TransactWriteItems`, or (better) with available stock *derived* as `on_hand - Σ(active reservations)` so there is no second number to keep in sync.

**`VoidAuthorization`.** Free, no money movement, safe to retry forever. If `payment-sim` is configured to fail it, the saga transitions to `COMPENSATION_FAILED` and pages. There is no compensation for a compensation.

**Universal rules for compensations:**
- Must be **idempotent** (they will be retried).
- Must be **retriable indefinitely** — there is no further fallback.
- Must be **commutative with in-flight forward steps** where possible, or guarded by a semantic lock (the `RESERVED` status *is* the semantic lock above).

**The timeout sweeper — do not skip this.**
```java
@Scheduled(fixedDelay = 5000)
void sweep() {
  // states AWAITING_* with step_deadline < now()  →  begin compensation
}
```
Without it, one lost reply wedges a saga forever. You will lose replies on purpose. This is the component that turns "it hung" into "it compensated and told me".

### Messaging topology — concrete

**Recommendation: EventBridge custom bus is the domain-event backbone; SQS is the delivery mechanism to every Spring consumer; SNS is retained on exactly one path so both fan-out models get practised.**

Why EventBridge over SNS as the primary bus: the outbox makes exactly one integration call (`PutEvents`, batched 10), and *all* routing lives in Terraform rules rather than in service config. Adding a consumer becomes a Terraform change with zero service changes — which is the property you actually want to feel. EventBridge also retries targets for up to 24 h with native exponential backoff, and supports a per-target DLQ.

```
                    ┌──────────────────────────────────────────────┐
  order (outbox) ──▶│  EventBridge bus: "ecommerce"                 │
      PutEvents     │  source=ecommerce.order                       │
                    └──┬──────────────┬────────────────┬────────────┘
                       │ rule         │ rule           │ rule
     detail-type=      │ OrderPlaced  │ OrderConfirmed │ InventoryLowStock
                       ▼              ▼                ▼
              ┌────────────────┐  ┌──────────┐   ┌──────────────┐
              │ q-inventory-   │  │ λ notif- │   │ SNS topic    │──▶ email (SES)
              │   commands     │  │ ication  │   │ low-stock    │──▶ q-analytics
              │  ↳ DLQ (mrc 3) │  │ ↳ onFail │   └──────────────┘
              └───────┬────────┘  │   DLQ    │    (the SNS fan-out
                      │           └──────────┘     comparison path)
                 inventory svc
                      │ reply (direct SendMessage — point-to-point, low latency)
                      ▼
              ┌──────────────────────┐
              │ q-order-saga-replies │──▶ order (orchestrator)
              │  ↳ DLQ (mrc 5)       │
              └──────────────────────┘
  Same command/reply shape for q-payment-commands.
  Rule-level DLQ (dead_letter_config) on EVERY EventBridge target.
```

**Commands and replies are point-to-point → plain SQS queues, not topics.** There is no fan-out, so a topic would be ceremony. Replies go to a **single** `q-order-saga-replies` queue with a typed payload — one consumer, one place to look, and the orchestrator's concurrency is one knob.

**Retry / backoff — concrete values, and a correction:**

| Setting | Value | Why |
|---|---|---|
| SQS `visibility_timeout_seconds` | 6 × consumer p99 handling time (≈30 s for a 5 s handler) | Too low → duplicate concurrent processing; too high → slow retry. For a Lambda target it **must be ≥ the Lambda timeout**. |
| `maxReceiveCount` — commands | 3 | Fail fast to DLQ. You *want* to see failures. |
| `maxReceiveCount` — replies | 5 | Replies are more valuable to recover. |
| SQS `message_retention_seconds` | 1209600 (14 d) | Free; a dead session's messages are debugging material. |
| Lambda | `maximum_retry_attempts = 2`, `maximum_event_age = 3600`, on-failure destination → DLQ | |
| EventBridge target | `retry_policy` + `dead_letter_config` → SQS DLQ | Covers "SQS itself rejected the delivery" |

> ⚠️ **Correction to a near-universal misconception: standard SQS does NOT do exponential backoff.** It redelivers after the visibility timeout — a flat interval. To get exponential backoff the *consumer* must call `ChangeMessageVisibility(receiptHandle, min(base * 2^n, 900))` using `ApproximateReceiveCount` as `n`. Spring Cloud AWS's `SqsListener` exposes the `Visibility` argument for exactly this. Implement it; it is a five-line method that teaches more than a week of reading.
>
> Secondary trap: `ApproximateReceiveCount` **resets after a DLQ redrive**, so any logic keyed on it silently restarts its backoff.

**DLQ policy: every SQS queue gets a DLQ; every EventBridge target gets a DLQ; every Lambda gets an on-failure destination.** And — the part everyone skips — a Prometheus alert on `aws_sqs_approximate_number_of_messages_visible > 0` for *any* queue whose name ends `-dlq`. An unwatched DLQ is the most common real-world failure in this architecture: the system appears healthy and is silently dropping orders. Also write the redrive runbook (`aws sqs start-message-move-task`) *by actually redriving a message*, per the project's runbook rule.

### DynamoDB concurrency — confirm and refine

**Optimistic locking (version attribute) is confirmed as a valid pattern**, and the Java SDK Enhanced Client implements it for you via `@DynamoDbVersionAttribute` (adds `ConditionExpression: version = :expected` and bumps on write; throws `ConditionalCheckFailedException` on conflict).

**But for the inventory hot path, prefer an atomic conditional decrement over read-modify-write:**

```
UpdateItem  PK=SKU#123, SK=STOCK
  UpdateExpression:    SET available = available - :qty
  ConditionExpression: available >= :qty
```

One round trip, no read, cannot lose an update, and contention costs nothing (no retry storm). Optimistic locking is the right tool when you must write a *composite* of fields derived from a read — which is the **catalog/product** item, not the stock counter.

**Recommendation: use both, in the right places.** Conditional decrement for `inventory` stock; `@DynamoDbVersionAttribute` for `catalog` product documents. You practise both patterns *and* each is used where it is actually correct.

Traps to note: `TransactWriteItems` is limited to 100 items / 4 MB and **consumes double the WCU** — use it only for genuine multi-SKU reservations. And a `ConditionalCheckFailedException` retry loop needs **bounded attempts with jitter**, or a hot SKU produces a thundering herd.

---

## Data Flow — "place an order", end to end

### Happy path

```
[1]  Browser (CloudFront/S3 SPA)
       POST /api/orders   Authorization: Bearer <cognito JWT>
                          Idempotency-Key: <uuid>
        │
[2]  ALB (IngressGroup "ecommerce-public", rule order 10, /api/*)
        │  SYNC
[3]  api-gateway (Spring Cloud Gateway)
        ├─ validate JWT against Cognito JWKS (cached)
        ├─ rate limit (Redis token bucket)
        └─ route → order svc
        │  SYNC
[4]  order svc — ONE Postgres transaction:
        ├─ SELECT cart from cart-svc (Redis) ── SYNC ── and SNAPSHOT into saga payload
        ├─ INSERT orders(... , idempotency_key)        ← unique index = edge dedupe
        ├─ INSERT saga_instance(state=AWAITING_INVENTORY, step_deadline=now()+30s)
        ├─ INSERT saga_step_log(1, ReserveInventory, FORWARD, PENDING)
        └─ INSERT outbox(event_id, 'OrderPlaced', payload)
        COMMIT                          ◄── the ONLY strong consistency boundary
        │
        └─▶ 202 Accepted { orderId, sagaId }   ← NOT 201. See consistency trap #2.
        │
[5]  outbox poller (≤500 ms later)  →  EventBridge PutEvents (detail-type=OrderPlaced)
        │  ASYNC
[6]  EB rule → SQS q-inventory-commands
        │
[7]  inventory svc (SqsListener)
        ├─ PutItem PK=SKU#x SK=RSV#<event_id>  ConditionExpression: attribute_not_exists(SK)
        │     └─ already exists → duplicate → ack, return  (idempotent)
        ├─ UpdateItem SK=STOCK  SET available = available - :qty
        │              ConditionExpression: available >= :qty
        └─ SendMessage → q-order-saga-replies { InventoryReserved, sagaId, event_id }
        │  ASYNC
[8]  order svc consumes reply (dedupe + effect in ONE tx)
        ├─ saga_instance → AWAITING_PAYMENT, current_step=2, step_deadline=now()+30s
        └─ outbox INSERT 'AuthorizePayment'   → EB → q-payment-commands
        │
[9]  payment-sim: Authorize → reply PaymentAuthorized
        │
[10] order svc: PIVOT — capture payment (sync call, the one place sync is correct:
        you must know the outcome before you can decide to roll forward only)
        ├─ orders.status = CONFIRMED
        ├─ saga_instance.state = COMPLETED
        └─ outbox INSERT 'OrderConfirmed'
        │
[11] EB rule → λ notification → SES email        ← CHOREOGRAPHED: order svc
[11'] EB rule → (future consumers, zero code change in order)   doesn't know it exists
        │
[12] Browser polls GET /api/orders/{id}  (or SSE) → CONFIRMED
```

### Failure branches

| Failure at | Detection | Response |
|---|---|---|
| [7] `available >= :qty` fails | `ConditionalCheckFailedException` | Reply `InventoryRejected` → saga → `FAILED` (no compensation needed, nothing was done) |
| [7] consumer crashes after reserve, before reply | `step_deadline` expires | **Timeout sweeper** → `COMPENSATING` → `ReleaseInventory` (idempotent, so safe even though the reserve *did* happen) |
| [7] message poisoned | `maxReceiveCount` 3 exceeded | → `q-inventory-commands-dlq` → Prometheus alert → manual redrive runbook |
| [9] payment declined | Reply `PaymentDeclined` | `COMPENSATING` → C1 `ReleaseInventory` → `FAILED` |
| [9] payment-sim unreachable | `step_deadline` | Sweeper → `COMPENSATING` → C1. Note the ambiguity: the authorize may have *succeeded*. C2 `VoidAuthorization` must therefore be safe to call for an authorization that may not exist. |
| C1/C2 itself fails | Compensation retries exhausted | `state = COMPENSATION_FAILED` → **page** → manual queue. No automated recovery exists. Build the alert. |
| [10] capture fails after pivot | — | **Roll forward only.** Retry capture with backoff; never un-reserve inventory after the pivot. |
| Spot reclaim mid-anything | Node `NotReady` | `terminationGracePeriodSeconds` must exceed in-flight SQS handling, or the message re-appears after visibility timeout and idempotency saves you. This is the Spot scenario worth engineering for. |
| fck-nat dies | Cluster-wide `ImagePullBackOff`, SQS/EB calls time out | Everything queues; nothing is lost (outbox + SQS retention). Recovery is automatic once the ASG replaces the instance — a genuinely satisfying demonstration of why the outbox exists. |

### Consistency boundaries

**Strongly consistent:**
- One Postgres transaction: `orders` + `saga_instance` + `saga_step_log` + `outbox`. This single boundary is what makes the whole design work.
- One DynamoDB item under a `ConditionExpression`.
- DynamoDB reads **only when `ConsistentRead = true`** is explicitly set.

**Eventually consistent:** everything crossing EventBridge or SQS · order status as observed by the client · catalog reads · Redis cart (no durability at all — cache-as-database, a deliberate accepted risk for a TTL'd pre-checkout artefact).

### Where a naive implementation is *silently* wrong

1. **DynamoDB `GetItem` defaults to eventually consistent.** Read-before-write on the inventory path returns stale stock intermittently, under load, unreproducibly. Set `ConsistentRead = true` (2× RCU) — or, better, use the conditional decrement so you never read first. **And note: GSI reads are *always* eventually consistent with no opt-out**, so a read-before-write via a GSI can never be made safe.
2. **Read-your-writes on order status.** Client POSTs, immediately GETs, sees `PENDING`, UI renders "failed". This is why step [4] returns **202 + sagaId**, not 201 + a status. Returning 201 with `status: CONFIRMED` would be a lie for ~2 seconds.
3. **Believing the outbox gives exactly-once.** It gives at-least-once. (Covered above; it is the most common misreading of the pattern.)
4. **Assuming compensations succeed.** They are network calls. They fail. Without `COMPENSATION_FAILED` your saga silently strands inventory.
5. **Redis cart TTL expiring mid-checkout.** The saga re-reads the cart at step 2 and finds it empty → an order for nothing. Fix: **snapshot the cart into `saga_instance.payload` at saga start and never re-read it.** Shown explicitly in step [4] above because this is exactly the bug that takes three hours to find.
6. **`ApproximateReceiveCount`-driven backoff after a DLQ redrive** — the count resets, backoff restarts from zero.
7. **Wall-clock ordering across services.** Never order events by timestamp across pods; clocks skew. Order by `saga_instance.current_step` or a per-aggregate sequence.
8. **RDS `max_connections` on db.t4g.micro.** It is derived from instance memory (`LEAST({DBInstanceClassMemory/9531392}, 5000)`) — roughly **80–90 connections on a 1 GiB instance** *(MEDIUM confidence — formula is stable, exact value should be read from the parameter at runtime)*. Six services × HikariCP default pool of 10 × 2 replicas = 120, **before** Flyway and your `psql` session. You will hit `FATAL: remaining connection slots are reserved` and it will look like a network problem. **Set `spring.datasource.hikari.maximum-pool-size: 5` everywhere and only `order` needs Postgres at all.**

---

## Decision 6 — Persistence under daily teardown

### RDS Postgres → **seed from scratch. `skip_final_snapshot = true`.**

The cost argument is a red herring (a ~1 GiB snapshot is ~$0.10/mo). The real arguments:

| | Snapshot + restore | Seed from scratch |
|---|---|---|
| `make up` time | 10–20 min (restore), and restore is slower than create | ~5–7 min create + seconds of Flyway |
| Determinism | First-ever apply has no snapshot → conditional logic in Terraform; restored instances can drift on parameter group/settings | Schema in Git is the *only* truth |
| Reproducibility | A snapshot chain is precisely the hidden state that produces "works on my rebuild" | Every session starts from a known state |
| Alignment with project goal | Undermines it | **Is** the goal |

Implementation: **Flyway migrations run on `order` startup** (`spring.flyway.enabled=true`) + an idempotent seed as an Argo CD `PreSync` hook `Job` (`INSERT ... ON CONFLICT DO NOTHING`). Both live in Git.

**Keep one escape hatch:** `var.preserve_final_snapshot` (default `false`) wired to `skip_final_snapshot` / `final_snapshot_identifier`. When you have produced an *interesting broken state* mid-chaos-exercise and want to resume debugging tomorrow, snapshotting it is genuinely valuable day-2 capability. Default off so it never becomes ambient cost.

Operational note: **RDS delete takes 5–10 minutes and is the long pole in `make down`.** Worth parallelising L2's destroy against the drain steps if you later optimise wall-clock.

### DynamoDB → **destroy it, despite it being nearly free to keep**

`PAY_PER_REQUEST` with a practice dataset (<10 MB) costs ~$0.003/mo in storage. So cost says keep it. **Architecture says destroy it:**

- Keeping it splits the table between the immortal and ephemeral worlds → `terraform import`/drift management on a table that logically belongs with the data layer.
- Stale inventory counts carried across sessions produce confusing test results ("why is SKU-1 out of stock, I never ordered it") — the exact opposite of a reproducible practice environment.

Set `point_in_time_recovery = false` (PITR is ~$0.20/GB-mo and pointless here) and seed via the same `PreSync` Job.

> **Revisit trigger:** if you later want a 100k-item catalog for load testing, re-seeding it every session costs real WCU and minutes. At that point move *only the catalog table* to L0. Flag this as a decision to revisit at that trigger, not before.

### ElastiCache Redis → ephemeral, obviously — but consider not using it at all

`cache.t4g.micro` ≈ $0.016/hr *(MEDIUM confidence)* → ~$0.07 per 4-hour session. Cost is fine. **The real cost is wall-clock: ElastiCache creation is slow (~8–12 min) and deletion adds ~5 min to `make down`.** On a stack you rebuild daily, minutes of `make up` are the scarcest resource you have.

**Recommend ElastiCache for M1 anyway** — precisely *because* it exercises subnet groups, security groups, an intra-subnet with no egress, and a real network boundary, which is the learning. **But flag it as the first thing to cut**: if `make up` time becomes the friction that kills sessions, replace it with a single in-cluster Redis pod (free, zero teardown risk, and `cart` is explicitly ephemeral TTL state so nothing is lost).

### Is there a case for a persistent "data layer" stack? — **No. Here is the arithmetic.**

*(All MEDIUM confidence — stable list prices, verify against the pricing page before committing.)*

| Resource kept alive 730 h/mo | Monthly |
|---|---|
| RDS `db.t4g.micro` single-AZ (~$0.016/hr) | ~$11.70 |
| RDS 20 GiB gp3 storage | ~$2.30 |
| ElastiCache `cache.t4g.micro` (~$0.016/hr) | ~$11.70 |
| **Total** | **~$25.70/mo** |

Against a **$5/mo idle ceiling** that is a **5× overrun**. Verdict: **no persistent database layer.** This is not close.

**However — there IS a correct persistent layer, and it is not the databases.** It is L0, and it is the thing that makes `make up` fast:

| L0 resource | Idle cost | Why it must persist |
|---|---|---|
| ECR repositories + images | ~$0.10/GiB-mo → ~$0.50 | **The single biggest rebuild-time lever.** Rebuilding six Spring Boot images per session is 10+ minutes of CI. Set a lifecycle policy keeping the last 5 tags. |
| S3 tfstate (versioned) | pennies | Obvious |
| S3 observability bucket (Loki/Tempo chunks, 3-day lifecycle) | pennies | Lets traces survive teardown — you can debug yesterday's saga |
| Secrets Manager | ~$0.40/secret-mo | Keep the count ≤ 5, use one JSON secret per domain |
| S3 SPA bucket + CloudFront | ~free at idle | Distribution create/propagate is slow (~10 min); zero reason to rebuild it |
| CloudWatch log groups | **set `retention_in_days = 1`** | Default ∞ retention is a classic silent leak |
| Budgets + anomaly detection | free | Guardrail |

**L0 total ≈ $2–3/mo.** Budget holds with headroom.

> **Three silent cost leaks specific to teardown-heavy projects — `verify-teardown.sh` must check all three:** (1) RDS *automated backups* that survive instance deletion, (2) orphaned *manual* snapshots, (3) CloudWatch log groups with default infinite retention.

---

## Decision 7 — Cluster-internal architecture

### Namespaces

| Namespace | Contents | Policy posture |
|---|---|---|
| `kube-system` | EKS addons | Kyverno `baseline` (CNI/kube-proxy need hostNetwork) |
| `argocd` | Argo CD | `baseline` |
| `platform` | LBC, ESO, Kyverno, metrics-server, Karpenter | `baseline` |
| `observability` | Prometheus, Grafana, Loki, Tempo, OTel Collector, Alloy | `baseline` (node-exporter/Alloy need hostPath) |
| `ecommerce` | the 6 services | **Kyverno `restricted` + default-deny NetworkPolicy** |
| `chaos` | chaos tooling | `baseline`, privileged where needed |

Default-deny egress+ingress in `ecommerce` with explicit allows: `ecommerce → kube-dns:53`, `ecommerce → 0.0.0.0/0:443` (AWS APIs via fck-nat), `api-gateway ← ingress from the LBC node SG`, and service-to-service only where the architecture says so. **Add NetworkPolicies *after* the system works** — see build order.

### Capacity — quantified, because underestimating this is the classic failure

Realistic tuned-down *requests* (not limits):

| Component | CPU req | Mem req |
|---|---|---|
| `kube-system` (CoreDNS ×2, kube-proxy DS, aws-node DS, EBS CSI, Pod Identity Agent, metrics-server) | ~450 m | ~600 Mi |
| Argo CD (server, repo-server, app-controller, redis, applicationset) | ~350 m | ~1.0 Gi |
| kube-prometheus-stack (Prometheus ×1, node-exporter DS, kube-state-metrics, operator, Grafana, Alertmanager ×1) | ~500 m | ~2.0 Gi |
| Loki **SingleBinary** + Alloy/Promtail DS | ~250 m | ~1.0 Gi |
| Tempo monolithic | ~150 m | ~512 Mi |
| LBC(1) + ESO(3 pods) + Kyverno(admission+bg+cleanup+reports) + Karpenter(1) | ~400 m | ~1.0 Gi |
| **Platform subtotal** | **~2.1 vCPU** | **~6.1 GiB** |
| 6 Spring Boot services @ 100 m / 512 Mi | 600 m | 3.0 GiB |
| **Cluster total** | **~2.7 vCPU** | **~9.1 GiB** |

Plus kubelet/system-reserved (~100 m / 200 Mi per node) and headroom for rollouts.

> **Minimum viable cluster ≈ 4 vCPU / 12 GiB.** You **cannot** fit this on 2 × `t3.small`. Attempting to is the classic failure: Prometheus and Kyverno get OOMKilled, Argo CD's repo-server thrashes, and you spend the session debugging the observability stack instead of the saga.

**A verified, non-obvious sizing trap:** the Grafana **Loki Helm chart (currently v7.3.0) defaults to `deploymentMode: SimpleScalable`** — read/write/backend StatefulSets, ~6+ pods. On this cluster you **must** set `deploymentMode: SingleBinary` explicitly. The chart's own comment describes SingleBinary as *"useful for small installs typically without HA, up to a few tens of GB/day"* — exactly this workload. *(Confidence: HIGH — read from grafana/loki `production/helm/loki/values.yaml`.)*

### Node topology — what runs where

| Group | Shape | Hosts | Cost |
|---|---|---|---|
| **System** (EKS managed node group, **on-demand**, min=max=1) | 1 × `t4g.medium` (2 vCPU / 4 GiB) | **Karpenter itself** (must not run on a Karpenter node — circular), CoreDNS, Argo CD app-controller, Prometheus server | ~$0.034/hr *(MEDIUM)* |
| **Spot** (Karpenter `NodePool`) | `t4g.large` / `m7g.large` / `c7g.large`, 2–4 vCPU, diversified across both AZs | everything else | ~$0.025/hr each *(MEDIUM)*, 1–2 nodes |

Taint the system group `node-role=system:NoSchedule` with matching tolerations on the pinned workloads. A taint (rather than just `nodeSelector`) forces you to get tolerations right — CKA-adjacent practice you want.

**Recommend arm64 (Graviton) throughout** — `t4g`/`m7g`/`c7g` are ~20% cheaper than x86 equivalents and match the `t4g.nano` fck-nat. Every component here ships arm64 images (Argo CD, Kyverno, ESO, LBC, Karpenter, the Prometheus stack, Loki, Tempo, Spring Boot on a JDK base).

> ⚠️ **Cost this decision honestly in CI**, because it is not free: arm64 means `docker buildx --platform linux/arm64` in GitHub Actions. On x86 runners that is QEMU emulation and can be **5–10× slower**. Use GitHub's arm64-hosted runners (`ubuntu-24.04-arm`) for the image build job. Validate arm64 image availability for every chart **in Phase 1**, before it is expensive to reverse.

### Hourly cost roll-up *(MEDIUM confidence — list prices)*

| Line item | $/hr | Share |
|---|---|---|
| **EKS control plane** | **0.10** | **42%** |
| Spot nodes (2 × t4g.large) | 0.050 | 21% |
| On-demand system node (t4g.medium) | 0.034 | 14% |
| ALB (1, shared via IngressGroup) | 0.0225 | 9% |
| RDS db.t4g.micro | 0.016 | 7% |
| ElastiCache t4g.micro | 0.016 | 7% |
| fck-nat t4g.nano | 0.0042 | 2% |
| WAF (prorated) | ~0.008 | 3% |
| **Total** | **≈ $0.25/hr** | fits the $0.30 target |

> **The EKS control plane alone is ~42% of the hourly cost (~$73/mo if left running).** The optimisation that matters is **session length, not instance type**. A 3-hour session ≈ $0.75. This also means: *there is no instance-type tuning that rescues a cluster you forgot to destroy* — hence the Budgets alarm and the teardown verifier are cost controls of the first order, not hygiene.

### Resource requests, limits, PDBs, topology spread — with the traps

- **Requests** = realistic p50. **Memory limit** = request × 1.5, with `-XX:MaxRAMPercentage=75` on every Spring Boot container.
- **Set no CPU limits.** CPU throttling (`container_cpu_cfs_throttled_seconds_total`) manifests as latency that looks exactly like a network problem and is the single most misdiagnosed Kubernetes issue. Leave CPU unlimited, alert on throttling if you later add limits. Worth experiencing deliberately once.
- **PodDisruptionBudgets — the trap that will bite you:** a PDB with `minAvailable: 1` on a **single-replica** Deployment makes the pod permanently undrainable → **Karpenter consolidation blocks forever** → you pay for idle nodes and `make down`'s drain step hangs. On a 1–2 node cluster almost everything is single-replica.
  - **Use `maxUnavailable: 1` for single-replica workloads** (allows disruption), `minAvailable: 1` only where replicas ≥ 2.
  - Annotate the Prometheus pod `karpenter.sh/do-not-disrupt: "true"` so consolidation doesn't churn the thing you observe incidents with.
- **Topology spread:** with 1–2 nodes, `whenUnsatisfiable: DoNotSchedule` will wedge pods in `Pending` with a confusing event. Configure spread anyway (for the learning) but with **`whenUnsatisfiable: ScheduleAnyway`, `maxSkew: 1`** over `topology.kubernetes.io/zone`.
- **Karpenter `NodePool`** (API `karpenter.sh/v1`, controller **v1.14.0** — *verified from the public ECR tag list*): `consolidationPolicy: WhenEmptyOrUnderutilized` for maximum churn (and therefore maximum practice), `expireAfter: 24h`, `capacity-type: [spot]`, and **broad `instance-family`/`instance-size` requirements** — instance-type diversity is the single most effective Spot-interruption mitigation.

### Observability storage — **object storage, not EBS**

This is a strong recommendation specifically *because* of the teardown constraint:

- **Loki** → S3 backend (`storage.type: s3`, bucket in **L0**, auth via Pod Identity). **Tempo** → S3 backend, same bucket, different prefix.
- **Prometheus** → `emptyDir` with `retention: 6h`, or a small 10 Gi gp3 PVC if you accept the drain step.
- **Why:** PVCs mean dynamically-provisioned EBS volumes, which are (a) an orphan class requiring drain step 3, (b) **AZ-pinned**, which actively fights Karpenter consolidation across AZs and produces `volume node affinity conflict` — a genuinely nasty scheduling failure.
- **Bonus:** S3-backed logs and traces **survive teardown**. You can debug last night's saga this morning. That is a large practical win for a platform that dies every night. Put a 3-day lifecycle rule on the bucket.

---

## Recommended Project Structure

```
/
├── Makefile                      # up / down / drain / verify — the operator's entire UI
├── layers/
│   ├── 00-bootstrap/             # IMMORTAL. applied by hand, never in `make down`
│   ├── 10-infra/                 # VPC + fck-nat + endpoints + EKS + addons + all IAM
│   ├── 20-data/                  # RDS, DynamoDB, ElastiCache, EventBridge, SQS, SNS, Cognito
│   └── 30-gitops/                # helm_release argocd + root Application. TWO resources.
├── modules/
│   ├── network/  eks-platform/  saga-queue/   # saga-queue = queue+DLQ+alarm+EB rule, one call
├── scripts/
│   ├── drain-ingress.sh          # POLLS aws elbv2 until empty
│   ├── drain-nodes.sh            # POLLS ec2 until no karpenter.sh/nodepool instances
│   ├── drain-pvcs.sh             # POLLS ec2 until no unattached project-tagged volumes
│   └── verify-teardown.sh        # orphan + cost-leak sweep. WRITTEN FIRST.
├── gitops/                       # Argo CD's territory. Nothing here is in Terraform.
│   ├── root-app.yaml             # app-of-apps
│   ├── platform/                 # lbc · eso · kyverno · metrics-server · karpenter(+NodePool)
│   ├── observability/            # kube-prom-stack · loki(SingleBinary,S3) · tempo(S3) · otel-col
│   └── ecommerce/                # per-service Application + Kustomize overlays
├── services/
│   ├── api-gateway/ catalog/ cart/ order/ payment-sim/     # Spring Boot (Gradle)
│   └── notification/                                       # Python Lambda
├── frontend/                     # React + Vite → S3/CloudFront
├── chaos/                        # scenario scripts, one per runbook
└── docs/runbooks/                # WRITTEN BY DEBUGGING, not by describing
```

**Structure rationale:**
- `layers/` numbering **is** the apply order; reverse numbering is the destroy order. The filesystem encodes the choreography so it cannot be misremembered at 11pm.
- `gitops/` and `layers/` are strictly disjoint. If a resource appears in both, the boundary has been violated — this is grep-able and worth a CI check.
- `scripts/` holds the three drain steps that are *deliberately not Terraform*. Their existence as first-class files is the architecture made visible.
- Single repo (not split app/manifests). Argo CD reads `gitops/` from the same repo. A separate manifests repo is production practice but adds a cross-repo PR dance that buys nothing for one operator; revisit at M2 if image-tag write-back becomes annoying.

---

## Build Order

### Ordering principle

> **Build the thinnest vertical slice through every architectural layer first, then thicken each layer.**

The "place an order and watch the trace" moment needs: VPC + cluster + ALB + 4 services + RDS/DynamoDB/SQS + Tempo/Grafana + OTel. It does **not** need Karpenter, Kyverno, NetworkPolicies, WAF, ESO, Cognito, canary, Loki, Prometheus dashboards, chaos, the frontend, the notification Lambda, or contract tests. Deferring all of that pulls the feedback loop forward by weeks.

### Phases

| # | Phase | Requires | Unblocks | ∥ |
|---|---|---|---|---|
| **P0** | **Repo + L0 bootstrap + teardown harness.** S3 state (`use_lockfile`), ECR + lifecycle policy, GH OIDC + CI role, Budgets, cost tags. Makefile skeleton. **`verify-teardown.sh` written now, before there is anything to tear down.** | — | everything | |
| **P1** | **L1 infra + drain scripts.** VPC/fck-nat/gateway endpoints/EKS/system node group/EKS addons/Pod Identity roles. **GATE: two consecutive clean `make up` → `make down` round-trips with an empty cluster and zero orphans.** | P0 | P2 | |
| **P1b** | **App scaffolding.** Six Spring Boot skeletons + Dockerfiles + GH Actions build→ECR (arm64). No cluster needed. **Validate arm64 images for every chart here.** | P0 | P3 | ∥ P1 |
| **P2** | **L3 Argo CD seed + first platform apps.** app-of-apps → LBC + metrics-server. Hello-world Ingress in the shared IngressGroup. **GATE: ALB serves traffic AND `make down` is still clean — drain step 1 now exercised for real.** | P1 | P3 | |
| **P3** | **L2 data (minimal) + two services.** RDS + DynamoDB + one SQS command/reply pair + EventBridge bus. Deploy `order` + `inventory` only. Flyway + seed Job. | P1b, P2 | P4 | |
| **P4** | **★ THE MOMENT.** `api-gateway` + `payment-sim` added. Minimal 3-step saga, happy path only. OTel Java agent + OTel Collector → Tempo (S3) → Grafana. **Target: `curl -X POST /api/orders` produces one trace spanning gateway → order → EventBridge → SQS → inventory → reply.** | P3 | everything after | |
| **P5** | **Complete the saga.** Compensations, pivot/capture, timeout sweeper, DLQs + redrive runbook, idempotency at all three layers, `payment-sim` failure injection. Now it can be broken on purpose. | P4 | P6, P11 | |
| **P6** | **Karpenter + Spot.** Chart + `NodePool`/`EC2NodeClass` via Argo CD (AWS side already exists from P1). Now watch what breaks: PDBs, `terminationGracePeriodSeconds` vs in-flight SQS, graceful shutdown. **Deliberately after P5** — a Spot interruption *mid-saga* is the scenario you actually want. Drain step 2 becomes live. | P5 | P11 | |
| **P7** | **Prometheus + Loki + alerting.** kube-prom-stack, Loki (SingleBinary, S3), RED/USE dashboards, **DLQ-depth alerts**, SLO burn rules. | P4 | P11 | ∥ P6 |
| **P8** | **Security hardening.** ESO + Secrets Manager, Cognito at gateway + ALB auth on platform paths, NetworkPolicies (default-deny), Kyverno (PSS + the Exclusive-annotation guard), WAF, Trivy + Checkov in CI. Internally fully parallel. **Deliberately late:** added after things work, every failure is attributable; added early, every bug looks like a policy bug. | P5 | | ∥ P7 |
| **P9** | **Frontend + notification Lambda + CloudFront.** The choreographed consumer lands here — proves loose coupling by requiring zero change to `order`. | P5 | | ∥ P8 |
| **P10** | **Progressive delivery.** Argo Rollouts canary on `catalog` (stateless, read-only, safest to canary). | P7 (needs metrics for analysis) | | |
| **P11** | **Chaos + runbooks.** The payoff. Every runbook written *by debugging*. | P5, P6, P7 | | |
| **P12** | **Testing depth.** Testcontainers integration tests, contract tests, E2E smoke gate against a freshly provisioned cluster. | P5 | | ∥ P11 |

### Critical path to the trace moment

```
P0 ──▶ P1 ──▶ P2 ──▶ P3 ──▶ P4 ★
  └──▶ P1b ─────────┘
```

Everything else hangs off P4 or P5. **If a phase can be moved after P4, move it after P4.**

### The one technical risk that can sink P4

**Trace context does not propagate across SQS/EventBridge automatically.** The W3C `traceparent` must be injected by the producer and extracted by the consumer:

- **SQS:** OpenTelemetry's messaging instrumentation propagates via **SQS message attributes** — but SQS allows a maximum of **10 message attributes**, and the AWS SDK instrumentation must be enabled on both ends. Workable out of the box with the Java agent.
- **EventBridge:** `PutEvents` has **no message-attribute channel**. You must carry `traceparent` **inside `detail`** (e.g. `detail._otel.traceparent`) and extract it manually in the consumer. This is *not* automatic.

> This is the #1 reason people report "my trace stops at the queue". **Make it an explicit, named task in P4, not an afterthought** — the entire payoff of P4 is a single unbroken trace, and this is the thing that breaks it.

---

## Anti-Patterns

### AP1 — Managing in-cluster resources with the Terraform `helm`/`kubernetes` providers
**What people do:** `helm_release` for LBC, Karpenter, Prometheus, Argo CD, plus `kubernetes_manifest` for CRs.
**Why it's wrong:** those providers need a live apiserver at *plan* time; on first apply the endpoint is unknown and on destroy the cluster may be gone, wedging state. Worse, Terraform cannot see resources the installed controllers create in AWS, so destroy leaves orphans that block VPC deletion.
**Instead:** Terraform owns the AWS API; Argo CD owns the Kubernetes API; the helm provider appears exactly once, in L3, to install Argo CD, and L3 is destroyed first.

### AP2 — Assuming `terraform destroy` is a complete teardown
**What people do:** `make down` = `terraform destroy`.
**Why it's wrong:** ALBs, Karpenter EC2 instances, EBS volumes, and controller-created SGs are not in state. `terraform destroy` will either fail on `DependencyViolation` or "succeed" while leaking billable resources.
**Instead:** `make down` = drain (k8s, polling) → destroy (TF, reverse layer order) → verify (orphan sweep, non-zero exit on any hit).

### AP3 — Buying interface endpoints "to save NAT cost"
**What people do:** add ECR/STS/Secrets Manager/SQS interface endpoints reflexively.
**Why it's wrong:** ~$0.01/hr/AZ each. At 2 AZs, **five endpoints cost more per hour than all the compute combined**, to avoid a few MB of fck-nat traffic.
**Instead:** gateway endpoints for S3 and DynamoDB (free, and S3 is where ECR layers actually come from). Zero interface endpoints, behind a feature flag for a deliberate cost experiment.

### AP4 — Believing the transactional outbox delivers exactly-once
**What people do:** skip consumer idempotency because "the outbox handles it".
**Why it's wrong:** publish-then-mark is not atomic. At-least-once, always.
**Instead:** idempotency at all three layers (API key, `event_id`, store-native conditional write).

### AP5 — Blind additive compensation
**What people do:** `ReleaseInventory` = `available += qty`.
**Why it's wrong:** retried compensations double-credit stock. Only happens on failure paths, so it is invisible until an audit.
**Instead:** flip a reservation status under a `ConditionExpression`, or derive available stock from active reservations.

### AP6 — `minAvailable: 1` PDBs on single-replica workloads
**What people do:** apply PDBs uniformly as "good practice".
**Why it's wrong:** makes the pod undrainable → Karpenter consolidation blocks forever → idle nodes you pay for and drains that hang.
**Instead:** `maxUnavailable: 1` for single-replica, `minAvailable: 1` only at replicas ≥ 2.

### AP7 — Sizing the cluster for the application
**What people do:** "six small services, 2 × t3.small will do".
**Why it's wrong:** the *platform* (Argo CD + Prometheus + Loki + Tempo + Kyverno + ESO) is ~2.1 vCPU / 6.1 GiB before a single business pod. You will spend sessions debugging OOMKilled observability instead of the saga.
**Instead:** ~4 vCPU / 12 GiB floor, and Loki explicitly in `SingleBinary` mode (the chart defaults to `SimpleScalable`).

### AP8 — Installing the Loki chart with default values
**What people do:** `helm install loki grafana/loki`.
**Why it's wrong:** default `deploymentMode: SimpleScalable` deploys read/write/backend StatefulSets — a multi-GB footprint on a cluster that has ~6 GiB total to spare.
**Instead:** `deploymentMode: SingleBinary`, S3 object storage, `replicas: 1`.

### AP9 — Spreading Exclusive annotations across IngressGroup members
**What people do:** put `scheme`/`subnets`/`certificate-arn` on each service's Ingress.
**Why it's wrong:** one conflicting value freezes reconciliation for the **entire group** — every service's routing stops updating, silently.
**Instead:** one anchor Ingress (or `IngressClassParams`) owns all Exclusive annotations; a Kyverno policy rejects them elsewhere.

### AP10 — Re-reading the cart during the saga
**What people do:** fetch the cart from Redis when building the order.
**Why it's wrong:** TTL expiry mid-saga yields an order for nothing, intermittently.
**Instead:** snapshot the cart into `saga_instance.payload` at saga start; never re-read.

---

## Integration Points

### External services

| Service | Integration pattern | Gotchas |
|---|---|---|
| ECR | Node pulls via instance-profile auth; **layers served from S3** | Needs the S3 gateway endpoint. Without egress (fck-nat down), the ECR *API* auth fails → cluster-wide `ImagePullBackOff`. |
| Secrets Manager | External Secrets Operator → `ExternalSecret` → k8s Secret, via Pod Identity | ~$0.40/secret-mo — consolidate into few JSON secrets. ESO refresh interval ≠ pod restart; the pod won't see a rotation without a reloader. |
| Cognito | JWT validated at `api-gateway` against cached JWKS; ALB-native `auth-type: cognito` for Grafana/Argo CD paths | Cognito user pool is in L2 → **user pool is destroyed nightly, so users are recreated by the seed Job.** Accept it; don't try to persist it. |
| EventBridge | `PutEvents` from the outbox, batched ≤10/call | No message-attribute channel — `traceparent` must live in `detail`. 256 KB event limit. |
| SQS | Spring Cloud AWS `@SqsListener` | Backoff is the consumer's job (`ChangeMessageVisibility`), not SQS's. Visibility timeout ≥ Lambda timeout for Lambda targets. |
| SES | notification Lambda | Sandbox mode by default — only verified recipients. Verify one address in **L0** so it survives teardown. |
| GitHub Actions | OIDC → `sts:AssumeRoleWithWebIdentity` | Trust policy must pin `sub` to `repo:<org>/<repo>:ref:refs/heads/main` (and environment), not `*`. arm64 image builds need `ubuntu-24.04-arm` runners or QEMU will be 5–10× slower. |

### Internal boundaries

| Boundary | Communication | Notes |
|---|---|---|
| browser ↔ api-gateway | HTTPS via CloudFront + ALB | `Idempotency-Key` required on `POST /api/orders` |
| api-gateway ↔ services | sync HTTP (in-cluster) | The only sync fan-out; keep it thin |
| order ↔ inventory / payment-sim | **async, EventBridge → SQS commands; SQS replies** | Never sync. The sync temptation here is what destroys the learning value. |
| order ↔ (capture at pivot) | sync HTTP | The one legitimate sync call in the saga — you must know the outcome to decide roll-forward |
| order → notification | EventBridge rule, **choreographed** | `order` has no knowledge of it. Adding consumers = a Terraform rule, zero service change. |
| cart ↔ order | sync read, **snapshotted once** | See AP10 |
| Terraform ↔ Argo CD | L3 `helm_release` + one root `Application` | The only seam. Everything else is strictly one side or the other. |
| L1 ↔ L2 | `terraform_remote_state` (subnets, SGs) | A *read* dependency, **not** an ordering guarantee — `make down` must enforce order |

---

## Scaling Considerations

Real scaling is out of scope (no real users). The useful question is **what breaks first when you load-test**, because that is where the day-2 learning is.

| Scale | What happens |
|---|---|
| Normal practice (1 user) | Everything idle; cost is the only constraint |
| A `hey`/`k6` burst (~100 rps) | **RDS connection exhaustion first** (db.t4g.micro ≈ 80–90 `max_connections`; HikariCP defaults will blow it). Then fck-nat `t4g.nano` network credits. Then Prometheus memory. |
| Sustained load | Karpenter provisions Spot nodes → private-subnet IP pressure (why /20, not /24) → DynamoDB on-demand throttling on a hot partition key |

**Scaling priorities (in the order you will actually hit them):**
1. **RDS connections** — set `maximum-pool-size: 5`; only `order` needs Postgres at all.
2. **fck-nat single instance** — `t4g.nano` burst credits exhaust under sustained egress. The S3 gateway endpoint already removes the largest consumer (image layers). Next step is `t4g.small`, not a second instance.
3. **Prometheus memory** — the first thing OOMKilled on a small cluster. Cut scrape targets and retention before adding nodes.
4. **DynamoDB hot partition** — a single hot SKU serialises on one partition. Fixes: write sharding (`SKU#123#<shard>`), or accept it as a demonstration of why hot keys matter.
5. **Single ALB LCU cost** — only at real traffic; irrelevant here.

---

## Confidence Summary

| Area | Confidence | Basis |
|---|---|---|
| TF/K8s provider boundary, layering, teardown choreography | **HIGH** | Reasoned from verified module/provider mechanics; `terraform-aws-modules/eks` v21 requirements block confirms no `kubernetes` provider needed |
| S3 native state locking, `dynamodb_table` deprecated | **HIGH** | Read directly from hashicorp/web-unified-docs `language/backend/s3.mdx` |
| IngressGroup semantics + ALB deletion on empty group | **HIGH** | Read directly from aws-load-balancer-controller v3.5.0 docs |
| Karpenter v1 API, Pod Identity default in EKS module v21 | **HIGH** | Karpenter public-ECR tags (v1.14.0) + `nodepools.md` (`karpenter.sh/v1`) + UPGRADE-21.0.md |
| Loki chart default `SimpleScalable` | **HIGH** | Read from grafana/loki `values.yaml` (chart v7.3.0) |
| Saga / outbox / idempotency / compensation design | **HIGH** | Well-established patterns, reasoned concretely against this exact stack |
| AWS unit pricing (EKS $0.10/hr, endpoints $0.01/hr/AZ, instance rates) | **MEDIUM** | Long-stable list prices, **not** re-verified against the pricing API this session. **Verify before committing the budget.** |
| Capacity table (2.1 vCPU / 6.1 GiB platform) | **MEDIUM** | Composed from typical chart defaults; measure with `kubectl top` in P2/P7 and correct |
| RDS `max_connections` ≈ 80–90 on db.t4g.micro | **MEDIUM** | Formula `LEAST({DBInstanceClassMemory/9531392},5000)` is stable; read the actual value at runtime |

### Gaps for later phase-specific research
- Exact current AWS pricing for ap-southeast-1 (or chosen region) — **do this before P0**, the whole budget rests on it.
- Spring Cloud AWS v3 `@SqsListener` + OTel messaging instrumentation: confirm automatic `traceparent` propagation over SQS end-to-end (needed in P4).
- arm64 image availability audit across every chart (needed in P1b).
- Argo Rollouts + ALB `TargetGroupBinding` traffic-splitting mechanics (needed in P10).
- Kyverno policy authoring for the Exclusive-annotation guard (P8).

## Sources

- HashiCorp `web-unified-docs` — `content/terraform/v1.16.x/docs/language/backend/s3.mdx` (`use_lockfile`; `dynamodb_table` deprecated) — **HIGH**
- `kubernetes-sigs/aws-load-balancer-controller` — `docs/guide/ingress/annotations.md`, chart/app **v3.5.0** (IngressGroup, Exclusive vs Merge, ALB deletion on empty group) — **HIGH**
- `terraform-aws-modules/terraform-aws-eks` — README + `docs/UPGRADE-21.0.md`, **v21.26.0** (no `kubernetes` provider; `aws-auth` removed; Karpenter Pod Identity by default) — **HIGH**
- `aws/karpenter-provider-aws` — `website/.../concepts/nodepools.md` (`karpenter.sh/v1`, consolidation policies); public ECR tag list (**v1.14.0**) — **HIGH**
- `grafana/loki` — `production/helm/loki/values.yaml` (chart **v7.3.0**, `deploymentMode` default `SimpleScalable`) — **HIGH**
- Terraform Registry / releases.hashicorp.com — Terraform **1.16.4**, `hashicorp/aws` **6.66.0**, `terraform-aws-modules/vpc` **6.7.3**, `RaJiska/fck-nat` **1.6.1** — **HIGH**
- Helm repo indexes — Argo CD chart **10.9.2**, kube-prometheus-stack **91.5.1**, Tempo **1.24.4**, Grafana **10.5.15**, External Secrets **2.11.0** — **HIGH**
- AWS list pricing (EKS control plane, VPC interface endpoints, EC2/RDS/ElastiCache/ALB rates) — **MEDIUM, not re-verified this session**

---
*Architecture research for: cost-constrained EKS e-commerce microservices practice platform with same-day teardown*
*Researched: 2026-09-24*
