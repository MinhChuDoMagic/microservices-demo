# Pitfalls Research

**Domain:** Cost-constrained AWS EKS e-commerce microservices practice platform (Terraform, Spring Boot, Spot + Karpenter, Argo CD, self-hosted LGTM-ish observability, same-day full teardown)
**Researched:** 2026-09-24
**Confidence:** HIGH on cost/pricing and Karpenter/ALB-controller mechanics (verified against live AWS and upstream docs this session). MEDIUM on operational folklore (teardown orphan lists, OTel async-context breakage, Argo CD rebootstrap patterns) — flagged inline.

> **Audience note.** The operator holds SAP-C02 and CKA. Nothing here explains what a NAT Gateway or a PDB *is*. Everything here is about the gap between knowing the primitive and surviving it on a $0.30/hour budget with a daily destroy cycle.

---

## The One-Paragraph Version

This project has exactly one failure mode that kills it outright: **a resource survives `terraform destroy` and bills silently**. Every other pitfall is recoverable. The EKS control plane alone is **$0.10/hr = $73/month** ([verified](https://aws.amazon.com/eks/pricing/)) — that is 14x the entire idle budget, so "I'll just leave it up tonight" is a $2.40 mistake per night and "I forgot for two weeks" is a $34 mistake. The second-highest-likelihood killer is subtler and is **already latent in PROJECT.md**: the decision to use "VPC endpoints for AWS-native traffic" to avoid NAT costs. Interface VPC endpoints bill **$0.01 per endpoint-ENI-hour** ([verified](https://aws.amazon.com/privatelink/pricing/)) = **$7.30/month per AZ per endpoint**. Five interface endpoints across two AZs is **$73/month** — 24x the ~$3/month fck-nat instance the project chose them to complement. This is the single most important correction in this document.

---

## Priority Ranking (likelihood × damage)

| # | Pitfall | Likelihood | Damage | Score | Category |
|---|---------|-----------|--------|-------|----------|
| 1 | Interface VPC endpoints cost more than the NAT they replace | **Very High** (already in the plan) | High ($73/mo) | 🔴 CRITICAL | Cost |
| 2 | Orphaned resources survive `terraform destroy` (ALB/TG/SG/EBS/ENI/Karpenter nodes) | **Very High** | High (unbounded) | 🔴 CRITICAL | Cost |
| 3 | Cluster left running overnight / over a weekend | High | High ($73/mo run-rate) | 🔴 CRITICAL | Cost |
| 4 | `terraform destroy` fails because the k8s/helm provider can't reach a dead API server | **Very High** | High (breaks the whole practice loop) | 🔴 CRITICAL | Terraform |
| 5 | Observability stack starves the application on a tiny cluster | High | High (demotivating, looks like app bugs) | 🔴 CRITICAL | Observability |
| 6 | CloudWatch log groups with infinite retention, orphaned by destroy | High | Medium (grows monotonically) | 🟠 HIGH | Cost |
| 7 | Missing/wrong subnet tags silently break the ALB controller | High | Medium (hours lost, no error) | 🟠 HIGH | Networking |
| 8 | Karpenter consolidation thrashing (`consolidateAfter: 0s` default) | High | Medium (churn, Spot cost, flapping pods) | 🟠 HIGH | Karpenter |
| 9 | Non-idempotent SQS consumers → duplicate orders | High | High (corrupts the centrepiece saga) | 🟠 HIGH | Correctness |
| 10 | "Infrastructure forever, never ship a feature" | **Very High** | High (project death by boredom) | 🟠 HIGH | Learning |
| 11 | JVM OOMKilled despite correct `-Xmx` | High | Medium | 🟠 HIGH | Spring Boot |
| 12 | Traces split at the SQS/SNS boundary | **Very High** | Medium (kills the flagship demo) | 🟠 HIGH | Observability |
| 13 | No graceful shutdown → dropped requests on every Spot reclaim | High | Medium | 🟠 HIGH | Spring Boot |
| 14 | Argo CD can't rebootstrap cleanly after daily destroy | High | Medium (manual toil every session) | 🟠 HIGH | GitOps |
| 15 | Karpenter bootstrap chicken-and-egg | Medium | Medium | 🟡 MEDIUM | Karpenter |
| 16 | Provider/module version drift breaks a rebuild weeks later | Medium | High (rebuild fails, loop dies) | 🟡 MEDIUM | Terraform |
| 17 | Kyverno/OPA policy locks the operator out of their own cluster | Medium | High (rebuild required) | 🟡 MEDIUM | Security |
| 18 | GitHub Actions OIDC trust policy scoped too loosely | Medium | **Critical** (account compromise) | 🟡 MEDIUM | Security |
| 19 | RDS connection pool exhaustion across replicas | Medium | Medium | 🟡 MEDIUM | Spring Boot |
| 20 | Prometheus cardinality explosion | Medium | Medium (OOM) | 🟡 MEDIUM | Observability |
| 21 | Copying stale tutorials (Karpenter v1beta1→v1) | High | Low-Medium (wasted hours) | 🟡 MEDIUM | Learning |
| 22 | VPC CNI IP exhaustion / prefix-delegation fragmentation | Low (at this scale) | Medium | 🟢 LOW | Networking |
| 23 | Public EKS API endpoint open to 0.0.0.0/0 | Medium | Medium (auth still required) | 🟢 LOW | Security |

---

# 1. COST — The Project-Killer

## 1.1 The Silent-Accrual Inventory

Every line item below bills whether or not a single request is served. Figures are `us-east-1`; verify your region.

| Charge | Rate | Monthly if left up | Accrues at zero traffic? | Survives `terraform destroy`? | Confidence |
|---|---|---|---|---|---|
| **EKS control plane** | **$0.10/cluster-hr** | **$73.00** | **YES — even with zero nodes** | No (but see §2.1 deadlocks) | HIGH ✅ |
| EKS extended support (>14mo version) | $0.60/cluster-hr | $438.00 | YES | No | HIGH ✅ |
| **Interface VPC endpoint** | **$0.01/endpoint-ENI-hr** | **$7.30 per AZ per endpoint** | **YES** | No | HIGH ✅ |
| Interface endpoint data processing | $0.01/GB (first PB) | usage | No | — | HIGH ✅ |
| **Gateway VPC endpoint (S3, DynamoDB)** | **$0.00** | **$0.00** | — | — | HIGH ✅ |
| **ALB** | **$0.0225/hr** + LCU | **$16.43** + LCU | YES (idle ALB still bills base) | **OFTEN NOT** (see §1.3) | HIGH ✅ |
| NLB | $0.0225/hr + NLCU | $16.43 + NLCU | YES | OFTEN NOT | HIGH ✅ |
| NAT Gateway (rejected) | $0.045/hr + $0.045/GB | $32.85 + data | YES | No | HIGH ✅ |
| **Public IPv4 address (any, in-use or idle)** | ~$0.005/hr | **~$3.65 each** | YES | Idle EIPs: **NO** | MEDIUM ⚠️ (rate not re-confirmed on page this session; AWS Feb-2024 change) |
| **Route 53 public hosted zone** | **$0.50/zone/mo, NOT prorated, charged at creation AND on the 1st** | $0.50 | YES | Yes if in TF | HIGH ✅ |
| EBS gp3 storage | ~$0.08/GB-mo | $0.80 per 10GB | YES | **PVC-created volumes: NO** | HIGH ✅ |
| EBS gp3 provisioned IOPS above baseline | $0.005/IOPS-mo | — | YES | — | HIGH ✅ |
| EBS snapshots | ~$0.05/GB-mo | — | YES | **Manual snapshots: NO** | MEDIUM ⚠️ |
| RDS final snapshot + manual snapshots | snapshot storage rate | — | **YES, after the instance is gone** | **NO — `final_snapshot` outlives destroy by design** | HIGH ✅ |
| RDS automated backups | free up to allocated storage, then billed | — | YES | Deleted with instance | MEDIUM ⚠️ |
| ECR storage | $0.10/GB-mo | $1.00 per 10GB | YES | **Images: NO, repo often `force_delete=false`** | MEDIUM ⚠️ |
| **CloudWatch Logs ingestion** | ~$0.50/GB | usage-driven, can spike | YES (control-plane logging!) | **Log groups: frequently NO** | MEDIUM ⚠️ |
| CloudWatch Logs storage | ~$0.03/GB-mo, **retention = Never Expire by default** | grows forever | YES | Often NO | HIGH ✅ (the default is the documented trap) |
| **Cross-AZ data transfer (pod↔pod, pod↔RDS)** | $0.01/GB each direction = **$0.02/GB round trip** | real, underestimated | No | — | MEDIUM ⚠️ |
| NAT/fck-nat egress for image pulls | fck-nat: only EC2 + IPv4 cost; NAT GW: $0.045/GB | see §1.2 | No | — | HIGH ✅ |
| S3 (TF state) + DynamoDB (lock) | pennies | <$0.10 | YES | **Intentionally survives** | HIGH ✅ |

### The $0.30/hour budget, decomposed

```
EKS control plane                    $0.1000/hr   ← 33% of budget, non-negotiable
ALB (1x, base)                       $0.0225/hr   ← 8%
fck-nat t4g.nano (spot/on-demand)    $0.0042/hr   ← 1.4%
Public IPv4 x3 (fck-nat + 2 ALB AZ)  $0.0150/hr   ← 5%
───────────────────────────────────────────────
Fixed overhead BEFORE any compute    $0.1417/hr   ← 47% of budget
Remaining for EC2 + RDS + Redis      $0.1583/hr
```

**Implication for the roadmap:** the budget is effectively **~$0.16/hr for all workload compute**. On Spot, that is roughly 2–3 `t3a.medium`/`m6a.large`-class instances. That is your real cluster size ceiling — design the observability stack and service resource requests against *that* number, not against a hypothetical.

---

### Pitfall 1: Interface VPC endpoints cost more than the NAT they replace 🔴

**What goes wrong:**
PROJECT.md commits to "fck-nat instance (t4g.nano) for egress, **and VPC endpoints for AWS-native traffic**" with the rationale of cutting ~$32/month. But interface endpoints bill **$0.01 per endpoint-ENI-hour** — one ENI *per subnet/AZ per endpoint*. A typical "let's be proper about it" endpoint set for this stack (`ecr.api`, `ecr.dkr`, `sts`, `logs`, `secretsmanager`, `sqs`, `sns`, `events`, `elasticache`) is **9 endpoints × 2 AZs × $7.30 = $131/month idle**. Even a modest five-endpoint, two-AZ set is **$73/month** — more than double the NAT Gateway that was rejected on cost, and ~24x the fck-nat instance.

**Why it happens:**
The "use VPC endpoints instead of NAT" advice is genuinely correct at production scale, where NAT *data processing* ($0.045/GB) dominates. At this project's scale, data volume is near zero, so the fixed hourly charge dominates and the advice inverts. It is a textbook case of applying a production heuristic outside its validity range — exactly the kind of gap certifications leave.

**How to avoid:**
1. **Use only the two free gateway endpoints:** `com.amazonaws.<region>.s3` and `com.amazonaws.<region>.dynamodb`. These cost **$0.00/hr** and are pure win. DynamoDB is used by `catalog` and `inventory`; S3 is used by ECR layer pulls, Loki chunks, and Tempo blocks — so the gateway endpoints carry a genuinely large share of this project's traffic for free.
2. **Route everything else (ECR API, STS, Secrets Manager, SQS/SNS/EventBridge) through fck-nat.** At this traffic volume the egress is cents.
3. If you want the *learning experience* of interface endpoints, create them in **one AZ only**, behind a Terraform variable defaulting to `false`, and tear them down the same session:
   ```hcl
   variable "enable_interface_endpoints" {
     description = "COST: $7.30/mo per endpoint per AZ. Single-AZ, session-only."
     type        = bool
     default     = false
   }
   ```
4. Put a hard comment with the dollar figure next to every interface endpoint resource. Future-you will otherwise re-add them.

**Warning signs:**
`aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[?VpcEndpointType==\`Interface\`].[ServiceName,length(NetworkInterfaceIds)]' --output table` returns anything. Multiply rows × ENIs × $7.30 — that is your monthly bill from this line item alone.

**Phase to address:** Networking/VPC foundation phase, before EKS exists. This must be decided *before* the module is written, because "we already have endpoints, removing them feels like a regression" is a real psychological trap.

---

### Pitfall 2: Resources orphaned by `terraform destroy` 🔴

**What goes wrong:**
`terraform destroy` reports `Destroy complete! Resources: 87 destroyed.` and the bill keeps climbing. Terraform only destroys what is in *state*. Anything created by an in-cluster controller is invisible to it.

**The canonical offender list for EKS specifically:**

| Orphan | Created by | Why Terraform misses it | Cost if orphaned |
|---|---|---|---|
| **ALB / NLB** | AWS Load Balancer Controller (from an `Ingress`/`Service type=LoadBalancer`) | Not in TF state | **$16.43/mo each** |
| **Target Groups** | Same | Not in TF state | $0 but blocks SG/VPC deletion |
| **Controller-created Security Groups** | Same (`k8s-<ns>-<name>-<hash>`) | Not in TF state | $0 but **blocks VPC destroy** → cascading failure |
| **EBS volumes from PVCs** | EBS CSI driver | StorageClass `reclaimPolicy: Retain`, or namespace deleted before PVC finalizers ran | **$0.08/GB-mo forever** |
| **Karpenter EC2 instances** | Karpenter | Never in TF state | **the largest orphan risk — full instance price** |
| **Karpenter-created launch templates / instance profiles** | Karpenter | Not in TF state | $0 but clutters and blocks IAM deletes |
| **Leaked ENIs** | VPC CNI (`aws-node`) | Detached on node termination but sometimes stranded | $0 but **blocks subnet/SG/VPC destroy** |
| **CloudWatch log groups** | EKS control-plane logging, Container Insights, Lambda | Lambda/EKS create them implicitly; TF only knows explicit ones | ingestion + **Never Expire** storage |
| **RDS final snapshot** | Terraform itself (`skip_final_snapshot = false`) | Deliberate — it is *supposed* to survive | snapshot storage, forever |
| **ECR images** | CI pipeline | `aws_ecr_repository` without `force_delete = true` fails or leaves images | $0.10/GB-mo |
| **Elastic IPs** | fck-nat module / manual | Released only if in state | ~$3.65/mo each |
| **EventBridge rules → Karpenter SQS queue** | Karpenter CFN template if bootstrapped that way | Outside TF | $0 |

**Why it happens:**
The mental model "Terraform manages my infrastructure" is *false* the moment a Kubernetes controller with an IAM role exists. Argo CD, the ALB controller, Karpenter, and the EBS CSI driver are all **second infrastructure-provisioning systems running inside the first one's product.** Terraform has no visibility into them.

**How to avoid — the ordered teardown, not `terraform destroy` alone:**

`make down` must be a *sequence*, not a single command:

```makefile
down:
	# 1. Stop the GitOps engine from re-creating what we delete
	kubectl -n argocd patch application root --type merge \
	  -p '{"spec":{"syncPolicy":null}}' || true
	# 2. Delete workloads that own AWS resources, and WAIT for finalizers
	kubectl delete ingress --all -A --timeout=5m || true
	kubectl delete svc --all-namespaces \
	  --field-selector spec.type=LoadBalancer --timeout=5m || true
	kubectl delete pvc --all -A --timeout=5m || true
	# 3. Let Karpenter drain its own fleet (it holds a finalizer on each NodeClaim)
	kubectl delete nodepool --all --timeout=10m || true
	kubectl delete nodeclaim --all --timeout=10m || true
	# 4. Now Terraform, in reverse dependency order
	terraform -chdir=infra/apps    destroy -auto-approve
	terraform -chdir=infra/cluster destroy -auto-approve
	terraform -chdir=infra/network destroy -auto-approve
	# 5. Prove it
	./scripts/verify-teardown.sh
```

Additional hard requirements:
- **All StorageClasses must be `reclaimPolicy: Delete`** for this project. `Retain` is correct in production and catastrophic here. Assert it in CI with a Kyverno policy or a `conftest` test.
- **`skip_final_snapshot = true` and `deletion_protection = false` on RDS.** Restoring yesterday's cart data has zero learning value; paying for 40 abandoned snapshots has negative value. If you want the snapshot/restore *practice*, do it deliberately as a named exercise with an explicit cleanup step.
- **`force_delete = true` on ECR repositories**, plus a lifecycle policy (see Pitfall 6).
- **Tag everything** (see §1.4) — the sweep depends on it.

**Warning signs:**
- `terraform destroy` hangs >20 min on `aws_subnet` or `aws_security_group` → almost always a controller-created ENI/SG/ALB holding a dependency.
- Cost Explorer shows non-zero EC2 or ELB spend on a day you tore down.
- `kubectl get pvc` returns items with `Terminating` status that never clear (finalizer deadlock).

**Phase to address:** This must be **Phase 1**, built *before* the first Spring Boot service. `make up` / `make down` / `verify-teardown.sh` are the first deliverable, not the last. Building them last is the number-one way this project dies.

---

### Pitfall 3: You cannot trust Cost Explorer to tell you the teardown worked 🔴

**What goes wrong:**
The natural verification instinct — "check the bill tomorrow" — fails. Cost Explorer has **up to 24 hours of lag** and the Cost and Usage Report can lag longer. By the time an orphan shows up, it has been billing for a day and you have already context-switched away. Worse: a single orphaned ALB is ~$0.55/day, which is easy to miss inside normal noise until it has run for a month.

**Why it happens:**
People reach for the billing console because it is the authoritative source of truth about money. It is — but it is the *slowest* one.

**How to avoid — a layered verification approach.** Use all four; they fail differently:

**Layer 1 — Immediate, authoritative, in-band: the tag sweep.** This is the one that actually works.
Every resource gets `Project=eks-practice` via `default_tags` in the AWS provider:
```hcl
provider "aws" {
  default_tags {
    tags = {
      Project   = "eks-practice"
      ManagedBy = "terraform"
    }
  }
}
```
Then `scripts/verify-teardown.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"

echo "== Tagged resources still alive =="
aws resourcegroupstaggingapi get-resources \
  --region "$REGION" \
  --tag-filters Key=Project,Values=eks-practice \
  --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'

echo "== UNTAGGED blind spots (controller-created; tags depend on config) =="
aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n'
aws ec2 describe-instances --region "$REGION" \
  --filters Name=instance-state-name,Values=running,pending \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n'
aws ec2 describe-volumes --region "$REGION" \
  --filters Name=status,Values=available \
  --query 'Volumes[].VolumeId' --output text | tr '\t' '\n'
aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==null].AllocationId' --output text | tr '\t' '\n'
aws ec2 describe-network-interfaces --region "$REGION" \
  --filters Name=status,Values=available \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text | tr '\t' '\n'
aws eks list-clusters --region "$REGION" --query 'clusters' --output text
aws rds describe-db-instances --region "$REGION" \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
aws rds describe-db-snapshots --region "$REGION" --snapshot-type manual \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
aws elasticache describe-cache-clusters --region "$REGION" \
  --query 'CacheClusters[].CacheClusterId' --output text
aws ec2 describe-vpc-endpoints --region "$REGION" \
  --query 'VpcEndpoints[?VpcEndpointType==`Interface`].VpcEndpointId' --output text
aws logs describe-log-groups --region "$REGION" \
  --query 'logGroups[?retentionInDays==null].logGroupName' --output text | tr '\t' '\n'
```
**Critical caveat:** `resourcegroupstaggingapi` does **not** cover every service, and controller-created resources (ALBs, Karpenter instances) only carry your tags if you configured the controllers to propagate them. That is why the script has a second, untagged section that enumerates by API. Configure the propagation anyway:
- ALB controller: `--default-tags=Project=eks-practice` controller flag, or `alb.ingress.kubernetes.io/tags` annotation.
- Karpenter: `spec.template.metadata.labels` plus `EC2NodeClass.spec.tags`.

**Layer 2 — Same-session, catches what you forgot to enumerate:** exit `verify-teardown.sh` non-zero if anything is found and wire it into `make down` so a dirty teardown is *loud*.

**Layer 3 — Asynchronous safety net: AWS Budgets + Cost Anomaly Detection.**
- A **zero-spend-threshold Budget** at ~$5/month with alerts at 50/80/100% of *forecasted* spend.
- **Cost Anomaly Detection** with a monitor on the linked account and a **$1 absolute threshold**. The default thresholds are tuned for enterprise spend and will never fire at this scale — you must set it low manually.
- Budgets/anomaly alerts are also lagging, but they are the backstop for the case where your script has a blind spot.

**Layer 4 — Standing nuke script.** A `scripts/nuke.sh` that force-deletes by tag/VPC, for when an ordered teardown genuinely fails. Consider `aws-nuke` or `cloud-nuke` scoped tightly to the practice account. **Use a dedicated AWS account for this project** so a blunt nuke is safe — this is the single highest-leverage structural decision for teardown confidence.

**Warning signs:** you find yourself opening the billing console "just to check" more than once per session. That means you do not trust your script, which means the script is wrong.

**Phase to address:** Phase 1, alongside `make down`.

---

### Pitfall 4: CloudWatch Logs — infinite retention by default 🟠

**What goes wrong:**
Log groups created by EKS control-plane logging, Lambda, and any Container Insights experiment default to **retention = Never Expire**. They also usually outlive `terraform destroy` because they were created implicitly by the service, not by Terraform. Across many spin-up/tear-down cycles this becomes a monotonically growing storage charge that nobody ever looks at. EKS control-plane audit logging in particular is *verbose* — enabling all five log types on a chatty cluster can produce multiple GB/day at ~$0.50/GB ingestion.

**Why it happens:** Nobody sets retention because nothing forces them to. The default is the trap.

**How to avoid:**
- Declare every log group explicitly in Terraform with `retention_in_days = 1` (this is a daily-teardown practice cluster; 1 day is correct, not stingy).
- **Do not enable all five EKS control-plane log types by default.** Enable `api` + `audit` only during a session where you are specifically practising audit-log analysis, then turn them off. Make it a variable:
  ```hcl
  cluster_enabled_log_types = var.deep_debug ? ["api","audit","authenticator","controllerManager","scheduler"] : []
  ```
- For Lambda: pre-create `/aws/lambda/<name>` in Terraform with retention set, so Lambda adopts your group instead of creating an unmanaged one.
- **Ship application logs to Loki, not CloudWatch.** This is already the project's plan and is correct — reinforce it by having *zero* CloudWatch agents/Fluent Bit→CW in the cluster.
- Add the `retentionInDays==null` query (above) to the teardown verification.

**Warning signs:** `aws logs describe-log-groups --query 'logGroups[?retentionInDays==null]'` returns anything.

**Phase to address:** Phase 1 (Terraform foundation) + Observability phase.

---

### Pitfall 5: Route 53 hosted zones are not prorated 🟡

**What goes wrong:**
A hosted zone is charged **$0.50 at the time it is created and again on the first day of each subsequent month** — explicitly **not prorated** ([verified](https://aws.amazon.com/route53/pricing/)). On a daily create/destroy cycle, naively provisioning a hosted zone in Terraform costs **$0.50 per session**, i.e. ~$10/month for 20 sessions — twice the entire idle budget, for DNS you do not need.

**The saving grace (and the exact rule to encode):** a hosted zone **deleted within 12 hours of creation is not charged**. A same-day teardown discipline therefore makes zones free — but only if teardown genuinely happens within 12 hours. One forgotten overnight = $0.50.

**How to avoid:** PROJECT.md already puts custom domains out of scope — **keep it there**. Use the ALB's `*.elb.amazonaws.com` DNS name and CloudFront's `*.cloudfront.net`. If a zone is ever needed, treat the 12-hour window as a hard operational rule and surface it in `make up` output.

**Phase to address:** Networking phase (as a documented non-decision).

---

### Pitfall 6: ECR storage accumulation across rebuilds 🟡

**What goes wrong:** Every CI run pushes ~6 Spring Boot images. A JVM image with a full JDK base is 300–500 MB. Twenty sessions × 6 services × 1 tag = 120 images ≈ 40 GB ≈ **$4/month** — which alone consumes the entire idle budget. And ECR repos are among the most commonly orphaned resources because `aws_ecr_repository` defaults to `force_delete = false`, so destroy *fails* rather than cleaning up, and people then remove it from state.

**How to avoid:**
- `force_delete = true` on every `aws_ecr_repository`.
- An `aws_ecr_lifecycle_policy` keeping the **last 3 images** per repo, expiring untagged after 1 day.
- Use **jlink/jdeps-trimmed runtime images** or a distroless/Alpine JRE base to cut image size 3–5x. This also directly reduces **fck-nat egress and pod startup time** — a triple win worth the effort.
- Consider keeping ECR out of the daily teardown (it is the one stateful thing worth persisting between sessions, like S3 state), but *only* with the lifecycle policy in place.

**Phase to address:** CI/CD phase.

---

### Pitfall 7: Cross-AZ data transfer between pods 🟡

**What goes wrong:** $0.01/GB in each direction = **$0.02/GB for a round trip** between AZs. In a microservices mesh where `api-gateway → order → payment → inventory` hops are randomly scheduled across AZs, essentially *all* internal traffic is cross-AZ. Add Prometheus scraping every pod every 15s, Loki shipping every log line, and Tempo receiving every span — the observability stack is frequently the **largest cross-AZ talker in the cluster**, exceeding the application it monitors.

**Why it's underestimated:** it never appears as a line item you provisioned. It appears as "EC2-Other / DataTransfer-Regional-Bytes", which most people never drill into.

**How to avoid at this project's scale:**
- **Run single-AZ.** For a practice cluster with no availability requirement, constrain Karpenter and the node group to one AZ: `topology.kubernetes.io/zone In [us-east-1a]`. This eliminates the charge entirely and halves the public-IPv4 count on the ALB. Keep the *subnets* multi-AZ (the ALB and EKS control plane require ≥2 AZs) but put all *compute* in one.
- Practice multi-AZ topology spreading as a **deliberate, time-boxed exercise**, not as the default posture.
- If multi-AZ: use `topologyAwareHints` / `trafficDistribution: PreferClose` on Services, and set Prometheus `scrape_interval: 30s` or `60s` (see §5).

**Warning signs:** Cost Explorer grouped by `Usage Type` shows `DataTransfer-Regional-Bytes` as a top-3 line.

**Phase to address:** Networking phase (AZ strategy), revisited in Observability phase.

---

### Pitfall 8: The horror stories — what actually causes the four-figure bills

These are the recurring patterns in publicly reported learner-bill incidents. **Confidence: MEDIUM** — these are synthesized from widely-reported community patterns, not from a single verified post-mortem; treat as a threat model rather than citation.

| Pattern | Mechanism | Typical damage |
|---|---|---|
| **Cluster left up over a holiday** | $0.10/hr control plane + Spot nodes + ALB + RDS. Nothing failed — they just forgot. | $150–$400 for 2–4 weeks |
| **`terraform destroy` "succeeded" but left NAT Gateways** | NAT in a module that errored mid-destroy; state showed clean. $32.85/mo each × 3 AZs. | ~$100/month |
| **Autoscaler + crashlooping workload** | A pod that OOMs and restarts triggers scale-up; HPA/Karpenter provisions instances to satisfy pending pods that can *never* schedule successfully. Runs all night. | $50–$500/night |
| **Karpenter with no instance-type constraints** | A resource request typo (`memory: 64Gi` instead of `64Mi`) makes Karpenter faithfully provision an `r6i.8xlarge`. Karpenter is *working correctly*. | $2/hr, silently |
| **Orphaned ALBs from repeated Ingress experiments** | Each `kubectl apply` of a differently-named Ingress makes a new ALB; deleting the *namespace* without deleting Ingresses skips finalizers. | $16.43/mo × N |
| **No budget alarm, or alarm on the wrong email** | Budget configured but notifications never verified. | Unbounded |
| **Public S3/ECR egress or a crypto-mining compromise via leaked keys** | Long-lived access key in a public repo. | $1,000s in hours |

**The two structural defenses that actually work:**
1. **A dedicated AWS account** for this project, with a **zero-spend Budget** and **Cost Anomaly Detection at a $1 threshold**. Isolation makes both detection and nuking safe.
2. **A Karpenter NodePool resource limit** — a hard ceiling Karpenter physically cannot exceed:
   ```yaml
   spec:
     limits:
       cpu: "8"
       memory: 32Gi
   ```
   This is the single best line of YAML in the project. It converts the "crashlooping workload scales forever" horror story from a $500 night into a bounded, debuggable `NodePool limit exceeded` event.
3. Pair it with an **EC2 instance-type allowlist** so a units typo cannot summon an `8xlarge`:
   ```yaml
   - key: node.kubernetes.io/instance-type
     operator: In
     values: ["t3a.medium","t3a.large","m6a.large","m6a.xlarge","m7g.large"]
   ```

**Phase to address:** Phase 0 (account + budget) and the Karpenter phase.

---

# 2. Terraform Destroy / Recreate

### Pitfall 9: The Kubernetes provider cannot reach a cluster that no longer exists 🔴

**What goes wrong:**
You run `terraform destroy`. Terraform destroys the EKS cluster. Then it tries to destroy a `kubernetes_manifest`, `helm_release`, or `kubectl_manifest` resource that is still in state and fails with:
```
Error: Get "https://XXXX.gr7.us-east-1.eks.amazonaws.com/api/v1/namespaces/argocd":
dial tcp: lookup XXXX.gr7.us-east-1.eks.amazonaws.com: no such host
```
Now destroy is **wedged**: Terraform cannot delete the Helm releases (no API server), and it will not proceed past them. Meanwhile the VPC, ALBs, and possibly nodes are still billing. The usual panic move is `terraform state rm` in a loop, which orphans everything it touches.

**Why it happens:**
The Kubernetes/Helm providers are configured with attributes from the `aws_eks_cluster` resource. Terraform providers are configured **once, at the start of the run** — so the provider either (a) captured a valid endpoint and later finds it gone, or (b) on a *fresh* apply, cannot be configured at all because the cluster doesn't exist yet (the mirror-image "provider configuration depends on a resource that doesn't exist" problem). Destroy ordering within a single graph is also not reliably "all k8s things before the cluster" when data sources are involved. This is a **known, structural limitation** of mixing the two providers in one state, not a bug you can configure away.

**How to avoid — split the state. This is the most important structural decision in the Terraform layer.**

```
infra/
  bootstrap/   # S3 state bucket + DynamoDB lock table. Created once, NEVER destroyed.
  network/     # VPC, subnets, route tables, fck-nat, gateway endpoints, SGs
  cluster/     # EKS control plane, managed node group, IRSA/Pod Identity, Karpenter IAM+SQS
  addons/      # Helm: Karpenter, ALB controller, EBS CSI, ESO, Argo CD  ← k8s/helm providers ONLY here
```
- `network` and `cluster` use **only** the AWS provider. `addons` uses the Kubernetes/Helm providers, reading cluster details from `terraform_remote_state` or `data "aws_eks_cluster"`.
- Destroy strictly in reverse: `addons` → `cluster` → `network`. Now the k8s provider is never asked to talk to a cluster that a *later step in the same graph* deleted.
- Configure the providers with `exec` credentials so tokens are never stale:
  ```hcl
  provider "kubernetes" {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
  ```
  Avoid `data "aws_eks_cluster_auth"` — its token expires in 15 minutes and a long apply will fail mid-run with `Unauthorized`, which is a separate maddening failure.
- **Prefer Argo CD over Terraform for in-cluster resources.** Terraform should install exactly one thing via Helm — Argo CD itself (plus the CRD-owning controllers that must exist before Argo, i.e. Karpenter and the ALB controller). Everything else is a `kubectl delete` away, which is far more reliable than a Terraform graph.

**Recovery when it happens anyway:**
```bash
# Remove ONLY the k8s-provider resources (they died with the cluster; nothing to orphan)
terraform state list | grep -E '^(helm_release|kubernetes_|kubectl_)' \
  | xargs -n1 terraform state rm
terraform destroy -auto-approve
```
This is safe *specifically* because those objects lived inside a cluster that is already gone. It is not safe for AWS resources.

**Warning signs:** `terraform plan` output where a `helm_release` shows changes on every run; any `data.aws_eks_cluster` referenced from a `provider` block in the same root module that creates the cluster.

**Phase to address:** Phase 1 — this is a layout decision, and retrofitting it later means a painful state migration.

---

### Pitfall 10: The spin-up/tear-down loop is too slow to be usable 🟠

**What goes wrong:** The loop is the product. If `make up` takes 45 minutes, sessions stop happening and the project dies of friction.

**Realistic timings (MEDIUM confidence — order-of-magnitude from documented service behaviour, validate empirically in Phase 1 and record actuals):**

| Resource | Create | Delete |
|---|---|---|
| VPC, subnets, route tables, SGs | ~1 min | ~2–5 min (ENI dependencies) |
| fck-nat EC2 instance | ~1 min | ~1 min |
| **EKS control plane** | **~10–15 min** | **~10 min** |
| Managed node group | ~3–5 min (after cluster) | ~5–10 min (drains) |
| Karpenter-provisioned nodes | ~40–60s | ~1 min |
| Helm addons + Argo CD sync | ~3–5 min | ~2 min |
| **RDS Postgres (single-AZ, t4g.micro)** | **~6–10 min** | **~5 min** (longer with final snapshot) |
| **ElastiCache Redis** | **~5–10 min** | **~5 min** |
| **CloudFront distribution** | **~5–15 min to deploy** | **~15–45 min** (must disable, wait for `Deployed`, then delete) |
| **Naive serial total** | **~45–60 min** | **~40–70 min** |

**CloudFront is the worst offender by a wide margin** and it is in the M1 scope for the frontend.

**How to make the loop fast enough to actually use:**
1. **Parallelize the long poles.** RDS, ElastiCache, and the EKS control plane have no dependency on each other. If they are in the same Terraform apply, Terraform parallelizes them automatically — a strong argument for *not* over-splitting `cluster`. Target: total `up` ≈ max(EKS 15min, RDS 10min) + addons 5min ≈ **~20 minutes**.
2. **Take CloudFront out of the daily loop entirely.** Options, best first:
   - Serve the SPA from the **ALB** (a second Ingress path) during normal sessions. Zero extra cost, zero extra time.
   - Or: make CloudFront + the S3 bucket a **long-lived, out-of-loop stack** (costs ~$0 idle: S3 storage pennies, CloudFront has no hourly charge). Practice CloudFront as a named exercise, not daily.
   - Never put CloudFront in the critical path of `make down`.
3. **Persist RDS as a snapshot, or skip RDS on most days.** Consider running Postgres **in-cluster** (a single StatefulSet, `emptyDir` or a small gp3 PVC) for day-to-day work, and switching to real RDS only for sessions where RDS itself is the subject. `order` doesn't care. This cuts ~10 min from up and ~5 from down, and removes a whole class of orphan risk. **Trade-off:** you lose IRSA-to-RDS-IAM-auth practice and parameter-group/backup practice — so keep a `var.use_rds` toggle rather than deleting the RDS module.
4. **Start the timer.** `make up` should print elapsed time and `make down` should too. Track it. If it regresses past 25 minutes, that is a defect.
5. **Use the wait time.** `make up` should be a backgroundable target that streams progress, not something you stare at.

**Phase to address:** Phase 1, with a stated non-functional requirement: **`make up` ≤ 20 min, `make down` ≤ 15 min.**

---

### Pitfall 11: Provider version drift breaks a rebuild three weeks later 🟡

**What goes wrong:** You destroy on Friday. You rebuild on the 20th of next month. `terraform init` pulls `hashicorp/aws` 6.x instead of 5.x, or the `terraform-aws-modules/eks` module has renamed variables, or Karpenter's chart moved from `v1beta1` to `v1` CRDs. The apply fails with a wall of unfamiliar errors and you have **no idea whether the problem is your code or the ecosystem**. For a project whose entire value proposition is "destroy and rebuild at will", this is an existential bug.

**How to avoid — pin at all four layers:**

```hcl
terraform {
  required_version = "~> 1.9.0"          # 1. Terraform CLI itself
  required_providers {
    aws        = { source = "hashicorp/aws",        version = "6.2.0" }  # 2. exact, not ~>
    kubernetes = { source = "hashicorp/kubernetes", version = "2.32.0" }
    helm       = { source = "hashicorp/helm",       version = "2.15.0" }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"                     # 3. exact module version
}
```
```yaml
# 4. Helm chart versions pinned in Argo CD Applications
spec:
  source:
    chart: karpenter
    targetRevision: "1.0.6"
```
Plus:
- **Commit `.terraform.lock.hcl`** and include all platforms: `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`.
- **Pin the EKS Kubernetes version explicitly** (`cluster_version = "1.31"`). Never let it float — and watch the **14-month standard-support window**, after which the control plane silently goes to **$0.60/hr, a 6x cost increase** ([verified](https://aws.amazon.com/eks/pricing/)). Set a calendar reminder.
- **Pin container base images by digest**, not tag, in Dockerfiles.
- Treat upgrades as a **deliberate exercise**: a `chore/bump-providers` branch, one layer at a time, with a full up/down cycle as the test. This is genuinely valuable day-2 practice — do it monthly on purpose rather than accidentally.

**Warning signs:** `.terraform.lock.hcl` in `.gitignore`. Any `version = "~> 5.0"` in a module you depend on for rebuild.

**Phase to address:** Phase 1, enforced by `tflint`/CI.

---

### Pitfall 12: Destroy dependency deadlocks 🟠

**What goes wrong:** Destroy hangs for 20+ minutes then fails with `DependencyViolation: The vpc has dependencies and cannot be deleted` or `resource sg-xxx has a dependent object`.

**The specific EKS causes, in order of frequency:**
1. **ALB-controller-created SGs and ALBs** still attached to subnets. Fix: delete Ingresses and wait for finalizers *before* Terraform runs (see Pitfall 2).
2. **Stranded VPC CNI ENIs** in `available` state. These usually clear within a few minutes; if not, delete explicitly.
3. **Karpenter nodes** still running because the NodePool wasn't deleted — Karpenter holds a finalizer on NodeClaims specifically so it can clean up EC2. If you delete the Karpenter *deployment* before the NodePools, **the finalizers can never be removed** and you get stuck NodeClaims *and* orphaned instances. **Order matters: delete NodePools → wait → then uninstall Karpenter.**
4. **EKS-managed cluster security group** referenced by controller-created SGs.
5. **PVC finalizers** blocking namespace deletion; the namespace is stuck `Terminating` forever.

**How to avoid:** the ordered `make down` in Pitfall 2, plus `terraform destroy -parallelism=30` for speed and a `timeout` wrapper that escalates to `nuke.sh` rather than leaving you wedged.

**Phase to address:** Phase 1.

---

# 3. Karpenter + Spot

### Pitfall 13: Consolidation thrashing — the defaults are aggressive 🟠

**What goes wrong:** Pods restart constantly. Nodes come and go every few minutes. Prometheus loses scrape targets, Argo CD shows `Progressing` forever, and traces are full of connection resets — and you spend an afternoon debugging the *application* when the problem is the node lifecycle.

**Why it happens — verified from [Karpenter docs](https://karpenter.sh/docs/concepts/disruption/):** if the `disruption` block is unset, Karpenter defaults to:
```yaml
consolidationPolicy: WhenEmptyOrUnderutilized
consolidateAfter: 0s
```
`WhenEmptyOrUnderutilized` means *any* node that can be removed or replaced to reduce cost is a candidate, and `0s` means it acts immediately. On a small cluster (2–3 nodes) where a single pod's scheduling changes the bin-packing calculus, this produces continuous churn. Karpenter resets the `consolidateAfter` timer whenever a pod is added or removed from a node — so a cluster with an HPA-scaled `catalog` service can oscillate indefinitely.

**How to avoid:**
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m          # give the cluster time to settle
    budgets:
      - nodes: "1"                # never disrupt more than one node at a time
      - nodes: "0"                # and never during your working hours, if you want quiet
        schedule: "0 9 * * mon-fri"
        duration: 8h
  limits:
    cpu: "8"
    memory: 32Gi
  template:
    spec:
      expireAfter: 720h
      terminationGracePeriod: 5m
```
Note the newer **`Balanced`** consolidation policy (also documented upstream) — "nodes where the cost savings outweigh the disruption to running pods." For a small practice cluster, `Balanced` with `consolidateAfter: 5m` is arguably the better default than `WhenEmptyOrUnderutilized`. **Verify it exists in your pinned Karpenter version before relying on it.**

**Warning signs:** `kubectl get nodeclaims -w` shows creation/deletion more than a couple of times per hour at steady state. `kubectl get events -A --field-selector reason=DisruptionBlocked`.

**Phase to address:** Karpenter phase.

---

### Pitfall 14: `expireAfter` without `terminationGracePeriod` strands partially-drained nodes 🟡

**What goes wrong (verified upstream):** Expiration is a **forceful** disruption — it begins draining as soon as the NodeClaim's lifetime exceeds `expireAfter` (default **720h**). But if a pod has a blocking PDB or the `karpenter.sh/do-not-disrupt` annotation, the drain cannot complete. Without `terminationGracePeriod`, the node sits **partially drained, cordoned, and still billing indefinitely**, requiring manual intervention. Karpenter's own docs explicitly warn about this.

Two more verified subtleties worth knowing:
- `expireAfter` is a **maximum**, not a minimum — drift or consolidation can kill a node much earlier, so don't use it to reason about node age.
- Changing `spec.template.spec.expireAfter` or `terminationGracePeriod` on a NodePool **does not** update existing NodeClaims; it induces **drift**, and the replacements get the new value. So a config change triggers a rolling node replacement — surprising if you expected an in-place update.
- Max node lifetime = `expireAfter` **+** `terminationGracePeriod`, not `expireAfter`.
- If a pod's `terminationGracePeriodSeconds` exceeds the Node's `terminationGracePeriod`, **the node's value wins** and the pod is deleted as soon as the drain starts.

**How to avoid:** always set both. `terminationGracePeriod: 5m` is a sane ceiling here. For a cluster destroyed daily, `expireAfter` barely matters — set it to `720h` and rely on the daily teardown.

**Phase to address:** Karpenter phase.

---

### Pitfall 15: Spot interruption handling done wrong 🟠

**What goes wrong:** Spot reclaims a node. Requests 500. Orders get stuck mid-saga. You conclude "Spot is unreliable" when in fact you never wired up the handling.

**The four things that must all be true:**

1. **The interruption queue must exist and be wired.** Verified: Karpenter requires an **SQS queue plus EventBridge rules** forwarding Spot Interruption Warnings, Rebalance Recommendations, Instance State-change, and Scheduled Change events, and Karpenter must be started with `--interruption-queue=<name>`. **Provision the SQS queue and EventBridge rules in Terraform**, not via the upstream CloudFormation template — otherwise they are orphaned by `terraform destroy` (an entry on the Pitfall-2 list). Without this, Karpenter falls back to the 2-minute EC2 notice with no proactive replacement, and you lose most of your grace window.
   - Verify: `kubectl -n kube-system logs deploy/karpenter | grep -i interruption` should show the queue being polled, not `interruption queue not configured`.
   - Note: instance **status checks** (unhealthy/scheduled-maintenance) work via `ec2:DescribeInstanceStatus` *without* the queue — do not mistake those working for the queue working.
2. **PodDisruptionBudgets on every Deployment.** `minAvailable: 1` for singletons is a **trap** — with 1 replica it blocks all voluntary disruption forever. Use `maxUnavailable: 1` for singletons, or run 2 replicas with `minAvailable: 1`. Given the budget, 2 replicas of a 256Mi Spring Boot service is affordable and is the correct answer for the saga-critical services (`order`, `payment-sim`, `inventory`).
3. **`terminationGracePeriodSeconds` tuned below the Spot window.** Spot gives **2 minutes**. The full chain is: interruption notice → Karpenter taints/cordons → pod gets `SIGTERM` → `preStop` → app drains → `SIGKILL`. Budget it: `terminationGracePeriodSeconds: 60` with a `preStop` sleep of 10–15s and a Spring Boot shutdown phase timeout of 30s. The default of 30s is usually *fine* for HTTP but too short for a service draining an SQS long-poll (see §7).
4. **Do not run the control-plane-critical addons on Spot.** Karpenter, CoreDNS, the ALB controller, and Argo CD's repo/application controllers must not all evaporate at once.

**Warning signs:** `kubectl get events -A | grep -i 'Spot\|Rebalance'` shows interruptions but no corresponding `NodeClaim` being created ahead of time.

**Phase to address:** Karpenter phase (infra) + Spring Boot phase (app-side draining). **This is also the highest-value chaos scenario** — the runbook for "Spot reclaim during an in-flight saga" is the single best exercise in the project.

---

### Pitfall 16: The Karpenter bootstrap chicken-and-egg 🟡

**What goes wrong:** Karpenter provisions nodes. Karpenter is a pod. Pods need nodes. If Karpenter is scheduled onto a node Karpenter itself manages, then:
- Karpenter consolidates its own node → Karpenter is evicted → no controller exists to provision its replacement → **cluster is permanently stuck with zero capacity**.
- Or on teardown: uninstalling Karpenter while NodePools exist leaves NodeClaims with unremovable finalizers *and* orphaned EC2 instances (see Pitfall 12).

**How to avoid — the standard and correct pattern:**
- A small **EKS-managed node group** (2 × `t3a.small`, **on-demand not Spot**) dedicated to system workloads: Karpenter, CoreDNS, the ALB controller, metrics-server, and Argo CD's controllers. Taint it `CriticalAddonsOnly=true:NoSchedule` and tolerate it from those workloads only.
  - Cost check: 2 × `t3a.small` on-demand ≈ $0.0376/hr — about 12% of the hourly budget. Acceptable, and it is what PROJECT.md already implies with "managed node groups on Spot" (change those two to on-demand).
  - Alternative to consider: 1 node instead of 2, accepting that a node failure requires `make down`/`make up`. On a practice cluster that is a fine trade and saves $0.019/hr.
- Exclude the managed node group's nodes from Karpenter by *not* labelling them with your NodePool's requirements — Karpenter only manages nodes it created (it tracks them via NodeClaims), so this is mostly automatic, but keep the taint as belt-and-braces against scheduling app pods there.
- Never let a Karpenter NodePool be able to satisfy Karpenter's own pod spec without the toleration.

**Warning signs:** `kubectl -n kube-system get pod -l app.kubernetes.io/name=karpenter -o wide` shows Karpenter on a node whose name matches the Karpenter naming pattern / has `karpenter.sh/nodepool` label.

**Phase to address:** EKS cluster phase — the managed node group must exist before Karpenter is installed.

---

### Pitfall 17: Pods stuck `Pending` with no clear signal 🟡

**What goes wrong:** A pod sits `Pending`. `kubectl describe pod` says `0/2 nodes are available` and nothing else useful. Karpenter *should* be provisioning but isn't, or provisions and the pod still doesn't schedule.

**The debugging ladder (in order — this is the runbook):**
```bash
# 1. What does the scheduler say?
kubectl describe pod <pod> | sed -n '/Events/,$p'

# 2. What does Karpenter say? This is the highest-signal source.
kubectl -n kube-system logs deploy/karpenter -f | jq -r 'select(.level!="DEBUG") | "\(.time) \(.level) \(.message) \(.error // "")"'

# 3. Did a NodeClaim get created, and is it stuck?
kubectl get nodeclaims -o wide
kubectl describe nodeclaim <nc>   # look at Conditions: Launched / Registered / Initialized

# 4. Common: NodePool limits hit
kubectl get nodepool -o jsonpath='{.items[*].status.resources}'

# 5. Common: no instance type satisfies the requirements
kubectl describe nodepool default | grep -A20 Requirements
```

**The six actual causes, ranked:**
1. **`limits` on the NodePool reached** — correct behaviour, looks like a bug. Karpenter logs it clearly if you read the logs.
2. **Overly narrow instance-type requirements + Spot capacity unavailable.** Requiring a single instance type in a single AZ on Spot is a recipe for `InsufficientInstanceCapacity`. **Always offer Karpenter ≥10 instance types** across at least 2 families/generations — this is the documented Spot best practice and directly improves both availability and the price-capacity-optimized selection. A `karpenter.k8s.aws/instance-family In [t3a,m6a,m7a,m6i]` + `instance-size In [medium,large,xlarge]` style constraint is far more robust than an explicit type list.
3. **Requests exceed anything in the allowlist** (the `64Gi` typo). Karpenter logs `no instance type satisfied resources`.
4. **Taints/tolerations mismatch** — the pod tolerates nothing but every NodePool taints.
5. **No IP addresses available** in the subnet (see §4.1) — the node *launches* but never becomes `Ready`, and the NodeClaim sits at `Registered=False`.
6. **EC2NodeClass `subnetSelectorTerms`/`securityGroupSelectorTerms` match nothing.** `kubectl describe ec2nodeclass` shows an empty `status.subnets`. Silent and common after a VPC rebuild changes tags.

**How to avoid proactively:** ship a Grafana panel on `karpenter_pods_pending` / `kube_pod_status_phase{phase="Pending"}` from day one, and an alert at >2 min pending. This is a genuine SRE habit worth building.

**Phase to address:** Karpenter phase + Observability phase. **Make this a written runbook** — it is one of the highest-frequency real-world EKS debugging tasks.

---

# 4. EKS Networking

### Pitfall 18: Missing or wrong subnet tags silently break the ALB controller 🟠

**What goes wrong:** You create an `Ingress`. Nothing happens. No ALB appears. `kubectl describe ingress` shows either nothing or `couldn't auto-discover subnets`. There is no error in a place you would think to look, and it can burn an entire session.

**The exact tags required (verified against [AWS LB Controller subnet discovery docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/)):**

| Tag | Value | On which subnets |
|---|---|---|
| `kubernetes.io/role/elb` | `1` | **Public** subnets (internet-facing ALB/NLB) |
| `kubernetes.io/role/internal-elb` | `1` | **Private** subnets (internal LB) |
| `kubernetes.io/cluster/<cluster-name>` | `owned` or `shared` | Both — subnets carrying this tag for the *current* cluster are **prioritized** during discovery |

**Why it happens:**
- The cluster name is embedded in a tag key. **Rename the cluster and every tag silently stops matching.** On a project that destroys and recreates daily, if the cluster name is ever randomized or suffixed, this breaks every time.
- The `terraform-aws-modules/vpc` module has `public_subnet_tags` / `private_subnet_tags` inputs, but people forget the cluster-specific one because it creates a **cross-module dependency** (VPC needs to know the cluster name). This is the real reason it gets skipped.
- Multiple clusters sharing a VPC without `shared` causes ambiguous discovery.

**How to avoid:**
- Make `cluster_name` a **deterministic local**, computed once and passed to both the network and cluster layers. Never random, never timestamped.
- Tag in the VPC module explicitly:
  ```hcl
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  ```
- **Belt and braces:** skip auto-discovery entirely with an explicit annotation, which removes the failure mode:
  ```yaml
  alb.ingress.kubernetes.io/subnets: subnet-aaa,subnet-bbb
  ```
  For a practice project, do it the discovery way *first* (learn it), then note the explicit form in the runbook.
- **Add a smoke test to `make up`**: apply a trivial Ingress and assert an ALB DNS name appears within 3 minutes. Fail the up if not.

**Warning signs:**
```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller | grep -i 'subnet\|discover'
kubectl get ingress -A -o wide   # ADDRESS column empty after 3 min = broken
```

**Phase to address:** Networking phase (tags) verified in the EKS/ingress phase.

---

### Pitfall 19: VPC CNI IP exhaustion and prefix-delegation fragmentation 🟢→🟠

**What goes wrong:** Each pod consumes a **real VPC IP** from the node's subnet. Nodes pre-allocate a *warm pool* of IPs, so a 3-node cluster can hold 50+ IPs even with 15 pods running. In a `/24` private subnet (251 usable), a handful of nodes plus the observability stack plus HPA scale-up will hit the ceiling. Symptom: nodes join but pods stay `ContainerCreating` with `failed to assign an IP address to container`.

At *this* project's scale (2–3 nodes, ~30 pods) this is genuinely unlikely — which is exactly why it will bite during a load-test or HPA chaos exercise, when the subnet is smallest relative to demand.

**Prefix delegation specifics (verified):** with `ENABLE_PREFIX_DELEGATION=true`, the CNI allocates **/28 prefixes** (16 IPs) per ENI instead of individual secondary IPs. This dramatically increases pod density and has **the best node launch time** per AWS. The catches:
- A **/28 must be contiguous and unfragmented**. A long-lived, churned subnet fragments and prefix allocation starts failing even though free IPs exist — the confusing failure is "I have 100 free IPs but can't allocate a prefix." *A daily-destroyed VPC is naturally immune to this* — a rare case where the teardown discipline is a defense.
- Default `max-pods` is **110**; prefix delegation lets you raise it, but you must update the node's `max-pods` (via launch-template bootstrap args) or you gain nothing.
- Mixing prefix-mode and secondary-IP-mode nodes in one cluster causes **inconsistent advertised capacity** — AWS recommends new node groups rather than rolling replacement when migrating.
- You cannot downgrade the CNI below 1.9.0/1.10.1 afterwards without removing all nodes.

**How to avoid:**
- **Size private subnets `/20` (4,091 usable) each.** IPv4 space inside your own VPC is free; there is no reason to be frugal. Use a `10.0.0.0/16` VPC with `/20` privates and `/24` publics. This makes the entire class of problem disappear.
- Enable prefix delegation from day one (the daily rebuild means no fragmentation risk) and set `WARM_PREFIX_TARGET=1` to avoid over-allocating on a tiny cluster.
- Practice the *failure* deliberately: a chaos scenario that provisions into an intentionally tiny `/26` subnet and makes you debug `ContainerCreating`. High learning value, zero risk.

**Warning signs:** `kubectl -n kube-system logs ds/aws-node | grep -i 'no available IP'`; `aws ec2 describe-subnets --query 'Subnets[].[SubnetId,AvailableIpAddressCount]'` trending toward zero.

**Phase to address:** Networking phase (subnet sizing — irreversible without a VPC rebuild, so get it right first).

---

### Pitfall 20: NetworkPolicy and security-group changes break DNS and metrics in non-obvious ways 🟠

**What goes wrong:** You apply a default-deny NetworkPolicy to enforce zero-trust (an explicit M1 requirement). Within minutes, **everything breaks in ways that look like application bugs**: services can't resolve each other, Prometheus shows all targets down, Argo CD can't reach the Kubernetes API.

**The specific, repeatable mistakes:**
1. **Default-deny egress without allowing DNS.** CoreDNS lives in `kube-system` on **UDP and TCP port 53**. Almost everyone allows UDP and forgets TCP, which breaks large responses and some resolvers intermittently — the worst kind of bug. Every namespace needs:
   ```yaml
   egress:
   - to:
     - namespaceSelector:
         matchLabels: { kubernetes.io/metadata.name: kube-system }
       podSelector:
         matchLabels: { k8s-app: kube-dns }
     ports:
     - { protocol: UDP, port: 53 }
     - { protocol: TCP, port: 53 }
   ```
2. **Forgetting Prometheus ingress.** Default-deny *ingress* on app namespaces blocks Prometheus's scrape to `/actuator/prometheus`. Targets go `context deadline exceeded` and it looks like the app is slow. Allow ingress from the monitoring namespace on the metrics port.
3. **The VPC CNI does not enforce NetworkPolicy by default.** You must enable it (`ENABLE_NETWORK_POLICY=true` on the `vpc-cni` addon, VPC CNI ≥1.14) or install Calico/Cilium. **The dangerous version of this bug is the inverse:** you apply policies, nothing breaks, and you believe zero-trust is working when **nothing is being enforced at all.** Always verify with a negative test.
4. **Security groups vs NetworkPolicies confusion.** SGs are node/ENI-level; NetworkPolicies are pod-level. A pod-to-RDS connection is governed by the *node's* SG (unless using Security Groups for Pods), so a NetworkPolicy alone will not stop it, and an SG rule alone will not stop pod-to-pod.
5. **Egress to AWS APIs.** Default-deny egress blocks pods reaching STS/SQS/Secrets Manager via fck-nat. You need an egress rule to `0.0.0.0/0` minus the cluster CIDR, or to the fck-nat ENI.

**How to avoid:** roll out NetworkPolicy **namespace by namespace, in audit mode first**. Write a `scripts/netpol-test.sh` that asserts (a) a pod in `apps` **can** resolve DNS and reach `order`, and (b) a pod in `default` **cannot** reach `order`. Run it in `make up`'s smoke test. Without the negative assertion you have no evidence enforcement is on.

**Phase to address:** Security phase — but **after** observability is working, because debugging NetworkPolicy without metrics and logs is miserable.

---

### Pitfall 21: CoreDNS on a small cluster 🟡

**What goes wrong:** Intermittent `UnknownHostException` in Spring Boot services, 5-second latency spikes, and traces with long unexplained gaps.

**The specific causes on a 2–3 node cluster:**
- **CoreDNS defaults to 2 replicas with anti-affinity.** On a 1-node system pool one replica is permanently `Pending`, halving capacity, and on a node disruption you can lose DNS entirely for ~30s.
- **No PDB / no topology spread** means consolidation can evict both replicas at once.
- **The `ndots:5` + search-domain amplification:** every external lookup (e.g. `sqs.us-east-1.amazonaws.com`) generates 4–5 failed queries before the correct one. With a JVM doing frequent AWS SDK calls this is a lot of needless query volume through 2 small CoreDNS pods. Fix per-pod:
  ```yaml
  dnsConfig:
    options: [{ name: ndots, value: "2" }]
  ```
- **JVM DNS caching** is the opposite problem: the JVM historically caches DNS **forever** (`networkaddress.cache.ttl=-1` under a SecurityManager). If an ALB or RDS endpoint IP changes, the JVM never notices. Set `-Dnetworkaddress.cache.ttl=30` explicitly — this matters for RDS failover and for anything behind a changing LB.
- Consider **NodeLocal DNSCache** if you see DNS latency; it is also a good learning exercise, though arguably over-engineering at 3 nodes.

**Warning signs:** `kubectl -n kube-system logs deploy/coredns | grep -i 'SERVFAIL\|i/o timeout'`; the `coredns_dns_request_duration_seconds` p99 in Grafana; `kubectl get pod -n kube-system -l k8s-app=kube-dns -o wide` showing `Pending`.

**Phase to address:** EKS cluster phase (CoreDNS sizing/PDB) + Spring Boot phase (`ndots`, JVM DNS TTL).

---

# 5. Observability on a Small Cluster

### Pitfall 22: The observability stack eats the cluster 🔴

**What goes wrong:** You install `kube-prometheus-stack` + Loki + Tempo + Grafana with default Helm values. Then your application pods start getting `OOMKilled`, Karpenter provisions more nodes, your hourly cost doubles, and you spend a week debugging "flaky services." The actual cause is that **the monitoring stack is consuming more memory than everything it monitors combined.**

This is the single most under-anticipated pitfall in this project, because the operator's mental model is "Prometheus is just a scraper."

**Concrete numbers (MEDIUM confidence — these are typical observed defaults; measure yours in Phase N and record actuals):**

| Component | Helm chart default request | Realistic usage on a 3-node cluster | Notes |
|---|---|---|---|
| Prometheus | often **no limit set**, 2Gi+ in practice | **1.5–3 GiB RSS** | Grows with active series; dominated by cardinality, not scrape count |
| Grafana | ~128Mi–256Mi | 200–400 MiB | Cheap |
| Alertmanager (×2 or ×3 HA!) | 32Mi each | 100 MiB total | **Set `replicas: 1`** |
| Loki (monolithic/SingleBinary) | ~256Mi | **500 MiB – 1.5 GiB** | Ingester memory scales with active streams |
| Tempo (monolithic) | ~256Mi | **500 MiB – 1 GiB** | Ingester buffers spans in memory |
| Promtail/Alloy DaemonSet | 128Mi × N nodes | 150 MiB × N | Per node |
| node-exporter + kube-state-metrics | ~100Mi | 200 MiB | Cheap |
| **Total** | — | **~3.5 – 6.5 GiB** | |

Against a budget of ~$0.16/hr ≈ 2–3 nodes ≈ **8–16 GiB total cluster memory**, the observability stack plausibly consumes **40–60% of the entire cluster** before a single Spring Boot service starts. And six JVMs at 512 MiB each is another 3 GiB. **The arithmetic does not close on the naive configuration.**

**How to avoid — this needs to be a deliberate, budgeted design, not a `helm install`:**

1. **Set explicit requests *and* limits on every observability component.** Untuned Prometheus with no limit will grow until it takes the node down with it.
2. **Shrink retention aggressively.** The cluster dies every day; there is no reason to retain more than a session:
   ```yaml
   prometheus:
     prometheusSpec:
       retention: 6h
       retentionSize: 2GB
       scrapeInterval: 60s        # default 30s; halves series ingestion
       resources:
         requests: { cpu: 200m, memory: 1Gi }
         limits:   { memory: 2Gi }
   ```
3. **Disable what you are not using.** `kube-prometheus-stack` ships ~30 default scrape jobs and hundreds of rules. On EKS the etcd/scheduler/controller-manager jobs **cannot work at all** (AWS doesn't expose them) and will sit permanently red, training you to ignore red — which is worse than having no dashboard. Disable them:
   ```yaml
   kubeEtcd: { enabled: false }
   kubeScheduler: { enabled: false }
   kubeControllerManager: { enabled: false }
   kubeProxy: { enabled: false }   # if using a CNI that replaces it
   ```
4. **Single replica everything.** `alertmanager.alertmanagerSpec.replicas: 1`, Loki `singleBinary` mode, Tempo monolithic.
5. **Sample traces.** 100% sampling on a chatty JVM mesh will dominate Tempo's memory. Use **parent-based + 10% head sampling** for normal operation, with an option to flip to 100% for a specific debugging session. Better: keep 100% head sampling but a **tail-sampling collector** that keeps all errors and slow traces — more work, far more instructive, and it is exactly the kind of thing certifications don't teach.
6. **Use S3 for Loki/Tempo object storage via the free S3 gateway endpoint.** Chunks/blocks go to S3 at ~$0.023/GB-mo and out of node memory/disk. Zero data-transfer cost via the gateway endpoint. Set S3 lifecycle rules to expire after 7 days.
7. **Give the observability stack its own Karpenter NodePool** with its own `limits`, so it physically cannot starve the application:
   ```yaml
   # NodePool: observability, limits: { cpu: "2", memory: 8Gi }, taint monitoring=true:NoSchedule
   ```
   This turns "observability starves the app" from a silent degradation into an explicit, visible `Pending` pod.
8. **Consider dropping one of the three signals for M1.** Metrics + traces (Prometheus + Tempo) deliver most of the learning; Loki can be added in a later phase. Sequencing them separately also lets you *measure* each one's footprint, which is itself a lesson.

**Warning signs:**
- `kubectl top pods -A --sort-by=memory | head -20` — if the top 5 are all in `monitoring`, you have the problem.
- `prometheus_tsdb_head_series` climbing without bound.
- Application pods with `OOMKilled` in `lastState` while `kubectl describe node` shows high memory pressure.

**Phase to address:** Observability phase — and **it must come after at least two services are running**, so you can size against real workload, not guesses.

---

### Pitfall 23: Prometheus data loss on every teardown 🟡

**What goes wrong:** Every `make down` destroys the entire metrics history. You cannot answer "was p99 latency worse this week than last week?", you cannot build a real SLO burn-rate alert (which needs 30 days of history), and you cannot do the *most valuable* observability exercise: comparing before/after a change.

**Is it acceptable?** **Mostly yes, but not entirely.** Within-session metrics are enough for 90% of the learning — debugging a live incident, watching an HPA scale, seeing a Spot reclaim. But the SLO/burn-rate requirement in PROJECT.md genuinely needs multi-day data to be meaningful, and losing it means you will practice *writing* burn-rate alerts without ever seeing one fire correctly.

**How to handle it — pick one:**
- **(Recommended) Loki/Tempo/Prometheus remote-write all to S3, and keep the S3 bucket out of the teardown.** With Thanos sidecar or Prometheus's native `--storage.tsdb` + Thanos, or simpler: use **Mimir/Thanos in "S3 as long-term storage" mode**. The bucket survives; each new cluster picks up the historical blocks. Cost: pennies. Complexity: real, but this is *exactly* the kind of thing worth practising.
- **(Simplest) Accept the loss, and simulate.** For the SLO exercise, generate synthetic historical data or compress the time window (define an SLO over 1 hour rather than 30 days). Honest and cheap; less realistic.
- **(Do not)** Try to keep an EBS PVC alive across teardowns. It is the exact orphan pattern from Pitfall 2 and it will cost you.

**Phase to address:** Observability phase. Decide explicitly — an undecided answer here means you will default to losing everything and be quietly frustrated.

---

### Pitfall 24: Cardinality explosion 🟡

**What goes wrong:** Prometheus memory doubles overnight and then OOMs. The cause is almost always a label with unbounded values.

**The specific offenders in this exact stack:**
- **Spring Boot `http.server.requests` with URI templating broken.** If a controller uses `@GetMapping("/orders/{id}")` correctly, Micrometer emits `uri="/orders/{id}"` — good. But **any 404, any unmapped path, or any manual `Timer` built from `request.getRequestURI()`** emits the raw path, creating one series per order ID. This is *the* classic Spring Boot cardinality bomb. Defend with:
  ```yaml
  management:
    metrics:
      tags: { application: ${spring.application.name} }
      enable:
        jvm.buffer: false
    observations:
      http.server.requests:
        # ensure unmapped requests are tagged uri="UNKNOWN", not the raw path
  ```
  and verify: `curl localhost:8080/actuator/prometheus | grep http_server_requests | wc -l` should be in the dozens, not thousands.
- **Trace/span/correlation IDs as metric labels.** Never. Those belong in logs and traces.
- **`user_id`, `order_id`, `session_id`, `cart_id`** as labels — in an e-commerce domain these are seductive and lethal.
- **Kubernetes pod name as a label on a high-churn deployment.** With Karpenter consolidation, pod names change constantly; every rollout multiplies series. `kube-state-metrics` does this by design, which is another reason to shorten retention.

**How to avoid:**
- Set a hard guard so a bad deploy cannot kill Prometheus:
  ```yaml
  prometheusSpec:
    enforcedSampleLimit: 5000       # per target
    enforcedLabelLimit: 30
    enforcedLabelValueLengthLimit: 128
  ```
- Add a `metric_relabel_configs` drop-list for known-noisy metrics.
- Build a Grafana panel on `topk(10, count by (__name__)({__name__=~".+"}))` and check it after every new service. Make it part of the "service is done" checklist.

**Warning signs:** `prometheus_tsdb_head_series` stepping up sharply right after a deploy. `scrape_samples_scraped` for one target far above others.

**Phase to address:** Observability phase, re-checked in every service phase.

---

### Pitfall 25: Traces silently split at the SQS/SNS boundary 🟠

**What goes wrong:** You build the flagship demo — "one trace following an order end-to-end across the full saga" — and it doesn't work. You get a trace for `api-gateway → order`, and a *separate, unlinked* trace for `inventory`. The saga is invisible exactly where it matters most. There is **no error**; the traces just don't join.

**Why it happens — this is the most common and most frustrating OTel failure:**
1. **Context does not propagate through a message broker automatically unless the instrumentation injects it into message attributes.** For SQS, the OTel Java agent's AWS SDK instrumentation can inject `traceparent` into the message's `MessageAttributes` — but **SQS allows only 10 message attributes**, and if your application already uses them, injection silently fails.
2. **SNS→SQS loses message attributes unless raw message delivery is configured correctly**, or the attributes get wrapped inside the SNS envelope body where the SQS consumer instrumentation doesn't look.
3. **EventBridge does not propagate message attributes at all** in the SQS sense — trace context must be carried **inside the event `detail` payload** and manually extracted. PROJECT.md uses EventBridge, so this *will* happen.
4. **Consumer-side span linking vs parenting.** OTel's SQS instrumentation often creates a span with a **Link** rather than a parent-child relationship (semantically correct for batch consumption), and **Tempo/Grafana do not render linked spans as one trace by default**. So the propagation actually worked and you still see two traces. This one wastes days.
5. **Async boundaries inside the JVM** — `@Async`, `CompletableFuture`, reactive chains, and thread pools lose the OTel `Context` unless the agent instruments the executor. The agent handles most cases, but **manually-created `ExecutorService`s and custom thread pools do not propagate**. Wrap them: `Context.taskWrapping(executor)`.
6. **Lambda cold-start / Python consumer** (`notification`) is a separate propagation story again — the AWS Lambda OTel layer extracts from different carriers.

**How to avoid:**
- **Make trace continuity an explicit, testable acceptance criterion**, not a hope. Write an E2E test that places an order and then asserts via the Tempo API that a single `traceID` contains spans from `api-gateway`, `order`, `payment-sim`, and `inventory`.
- **Put `traceparent` in your own event envelope.** Do not rely on broker-level propagation across EventBridge. Define a standard envelope:
  ```json
  { "eventId": "...", "eventType": "OrderCreated", "traceparent": "00-<trace>-<span>-01",
    "occurredAt": "...", "payload": { ... } }
  ```
  and inject/extract manually with `W3CTraceContextPropagator`. This is more code but it is **deterministic, debuggable, and broker-agnostic** — and it is what you'd do in production anyway. It also survives the outbox pattern, where the event is written to Postgres in one transaction and published later by a relay, at which point the original context is long gone (a subtlety most tutorials miss entirely).
- **In the outbox table, store the `traceparent` as a column.** The relay reads it and restores context when publishing. Without this, the outbox pattern *guarantees* trace breakage.
- Verify span **Links** vs **Parent** in the Tempo UI before concluding propagation is broken.

**Warning signs:** Two traces with adjacent timestamps and complementary service sets. `traceparent` absent from `kubectl exec`-dumped SQS messages.

**Phase to address:** Observability phase, with the envelope design decided in the **event-backbone phase** (before services are written — retrofitting an envelope across 6 services is painful).

---

### Pitfall 26: OTel Java agent startup overhead and sampling misconfiguration 🟡

**What goes wrong:**
- The OTel Java agent adds **1–3 seconds to JVM startup** (bytecode instrumentation at class load). On a Spring Boot app already taking 15–25s to start, this pushes past a default `startupProbe` and the pod is killed and restarted forever (see Pitfall 28).
- Memory: the agent adds **~50–100 MiB** of heap/metaspace. On a 512Mi container limit this is the difference between fine and `OOMKilled`.
- `OTEL_TRACES_SAMPLER=always_on` (or `parentbased_always_on`, the default) in a mesh that also scrapes `/actuator/health` produces enormous trace volume from health checks alone.
- Exporting to a collector that isn't up yet causes a **blocking export with retries** at startup in some configurations.

**How to avoid:**
```yaml
env:
  - { name: OTEL_TRACES_SAMPLER,      value: "parentbased_traceidratio" }
  - { name: OTEL_TRACES_SAMPLER_ARG,  value: "0.1" }
  - { name: OTEL_METRICS_EXPORTER,    value: "none" }   # Micrometer/Prometheus does metrics
  - { name: OTEL_LOGS_EXPORTER,       value: "none" }   # Promtail/Alloy does logs
  - { name: OTEL_EXPORTER_OTLP_PROTOCOL, value: "grpc" }
  - { name: OTEL_INSTRUMENTATION_COMMON_DEFAULT_ENABLED, value: "true" }
  - { name: OTEL_JAVA_DISABLED_RESOURCE_PROVIDERS, value: "io.opentelemetry.sdk.extension.resources.ProcessResourceProvider" }
```
- **Exclude health/actuator endpoints** from tracing (`OTEL_INSTRUMENTATION_HTTP_SERVER_EXPERIMENTAL_...` or a `Sampler` that drops `/actuator/*`).
- **Consider `micrometer-tracing-bridge-otel` instead of the agent** for Spring Boot 3.x — zero startup penalty, tighter Spring integration, and it works well with the manual envelope propagation recommended above. The agent's advantage is auto-instrumenting libraries you didn't write. **Recommendation: use the agent** (broader coverage is more instructive), but budget the startup time and memory.
- Set `startupProbe.failureThreshold` generously (see Pitfall 28).

**Phase to address:** Spring Boot service phase + Observability phase.

---

# 6. Spring Boot on Kubernetes

### Pitfall 27: `OOMKilled` despite a "correct" `-Xmx` 🟠

**What goes wrong:** You set `-Xmx512m` and `resources.limits.memory: 512Mi`. The pod gets `OOMKilled` (exit 137) anyway, usually under load or after a while. You increase `-Xmx`, it gets worse.

**Why it happens — the JVM's total footprint is much larger than the heap:**
```
Container RSS = Heap (-Xmx)
              + Metaspace (~80-150 MiB for Spring Boot)
              + Code cache (~50 MiB, JIT)
              + Thread stacks (1 MiB × ~50 threads = ~50 MiB)
              + GC overhead structures (~10% of heap for G1)
              + Direct/NIO buffers (Netty, gRPC, OTLP exporter — unbounded by default!)
              + OTel agent (~50-100 MiB)
              ≈ heap + 250-400 MiB
```
So `-Xmx512m` in a `512Mi` container needs ~**900Mi** and is killed. And critically: **the JVM heap is not the thing that gets killed** — the *cgroup* is. The JVM never sees an `OutOfMemoryError`; the kernel just kills the process, which is why the logs show nothing useful. That silence is the signature.

**How to avoid:**
1. **Use `-XX:MaxRAMPercentage`, not `-Xmx`.** It reads the cgroup limit, so it stays correct when you resize the container:
   ```
   JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=65.0 -XX:InitialRAMPercentage=65.0 \
     -XX:+UseSerialGC -XX:MaxMetaspaceSize=128m -XX:MaxDirectMemorySize=64m \
     -Dnetworkaddress.cache.ttl=30"
   ```
   **65%, not the commonly-cited 75%**, because of the OTel agent. Validate empirically with `jcmd <pid> VM.native_memory summary` (requires `-XX:NativeMemoryTracking=summary`) — this is a genuinely valuable skill to build.
2. **`-XX:+UseSerialGC` for small containers.** G1 (the default above ~1.8GB/2 CPU) spawns multiple GC threads and reserves significant native memory. For a 512Mi–1Gi single-CPU-ish service, SerialGC uses less memory and has comparable latency at this scale. **Verify the JVM isn't silently picking a different GC:** `java -XX:+PrintFlagsFinal -version | grep UseG1GC`.
3. **Set `requests == limits` for memory** (Guaranteed QoS). Bursty memory on a Spot-backed node with overcommit is how you get evicted at the worst moment.
4. **Cap direct memory explicitly** — `MaxDirectMemorySize` defaults to the heap size, so Netty/OTLP buffers can silently double your footprint.
5. **Realistic sizing for this stack:** a Spring Boot 3 service with OTel agent, JPA, and an AWS SDK client needs **~640Mi–768Mi** limit to be comfortable. Six of those is ~4 GiB. Add the ~4 GiB observability stack and you need ~8–10 GiB of cluster memory — which is 2 × `m6a.large` (8 GiB each). **Do this arithmetic before the roadmap commits to service count.**
6. **Consider Spring Boot AOT / native image (GraalVM) for one service** as a deliberate exercise: ~50 MiB RSS, ~50 ms startup. It would meaningfully change the cost profile and is excellent practice. Don't do all six — the build times are brutal.

**Warning signs:** `kubectl get pod -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'` = `OOMKilled` with `exitCode: 137` and **no stack trace in the logs**. `container_memory_working_set_bytes` approaching the limit asymptotically.

**Phase to address:** First Spring Boot service phase — establish the base image, `JAVA_TOOL_OPTIONS`, and resource template **once**, then reuse. Getting this right on service #1 saves it six times.

---

### Pitfall 28: Probes — slow startup and the liveness/readiness confusion 🟠

**What goes wrong — two distinct failures:**

**(a) The CrashLoop that isn't a crash.** Spring Boot + OTel agent takes 20–35s to start (worse on a cold Spot node pulling a 400 MiB image). A `livenessProbe` with the default `initialDelaySeconds: 0`, `periodSeconds: 10`, `failureThreshold: 3` kills the pod at **30 seconds** — before it ever finishes booting. The pod restarts, is killed again, and enters `CrashLoopBackOff`. The logs show a *normal, healthy* startup sequence cut off mid-way, which is deeply confusing.

**(b) Using liveness as readiness.** The classic: pointing `livenessProbe` at a health endpoint that checks *downstream dependencies* (`/actuator/health` includes DB, Redis, and SQS health indicators by default). Now when RDS has a brief blip, **every replica of every service fails liveness and Kubernetes restarts the entire fleet simultaneously** — converting a 5-second database hiccup into a multi-minute total outage, and preventing recovery because the restarts hammer the recovering database. This is a genuine production-outage pattern, not a theoretical one.

**How to avoid — use all three probes, correctly, with Spring Boot's dedicated endpoints:**
```yaml
management:
  endpoint.health.probes.enabled: true
  health.livenessState.enabled: true
  health.readinessState.enabled: true
  endpoints.web.exposure.include: health,info,prometheus
server:
  shutdown: graceful          # explicit — default was `immediate` before Spring Boot 3.5
spring:
  lifecycle.timeout-per-shutdown-phase: 25s
```
```yaml
startupProbe:                  # handles slow start; the other two don't run until this passes
  httpGet: { path: /actuator/health/liveness, port: 8080 }
  periodSeconds: 5
  failureThreshold: 24         # 120s budget — generous is correct here
readinessProbe:                # MAY check dependencies — removes pod from Service, no restart
  httpGet: { path: /actuator/health/readiness, port: 8080 }
  periodSeconds: 5
  failureThreshold: 3
livenessProbe:                 # MUST NOT check dependencies — only "is the JVM wedged?"
  httpGet: { path: /actuator/health/liveness, port: 8080 }
  periodSeconds: 10
  failureThreshold: 6
```
**The rule:** *liveness answers "should I be restarted?" — readiness answers "should I get traffic?"* A failing database is a readiness problem. Spring Boot's `livenessState` and `readinessState` groups implement exactly this split, and the `livenessState` group deliberately excludes dependency indicators. **Use them; do not point probes at bare `/actuator/health`.**

**Warning signs:** `kubectl describe pod` showing `Liveness probe failed` events during startup; `restartCount` climbing on a service whose logs show clean startups; all replicas restarting at the same second.

**Phase to address:** First Spring Boot service phase. **Also an excellent chaos scenario:** deliberately break RDS and verify that services go `NotReady` but do **not** restart.

---

### Pitfall 29: Graceful shutdown — the part everyone gets wrong even with `server.shutdown=graceful` 🟠

**What goes wrong:** You enable Spring Boot graceful shutdown (verified: [enabled by default in Spring Boot 3.5+](https://docs.spring.io/spring-boot/3.5/reference/web/graceful-shutdown.html); required `server.shutdown=graceful` in earlier versions — **check your version**). You still see 502s during every rolling deploy and every Spot reclaim.

**Why it still fails — the deregistration race.** The kill sequence is:
```
t=0    Pod marked Terminating
       ├─ kubelet sends SIGTERM  → app stops accepting connections IMMEDIATELY
       └─ Endpoints controller removes pod from EndpointSlice  (ASYNC, takes 1-10s)
           └─ ALB controller deregisters target from Target Group  (ANOTHER 10-30s+)
t=1s   App has stopped listening
t=1-30s ALB is STILL sending traffic to a socket that is closed → 502
```
Graceful shutdown solves *in-flight* requests. It does **not** solve *newly-arriving* requests during the deregistration window.

**How to fix — the `preStop` sleep. This is non-negotiable:**
```yaml
lifecycle:
  preStop:
    exec: { command: ["sh","-c","sleep 20"] }
terminationGracePeriodSeconds: 60      # must exceed preStop(20) + shutdown timeout(25) + margin
```
The pod keeps serving normally for 20s *after* being marked Terminating, giving the EndpointSlice and ALB deregistration time to complete. Only then does `SIGTERM` reach the JVM.

Also required:
- **ALB target group deregistration delay**: `alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30`.
- **Use `target-type: ip`** on the ALB Ingress so the ALB targets pods directly and respects pod readiness gates — with `instance` mode you get a second layer of kube-proxy indirection and worse drain behaviour.
- **Enable pod readiness gates** on the ALB controller so a rolling update waits for the new pod to actually be healthy *in the target group*, not just Ready in Kubernetes. This is the piece almost nobody configures and it is what makes zero-downtime deploys actually work.

**And for the async workers (`order`'s SQS consumers) this is a different problem entirely:**
- An SQS long-poll of 20s that is interrupted by `SIGTERM` can leave a message in-flight and unacknowledged. With a 30s visibility timeout it reappears and gets processed twice — which is fine **only if the consumer is idempotent** (see §7).
- Spring's `@PreDestroy` on the listener container should stop polling first, then drain in-flight messages. `SqsMessageListenerContainer` supports this; verify it, don't assume it.
- **Budget: `terminationGracePeriodSeconds` must exceed the SQS long-poll wait time.** 20s poll + 20s processing + 20s preStop = at least 70s. But **Spot only gives 120s total.** This is a real, tight constraint and a great thing to measure.

**Warning signs:** 502/504 counts in ALB metrics that correlate exactly with deploy timestamps. Duplicate order processing that correlates with pod restarts.

**Phase to address:** First Spring Boot service phase (template it), verified in the chaos phase with a load generator running during a rolling deploy — **"deploy under load with zero 5xx" is the single best acceptance test in this project.**

---

### Pitfall 30: RDS connection pool exhaustion 🟡

**What goes wrong:** `order` scales to 3 replicas. Half the requests fail with `HikariPool-1 - Connection is not available, request timed out after 30000ms`. RDS shows 100% connection utilization.

**The arithmetic everyone skips:** a `db.t4g.micro` Postgres has `max_connections ≈ LEAST({DBInstanceClassMemory/9531392}, 5000)` ≈ **~80–100 connections** at 1 GiB. AWS reserves ~3 for superuser. Now:
```
HikariCP default maximumPoolSize = 10
× 3 replicas of `order`                    = 30
+ 3 replicas × 10 for any other JPA service = 30
+ Flyway/Liquibase migration connections    = 2 per pod at startup (SPIKY!)
+ your psql session, Grafana datasource     = 5
                                            ≈ 67-90  ← at the ceiling
```
And the worst case is a **rolling deploy**: old pods still hold connections while new pods open theirs, **doubling demand for 30 seconds**. That is when it breaks — which is why it looks intermittent and random.

**How to avoid:**
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 5          # NOT the default 10
      minimum-idle: 1               # don't hold connections you aren't using
      connection-timeout: 3000      # fail fast; 30s default just queues requests
      max-lifetime: 600000          # 10 min, below any RDS/proxy idle timeout
      leak-detection-threshold: 20000
```
- **`maximum-pool-size: 5` is almost always more than enough.** The classic sizing formula is `connections ≈ (core_count × 2) + effective_spindle_count`; for a 1-vCPU RDS instance the *optimal* total across the whole fleet is single digits. More connections make it **slower**, not faster — a counterintuitive result worth experiencing firsthand.
- **Run migrations as a Kubernetes `Job`, not on application startup.** This removes the startup connection spike, removes the race where 3 replicas all try to migrate simultaneously, and is the correct production pattern anyway.
- Add a PDB and `maxSurge: 1` on the rolling update to bound the overlap.
- **Alert on `hikaricp_connections_pending > 0`** — Micrometer exposes this for free and it is the leading indicator.
- If you want the practice: **RDS Proxy** solves this properly — but it costs ~$0.015/vCPU-hr and is likely outside the budget. Note it as an M2 exercise.

**Phase to address:** `order` service phase; the Job-based migration pattern should be set in the first JPA service.

---

# 7. Saga / Event-Driven Correctness

> This is the project's stated centrepiece. These pitfalls are the *content* of the learning, not obstacles to it — but only if they're anticipated well enough to be designed against deliberately.

### Pitfall 31: Lost events without a transactional outbox 🟠

**What goes wrong:** `order` does:
```java
orderRepository.save(order);       // commits to Postgres
snsClient.publish(orderCreated);   // separate network call
```
Between those two lines the pod is Spot-reclaimed. The order exists in the database; the event never fires. `payment` and `inventory` never hear about it. The order sits `PENDING` forever with no error anywhere — **it is a silent, permanent inconsistency.** Inverting the order is worse (publish then save): now you charge for an order that doesn't exist.

**Why it happens:** the database transaction and the message publish are two separate systems with no shared commit. There is no fix at the call-site level; it requires a pattern.

**How to avoid — the transactional outbox (already in PROJECT.md, so the risk is doing it *subtly wrong*):**
```sql
CREATE TABLE outbox (
  id            UUID PRIMARY KEY,
  aggregate_id  UUID NOT NULL,
  event_type    TEXT NOT NULL,
  payload       JSONB NOT NULL,
  traceparent   TEXT,              -- see Pitfall 25
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at  TIMESTAMPTZ
);
CREATE INDEX ON outbox (published_at) WHERE published_at IS NULL;
```
The insert into `outbox` happens **in the same `@Transactional` method** as the order insert. A separate relay polls and publishes.

**The three ways people get the outbox wrong:**
1. **The relay is not concurrency-safe.** Two `order` replicas both poll the outbox and publish the same event twice. Fix: `SELECT ... FOR UPDATE SKIP LOCKED LIMIT 100` — this is the correct, elegant Postgres idiom and worth learning properly. (Or run the relay as a single-replica Deployment / leader-elected — simpler, and fine here.)
2. **The relay marks published *before* publishing** (loses events) or has no retry (same). Publish first, then mark — which yields **at-least-once**, which is why consumers must be idempotent.
3. **The outbox table is never pruned** and grows unbounded. Add a `DELETE FROM outbox WHERE published_at < now() - interval '1 day'` job.

**Worth noting:** the outbox gives at-least-once **publication**, never exactly-once. The whole point is that it converts "lost events" into "duplicate events", and duplicates are solved by Pitfall 32. Understanding that trade is the lesson.

**Warning signs:** orders stuck in an intermediate state with no corresponding event. `SELECT count(*) FROM outbox WHERE published_at IS NULL` growing.

**Phase to address:** `order` service phase.

---

### Pitfall 32: Non-idempotent consumers + SQS at-least-once = double charges 🟠

**What goes wrong:** Standard SQS guarantees **at-least-once** delivery. Duplicates happen for entirely normal reasons: visibility timeout expiry during a slow operation, a Spot reclaim mid-processing, the outbox relay retrying, SNS fan-out retries. `payment-sim` charges twice. `inventory` decrements stock twice. In an e-commerce domain these are the two worst possible bugs.

**Why it happens:** the happy path works perfectly in testing. Duplicates only appear under failure, which is exactly the condition this project is designed to create.

**How to avoid — idempotency must be designed in, per consumer:**
1. **Every event carries a stable, producer-generated `eventId`** (UUID, generated when the outbox row is written — **not** at publish time, or retries generate new IDs).
2. **Consumers record processed IDs and reject repeats atomically:**
   ```sql
   -- Postgres consumers (payment, order)
   INSERT INTO processed_events(event_id, processed_at) VALUES (?, now())
     ON CONFLICT (event_id) DO NOTHING;
   -- if 0 rows affected → already processed → ack and return
   ```
   ```
   // DynamoDB consumers (inventory) — conditional write
   PutItem with ConditionExpression: attribute_not_exists(eventId)
   ```
   The dedupe insert **must be in the same transaction as the business effect.** If they're separate, a crash between them reintroduces the bug.
3. **Prefer naturally idempotent operations where possible.** `SET status = 'PAID'` is idempotent; `balance = balance - 10` is not. In `inventory`, PROJECT.md already specifies **optimistic locking** on DynamoDB — combine the version check with the event ID check.
4. **Set the visibility timeout above the p99 processing time** (and use SQS's `ChangeMessageVisibility` heartbeat for long operations). A 30s default against a 45s p99 guarantees duplicates on every slow message.
5. **TTL the dedupe table** (DynamoDB TTL, or a Postgres prune job) — 7 days is plenty.

**Note the FIFO temptation:** SQS FIFO offers 5-minute deduplication and exactly-once *processing* within that window. It is **not a substitute** for application-level idempotency (the window is too short, throughput is lower, and it doesn't cover the outbox relay). Use standard SQS + idempotent consumers. Practising FIFO separately is worthwhile; relying on it is not.

**Warning signs:** stock counts drifting negative. Two `PaymentProcessed` events for one order. `ApproximateNumberOfMessagesNotVisible` staying high (slow consumers → visibility expiry → redelivery).

**Phase to address:** Event-backbone phase (envelope + `eventId` contract) then every consumer phase. **Chaos scenario: replay the same SQS message 5 times and assert the order total is unchanged.** That's the test that proves it.

---

### Pitfall 33: Compensating transactions that themselves fail 🟠

**What goes wrong:** Payment succeeds, inventory reservation fails, so the saga issues a `RefundPayment` compensation — and the refund call fails too (payment service is down, network partition, Spot reclaim). Now the customer is charged for an order that doesn't exist, and the saga orchestrator has **no state machine step for "compensation failed."** It either retries forever, silently gives up, or crashes.

**Why it happens:** tutorials show the happy path and the single-failure path. Nobody shows the compensation-fails path, because it has no clean automated answer.

**How to avoid:**
1. **Model the saga as an explicit, persisted state machine**, not as a chain of method calls. States: `PENDING → PAYMENT_PENDING → PAYMENT_OK → INVENTORY_PENDING → CONFIRMED`, plus `COMPENSATING`, `COMPENSATION_FAILED`, `CANCELLED`. Persist every transition in the same Postgres transaction as the outbox write. If `order` is Spot-reclaimed mid-saga, a new replica reads the state and resumes. **A saga with in-memory state does not survive a Spot reclaim** — and this project reclaims nodes constantly, so this is not theoretical.
2. **Compensations must be idempotent and retryable** (same rules as Pitfall 32 — refunds especially).
3. **Bound the retries, then escalate.** After N attempts, transition to `COMPENSATION_FAILED`, emit a **high-severity alert**, and stop. Manual intervention is the correct, honest answer — real payment systems do exactly this. Build the alert and a tiny admin endpoint to resolve it; that *is* the lesson.
4. **A reconciliation/sweeper job.** A scheduled task that finds sagas stuck in a non-terminal state for >5 minutes and re-drives or escalates them. **This is the single most valuable component in the whole distributed-systems part of the project** and the one most likely to be skipped. Every real event-driven system has one.
5. **Design compensations to be semantically honest.** You cannot "un-charge" a card; you issue a refund, which is a *new* transaction with its own failure modes. Model it as such.

**Warning signs:** a Grafana panel on `orders_by_state` showing a growing `COMPENSATING` bucket. Any saga row older than 10 minutes in a non-terminal state.

**Phase to address:** `order` saga phase. **Make `payment-sim`'s configurable failure injection able to fail the *refund* specifically**, not just the charge — otherwise this path is never exercised.

---

### Pitfall 34: Poison messages, missing DLQs, and unmonitored DLQs 🟠

**What goes wrong:**
- A malformed message throws on every attempt. Without a DLQ (redrive policy), SQS redelivers it until `MessageRetentionPeriod` expires — **14 days by default**. Meanwhile the consumer burns CPU, logs errors, and if processing is ordered-ish, blocks progress.
- With a DLQ but no alarm, messages land there and **nobody ever knows.** Orders silently vanish. This is worse than no DLQ, because it creates the *illusion* of handling.
- A retry policy with no backoff hammers a struggling downstream service into complete failure (retry storm).

**How to avoid:**
```hcl
resource "aws_sqs_queue" "order_events_dlq" {
  name                      = "order-events-dlq"
  message_retention_seconds = 1209600   # 14 days — you want time to investigate
}

resource "aws_sqs_queue" "order_events" {
  name                       = "order-events"
  visibility_timeout_seconds = 120      # > p99 processing time
  receive_wait_time_seconds  = 20       # long polling — cheaper and lower latency
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_events_dlq.arn
    maxReceiveCount     = 3             # NOT 1 (no retry) and NOT 100 (poison loop)
  })
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "order-events-dlq-not-empty"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.order_events_dlq.name }
}
```
- **A DLQ with ≥1 message must page you.** Alert on every DLQ, always, with no threshold above zero.
- **Scrape SQS metrics into Prometheus** (via `yet-another-cloudwatch-exporter` or a small custom exporter) so the DLQ depth is on the same Grafana dashboard as everything else. Relying on a CloudWatch alarm you'll never look at reproduces the original problem in a different console. *(Note: CloudWatch `GetMetricData` API calls cost ~$0.01/1000 — negligible at a 5-minute scrape interval, but don't scrape every 15s.)*
- **Distinguish retryable from non-retryable failures in code.** A malformed payload should go straight to the DLQ (`return` + explicit `DeleteMessage` after DLQ-ing, or throw a marked exception); only transient failures should consume retries. Blindly retrying a deserialization error 3 times is pure waste.
- **Build the redrive path**: a documented `aws sqs start-message-move-task` runbook to replay the DLQ after a fix. Untested redrive is not a recovery plan.

**Phase to address:** Event-backbone phase. **Chaos scenario: inject a malformed event and follow it to the DLQ and back.**

---

### Pitfall 35: Assuming ordering that standard SQS does not provide 🟡

**What goes wrong:** `OrderCreated` and `OrderCancelled` are published 50 ms apart. Standard SQS delivers them **out of order** (ordering is explicitly best-effort, not guaranteed). The consumer cancels an order that doesn't exist yet, throws, retries, eventually DLQs — or worse, processes the cancel, then processes the create, and ships a cancelled order. With SNS fan-out to multiple queues and multiple consumer replicas, reordering is not an edge case; it is routine.

**How to avoid — in priority order:**
1. **Design for commutativity/out-of-order tolerance.** The best answer is usually to not need ordering. Include a **version or sequence number** per aggregate in the event, and have consumers reject events older than the version they've already applied (the same optimistic-locking mechanism `inventory` already uses).
2. **State-machine guards on the consumer.** "Only transition `CONFIRMED → CANCELLED`" — an out-of-order cancel for a non-existent order becomes a no-op-and-retry rather than a crash.
3. **Carry full state, not deltas.** `OrderCancelled { orderId, finalState, version }` is far more reorder-tolerant than an implicit delta.
4. **FIFO queues with `MessageGroupId = orderId`** give per-order ordering. This is the "correct" answer and worth implementing for *one* queue as an exercise — but note FIFO limits throughput, doesn't work with all EventBridge targets, and you still need idempotency. Don't make it the default.
5. **Beware the SNS→SQS combination**: SNS is not ordered, and FIFO SNS topics only deliver to FIFO SQS queues. Mixing standard and FIFO silently loses the guarantee.

**Warning signs:** DLQ messages whose failure is "entity not found." Order states that regress.

**Phase to address:** Event-backbone phase (envelope must include `version`); enforced in each consumer.

---

# 8. Security

### Pitfall 36: GitHub Actions OIDC trust policy scoped too loosely 🟡 (likelihood) / 🔴 (damage)

**What goes wrong:** The trust policy is written as:
```json
"StringLike": { "token.actions.githubusercontent.com:sub": "repo:myorg/*" }
```
or worse, the `sub` condition is omitted entirely and only `aud` is checked. **With no `sub` condition, *anyone on GitHub* can assume your role** — they simply create a public repo with a workflow that requests an OIDC token for your `aud`. This is a complete account takeover via a single missing JSON key, and it is a well-documented real-world misconfiguration class.

**How to avoid:**
```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:myorg/microservices-demo:ref:refs/heads/main"
    }
  }
}
```
- **`StringEquals`, not `StringLike`.** If you must use `StringLike` (e.g. for PR workflows), the wildcard must never be at the start of the repo segment: `repo:myorg/microservices-demo:*` is acceptable; `repo:myorg/*` and `repo:*` are not.
- **`aud` must always be constrained** to `sts.amazonaws.com`.
- **Separate roles for plan and apply.** The PR-triggered `terraform plan` role gets read-only and can be scoped to `pull_request`; the `apply` role is scoped to `ref:refs/heads/main` only. This means a malicious PR cannot apply.
- **Use GitHub Environments** with required reviewers for the apply role, and include the environment in the `sub` claim: `repo:org/repo:environment:production`.
- **Set a short `max_session_duration`** (900s) — the workflow doesn't need an hour.
- Verify: `aws iam get-role --role-name gha-terraform --query 'Role.AssumeRolePolicyDocument'` and read the `sub` with suspicion. Add a `checkov`/`tfsec` CI rule for it.

**Phase to address:** CI/CD phase — **before** the first `terraform apply` from CI.

---

### Pitfall 37: Over-permissive IRSA roles and trust-policy mistakes 🟡

**What goes wrong — two symmetric failures:**

**(a) Too broad.** Every service gets `AmazonDynamoDBFullAccess` + `AmazonS3FullAccess` "just to get it working, I'll tighten it later." Later never comes. Now `catalog` (a read-only, internet-adjacent service) can delete the Terraform state bucket and drop the `inventory` table. On a practice project this is *the* pattern to break, because the entire point is to build production habits.

**(b) Broken/too-broad trust policy.** The IRSA trust policy uses `StringLike` with a wildcard on the service account:
```json
"oidc.eks...:sub": "system:serviceaccount:*:*"
```
Now **any pod in any namespace** can assume the role by creating a service account with the annotation. A compromised sidecar in `monitoring` gets your payment credentials.

The *breaking* version: `StringEquals` with the wrong namespace or a typo in the SA name gives `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity` — which is at least loud.

**How to avoid:**
```json
"Condition": {
  "StringEquals": {
    "oidc.eks.us-east-1.amazonaws.com/id/<ID>:aud": "sts.amazonaws.com",
    "oidc.eks.us-east-1.amazonaws.com/id/<ID>:sub": "system:serviceaccount:apps:catalog"
  }
}
```
- **One role per service.** Six services = six roles. Yes, it's more Terraform. That's the practice.
- **Scope resources, not just actions:** `dynamodb:GetItem` on `arn:aws:dynamodb:*:*:table/catalog` — not `Resource: "*"`.
- `catalog` gets `GetItem`/`Query`/`Scan` and **no write actions at all.** Verify by trying a write and confirming it fails — a negative test.
- **Strongly consider EKS Pod Identity over IRSA** for new work. It removes the OIDC-provider-per-cluster setup, which on a **daily-recreated cluster is a significant win**: IRSA trust policies embed the cluster's OIDC provider ID, which **changes every time you recreate the cluster**. That means either (a) your IAM roles must be created *after* the cluster in the same Terraform run, or (b) they break on every rebuild. Pod Identity's trust policy is static (`pods.eks.amazonaws.com`) and the association is a separate API call — much friendlier to this project's lifecycle. **This is a genuinely project-specific recommendation: use Pod Identity.** Practise IRSA once for the knowledge, then switch.
- Run **`aws iam generate-service-last-accessed-details`** or IAM Access Analyzer after a session to find unused permissions and tighten. That is a real day-2 skill.

**Warning signs:** any `"Resource": "*"` or `"Action": "*"` in the repo. Any `StringLike` in an IRSA trust policy. Grep for both in CI.

**Phase to address:** EKS cluster phase (the role pattern), each service phase (its specific policy).

---

### Pitfall 38: Secrets in Git, or "encrypted" Kubernetes Secrets 🟡

**What goes wrong:**
- `base64` is encoding, not encryption. A committed `Secret` manifest is a plaintext credential with an extra step, and Argo CD makes it *very* tempting to commit one "just for the dev database."
- Kubernetes Secrets are stored **unencrypted in etcd by default**. On EKS, AWS manages etcd and encrypts the volume, but **envelope encryption with a KMS key is a separate opt-in** — without it, any principal with `get secrets` cluster-wide reads everything.
- A secret committed and then deleted is **still in Git history forever.** Rotation is the only fix.
- Terraform writes secrets into **state in plaintext** — `aws_db_instance.password`, `random_password.result`. The state bucket is therefore a credential store and must be encrypted, versioned, and access-restricted.

**How to avoid:**
- PROJECT.md's choice of **External Secrets Operator + AWS Secrets Manager** is correct. Enforce it with a **Kyverno policy that rejects any `kind: Secret` not owned by ESO**:
  ```yaml
  # validate: Secret must have ownerReferences[].kind == ExternalSecret
  ```
  This converts a discipline into a guarantee.
- **`gitleaks` or `trufflehog` as a pre-commit hook AND a CI gate.** Pre-commit alone is bypassable with `--no-verify`.
- **Enable EKS envelope encryption** with a customer-managed KMS key (`encryption_config` in the cluster resource). Cost: $1/month per key — a real but acceptable line item. *Note: the daily teardown means either the key is out-of-loop (recommended, with `deletion_window_in_days = 7` awareness) or you pay $1 per creation.*
- **Never put secrets in Terraform variables or `.tfvars`.** Generate with `random_password` and write directly to Secrets Manager; have the app read from there. Accept that the value is in state and protect the state bucket accordingly (SSE-KMS, versioning, `BlockPublicAcls`, bucket policy denying non-TLS).
- **ESO-specific gotcha:** Secrets Manager charges **$0.40/secret/month** plus $0.05 per 10,000 API calls. Ten secrets = $4/month — **the entire idle budget.** Consolidate into **one or two JSON secrets** with multiple keys and use ESO's `dataFrom`/property extraction. Or use **SSM Parameter Store Standard parameters, which are free** — ESO supports it as a provider. **Recommendation: Parameter Store for everything except genuinely rotating credentials.**

**Phase to address:** Security phase, but the **ESO + Parameter Store decision must land before the first service needs a credential.**

---

### Pitfall 39: Kyverno/OPA policies that lock you out of your own cluster 🟡 (likelihood) / 🔴 (damage)

**What goes wrong:** You apply a cluster-wide `Enforce`-mode policy — "all pods must have resource limits", "all images must come from our ECR", "no `:latest` tags", "must run as non-root". Then:
- **`kube-system` is included**, so CoreDNS, `aws-node`, and `kube-proxy` can no longer be created. On the next node join, the CNI DaemonSet pod is **rejected**, the node never becomes Ready, and the cluster degrades to nothing. Karpenter tries to fix it by adding more nodes, which also fail. You now have a cluster that cannot schedule anything and **a bill that is climbing**.
- **Kyverno's own webhook fails closed.** With `failurePolicy: Fail` (the default for validating webhooks in many configs), if the Kyverno pods are evicted by a Spot reclaim and cannot be rescheduled — because the webhook that must approve them is down — **nothing can be created cluster-wide, including Kyverno itself.** This is a genuine, total, self-inflicted deadlock, and the only recovery is `kubectl delete validatingwebhookconfiguration` (if you still have API access) or rebuilding the cluster.
- A mutating policy that adds a default (e.g. injecting `securityContext`) makes Argo CD permanently `OutOfSync` (see Pitfall 41).

**How to avoid:**
1. **Always exclude system namespaces:**
   ```yaml
   spec:
     rules:
     - name: require-limits
       match:
         any: [{ resources: { kinds: [Pod] } }]
       exclude:
         any:
         - resources:
             namespaces: [kube-system, kyverno, karpenter, argocd, monitoring, kube-node-lease, kube-public]
   ```
2. **Start every policy in `validationFailureAction: Audit`.** Run a full session. Check `kubectl get polr -A` (policy reports) for what *would* have been blocked. Only then flip to `Enforce`. There is no excuse for going straight to Enforce.
3. **Set `failurePolicy: Ignore`** on your Kyverno webhook configuration for this project. In production, `Fail` is correct (a policy engine that can be bypassed by killing it is not a control). Here, availability of your own cluster matters more than the guarantee, and the *lesson* of experiencing both is available by toggling it deliberately.
4. **Run Kyverno on the on-demand system node group** with a PDB, so a Spot reclaim can't take it out.
5. **Keep `kubectl delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg` in the runbook**, at the top, in bold. You will need it.
6. **Spot-interruption interaction:** a Kyverno policy requiring an annotation that Karpenter's provisioned pods don't have will block node bootstrap. Test policies *with a Karpenter scale-up*, not just with `kubectl run`.

**Warning signs:** `kubectl -n kube-system get pods` showing `aws-node` or `coredns` missing/not being created; `kubectl get events -A | grep -i admission`; nodes stuck `NotReady` with no CNI pod.

**Phase to address:** Security phase — **late**, after everything else works, and **always Audit-first**. This is a strong argument for putting policy enforcement in its own phase near the end of M1.

---

### Pitfall 40: Public EKS API endpoint open to 0.0.0.0/0 🟢

**What goes wrong:** `endpoint_public_access = true` with `public_access_cidrs = ["0.0.0.0/0"]` (the default). The Kubernetes API server is reachable from the entire internet.

**Honest risk assessment:** this is **lower risk than it feels**. The API server still requires valid IAM-signed authentication; there is no anonymous access, and EKS doesn't expose an unauthenticated endpoint. The real risks are (a) exposure to any future auth bypass CVE, (b) credential-stuffing/enumeration noise, and (c) it means a leaked kubeconfig/IAM credential is immediately exploitable from anywhere.

**Why fully private is the wrong answer *here*:** a private-only endpoint requires a bastion, VPN, or SSM port-forwarding to use `kubectl` — which adds cost, adds `make up` time, and adds a failure mode to the loop that is the project's lifeblood. The cost/benefit does not favour it for a practice cluster with no real data.

**The right answer:**
```hcl
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["${chomp(data.http.my_ip.response_body)}/32"]
cluster_endpoint_private_access      = true
```
Fetch your current IP at apply time. This is nearly free, costs no time, and removes 99.9% of the exposure. Handle the "my IP changed" case gracefully (a `make refresh-ip` target).

**Additionally:**
- Enable **audit logging** during security-focused sessions only (see Pitfall 4 on cost).
- Practise **fully private + SSM Session Manager port-forward** as a deliberate one-session exercise. It's a genuinely useful skill and SSM avoids bastion cost.

**Phase to address:** EKS cluster phase.

---

# 9. GitOps / Argo CD

### Pitfall 41: Perpetual `OutOfSync` from mutating webhooks and defaulted fields 🟠

**What goes wrong:** An Application shows `OutOfSync` forever. Clicking Sync succeeds, and it immediately goes `OutOfSync` again. Argo CD burns CPU reconciling in a loop, alerts become noise, and — worst — **you stop trusting the sync status**, which destroys the entire value of GitOps.

**The specific causes in this stack:**
1. **Kyverno mutating policies** inject `securityContext`, labels, or `imagePullSecrets`. Git says one thing, the cluster says another, forever.
2. **Kubernetes API defaulting** — `protocol: TCP`, `terminationMessagePath`, `revisionHistoryLimit`, empty `creationTimestamp: null` in CRDs.
3. **HPA fighting the Deployment's `replicas`.** Git says `replicas: 2`, HPA scales to 4, Argo reverts to 2, HPA scales up again. **Classic and guaranteed** given PROJECT.md's HPA-scaled `catalog`.
4. **Metrics-server / VPA** mutating resource fields.
5. **CRD schema pruning** — Argo sends fields the CRD strips.
6. **The AWS Load Balancer Controller** adding finalizers and status to Ingress objects.

**How to avoid:**
```yaml
# For the HPA fight — the correct answer:
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers: ["/spec/replicas"]
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
    - ApplyOutOfSyncOnly=true
    - ServerSideApply=true        # respects other field managers; fixes most defaulting diffs
    - RespectIgnoreDifferences=true
```
- **`ServerSideApply=true` is the single highest-leverage setting** — it makes Argo a field manager that coexists with webhooks and controllers instead of fighting them.
- **Better than `ignoreDifferences` for replicas: omit `replicas` from the manifest entirely** when an HPA owns it. Then there is nothing to diff.
- Use `kubectl diff -f manifest.yaml` and Argo's own `App Diff` view to find the exact offending field rather than guessing.
- **Audit-mode your Kyverno mutations first** and make the mutation match what's in Git, rather than diverging from it.

**Warning signs:** `argocd_app_info{sync_status="OutOfSync"}` persistently > 0. Argo repo-server CPU pegged.

**Phase to address:** GitOps phase, revisited after Kyverno and HPA land.

---

### Pitfall 42: The Argo CD bootstrap problem, and rebootstrapping a cluster destroyed daily 🟠

**What goes wrong — this is the most project-specific pitfall in the document.** Argo CD deploys everything. But who deploys Argo CD? And on a cluster that is destroyed and recreated every single day, this question is asked **every session**, so any friction here is multiplied by every session you will ever run.

**The failure modes:**
1. **Terraform installs Argo via `helm_release`, then Argo manages itself** → the two fight (Pitfall 9 + Pitfall 43), and destroy wedges.
2. **Manual `kubectl apply` of Argo after every `make up`** → not reproducible, and the "single-command lifecycle" requirement in PROJECT.md is violated on day one.
3. **Argo comes up before the CRDs it needs exist** (Karpenter's NodePool CRD, the ALB controller's TargetGroupBinding), so the first sync fails with `unable to recognize kind`. Argo retries, but the Application shows `Unknown`/`Degraded` and you waste time.
4. **Argo's admin password / server certificate regenerate every rebuild**, so `argocd login` breaks and any bookmarked URL fails on certs.
5. **Argo tries to sync an `Ingress` before the ALB controller exists**, or an `ExternalSecret` before ESO's CRDs exist — **ordering matters and Argo doesn't infer it.**

**How to avoid — the layered bootstrap that actually works for this lifecycle:**

```
Terraform (`addons` layer) installs ONLY:
  1. Karpenter          (CRDs needed before anything schedules)
  2. AWS LB Controller  (CRDs needed for Ingress)
  3. EBS CSI driver     (EKS addon)
  4. External Secrets Operator (CRDs needed for every app)
  5. Argo CD            (helm_release, minimal values)
  6. ONE `kubernetes_manifest`: the "app-of-apps" root Application
                        ↓
Argo CD then owns EVERYTHING else, from Git, with sync waves.
```
Key details:
- **Use Argo CD sync waves** to enforce ordering — this is the mechanism that solves #3 and #5:
  ```yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-1"   # namespaces, CRDs
      # "0"  platform (monitoring, ESO ClusterSecretStore)
      # "1"  data-layer config
      # "2"  application services
      # "3"  ingress
  ```
- **Argo must NOT manage Argo** in this project. Self-management is elegant in a long-lived cluster and an active liability in one that's destroyed daily — it creates a destroy-order circularity and makes the Helm values the source of truth in two places. Let Terraform own Argo; let Argo own everything else. **Accept the small inconsistency for a large reliability win.**
- **Pin Argo's admin password deterministically** from Secrets Manager (via `argocd-secret`'s `admin.password` bcrypt hash) so `argocd login` works identically after every rebuild. Regenerating it each session is a small friction that compounds into real annoyance.
- **`make up` must end by waiting for Argo to be healthy and synced**, not by returning as soon as Terraform finishes:
  ```bash
  argocd app wait root --health --timeout 600
  kubectl -n argocd wait --for=condition=available deploy/argocd-server --timeout=5m
  ```
  Otherwise "up" is a lie and you start debugging a cluster that is still converging.
- **Disable Argo's Dex/SSO and notifications** — unused components, pure memory cost on a tiny cluster.
- **`make down` must first disable auto-sync on the root app** (Pitfall 2), or Argo will faithfully recreate the Ingresses you're deleting. This is a real and infuriating race.
- **Pin `targetRevision` to a tag or commit SHA, not `HEAD`**, for anything you want reproducible. `HEAD` means "the cluster I rebuild tomorrow is not the cluster I destroyed today," which quietly breaks the reproducibility premise of the entire project.

**Warning signs:** `make up` succeeds but `kubectl get pods -A` shows half the cluster missing. Argo Applications stuck `Unknown` with `unable to recognize kind`.

**Phase to address:** GitOps phase — and it should come **early**, right after the cluster, because every subsequent phase deploys through it.

---

### Pitfall 43: Terraform and Argo CD fighting over the same resources 🟡

**What goes wrong:** Terraform creates a `kubernetes_namespace` and Argo also manages it via a manifest in Git. Terraform's next `plan` wants to remove Argo's labels; Argo's next sync wants to remove Terraform's. Each `apply`/sync flips it. Or: Terraform creates a `helm_release` for `kube-prometheus-stack` and you later add an Argo Application for the same chart — now two controllers own the same release and Helm's release secret gets corrupted.

**How to avoid — one rule, no exceptions:**

> **Every Kubernetes object has exactly one owner: Terraform *or* Argo CD. Never both.**

Draw the line explicitly and write it in the repo README:

| Owned by Terraform | Owned by Argo CD |
|---|---|
| All AWS resources | All application manifests |
| EKS addons (`vpc-cni`, `coredns`, `kube-proxy`, `ebs-csi`) | Observability stack |
| Karpenter (chart), its IAM + SQS | **Karpenter NodePools / EC2NodeClass** (CRs, not the controller) |
| AWS LB Controller (chart) + IRSA | Ingresses, Services |
| ESO (chart) + IRSA | ClusterSecretStore, ExternalSecrets |
| Argo CD itself + the root Application | Everything else, including Kyverno + policies |

Note the split on Karpenter: Terraform owns the **controller and its AWS dependencies**; Argo owns the **NodePool custom resources**. This is deliberate — NodePool tuning is the thing you'll iterate on constantly, and GitOps iteration is much nicer than `terraform apply`. But it means `make down` must delete NodePools via `kubectl` (Pitfall 12), since Terraform doesn't know about them.

Also: **use distinct namespaces** for Terraform-owned vs Argo-owned things where possible, and set `argocd.argoproj.io/tracking-id` correctly so Argo's ownership is unambiguous.

**Warning signs:** a `terraform plan` that is never empty right after an apply. Helm releases with `pending-upgrade` status.

**Phase to address:** GitOps phase — the ownership table is a **deliverable**, written down before the first Argo Application.

---

# 10. Learning-Project-Specific Traps

> These have the highest likelihood of any category and the damage is total — the project is abandoned. They deserve the same seriousness as the cost pitfalls.

### Pitfall 44: "Infrastructure forever, never ship a feature" 🟠

**What goes wrong:** Three months in, the Terraform is beautiful, the Karpenter NodePools are elegantly tuned, and **not one HTTP request has ever traversed the system.** Motivation collapses because there's been no visible progress — only YAML. The project is abandoned with 8,000 lines of infrastructure code and zero learning about distributed systems, which was the stated centrepiece.

**Why it happens:** infrastructure work has *endless* legitimate depth. Every component can be improved. There is always another best practice. With no deadline (explicitly stated in PROJECT.md as a feature) there is no forcing function, and the highest-quality-feeling work is always "tighten the IAM policy" rather than "write a controller."

**How to avoid — this should shape the roadmap's phase ordering more than any other consideration:**
1. **Make Phase 2 or 3 a working end-to-end request.** Not a complete service — a **walking skeleton**: one `catalog` endpoint returning hardcoded JSON, behind the ALB, reachable from a browser, with a trace in Tempo. Minimum viable everything. **Feeling the whole path work is worth more than any single component being right.**
2. **Vertical slices, not horizontal layers.** Do not build "all the infrastructure" then "all the services." Build `catalog` completely (code → image → ECR → Argo → ALB → metrics → trace), *then* `cart`, *then* `order`. Each slice re-exercises the whole pipeline and gets faster each time.
3. **Time-box infrastructure phases.** Even without deadlines: "networking gets 3 sessions; whatever isn't done gets a TODO and we move on." Infrastructure is never done; the practice is what matters.
4. **A visible artifact per session.** A screenshot, a trace, a dashboard, a runbook entry. Something you could show someone.
5. **Defer polish ruthlessly.** Kyverno, WAF, contract testing, progressive delivery — all valuable, all *late*. The roadmap should place security hardening and policy enforcement **after** the saga works end-to-end, not before.

**Warning signs:** three consecutive sessions with no application code changed. A `.tf` line count growing faster than `.java`. Finding yourself refactoring Terraform modules "for reusability" in a single-environment project.

---

### Pitfall 45: Building everything before seeing one request flow end-to-end 🟠

**What goes wrong:** The related, sharper version of Pitfall 44: you build all six services, *then* wire the saga, *then* add observability — and when you finally run it, **fifteen things are broken simultaneously** with no way to tell which failure causes which. Debugging a system where you have never seen the working state is exponentially harder than debugging a regression from a known-good state.

**How to avoid:**
- **Get the `order → payment → inventory` saga working with two services and fake data before adding the third.** Then add real persistence. Then add compensation. Then add failure injection.
- **Build observability before the saga, not after.** You cannot debug a distributed saga without traces. PROJECT.md lists observability after the services — **the roadmap should invert this**: a minimal Prometheus + Tempo should exist before the *second* service is written, so the very first cross-service call produces a trace. This is the single most valuable ordering change this research suggests.
- **Always have a green E2E smoke test.** `make up && make smoke` must pass. If it's red, fix it before adding anything. This is the discipline that makes a 20-minute rebuild loop *useful* rather than just fast.

---

### Pitfall 46: Stale tutorials with changed APIs 🟡

**What goes wrong:** You follow a well-written blog post, hit errors that make no sense, and lose hours to the gap between the post's version and yours. The canonical example is **Karpenter `v1alpha5` → `v1beta1` → `v1`** — the CRDs were renamed (`Provisioner`/`AWSNodeTemplate` → `NodePool`/`EC2NodeClass`), the API group changed, and label keys moved namespaces. A `v1beta1` tutorial applied against a v1 install fails in confusing ways.

**Other live examples in this stack:**
- **`aws-iam-authenticator` ConfigMap vs EKS Access Entries.** The `aws-auth` ConfigMap is legacy; Access Entries (`authentication_mode = "API"`) are current. Most tutorials show `aws-auth`, and mixing the two is a great way to lock yourself out of your own cluster.
- **`terraform-aws-modules/eks` v19 → v20** — significant variable renames, and the v20 module switched to Access Entries by default.
- **IRSA → EKS Pod Identity** (see Pitfall 37).
- **Spring Boot 2.x → 3.x** — `javax.*` → `jakarta.*`, Spring Cloud Sleuth → Micrometer Tracing. Any tracing tutorial written before ~2023 is wrong for Spring Boot 3.
- **Spring Cloud AWS 2.x → 3.x** — SQS listener APIs changed substantially.
- **`kubectl` deprecations** — `PodSecurityPolicy` is gone (removed in 1.25); use Pod Security Admission or Kyverno.

**How to avoid:**
- **Prefer official docs over blog posts, always.** Karpenter, Argo CD, and the AWS LB Controller all have excellent versioned docs. When you must use a blog post, check the date *and* cross-check the API version against the official CRD reference.
- **Pin everything (Pitfall 11) and record versions in the repo.** A `VERSIONS.md` listing Kubernetes, Karpenter, Argo CD, Spring Boot, and provider versions makes "is this doc current for me?" a 5-second check.
- **When something fails inexplicably, check the API version first**: `kubectl api-resources | grep karpenter`, `kubectl explain nodepool.spec`. `kubectl explain` against your live cluster is *always* correct for your version — trust it over any document.
- Budget for it: a chunk of every session is version archaeology. That's normal, and learning to do it fast is itself a skill.

---

### Pitfall 47: Not writing anything down, so practice doesn't compound 🟠

**What goes wrong:** You solve a hard problem — a Karpenter capacity failure, a broken trace, a `terraform destroy` deadlock. Three weeks later the same problem appears and you solve it again from scratch. The practice produces no durable asset, and you cannot answer "what did I actually learn?" — which makes the whole investment feel unjustified and accelerates abandonment.

**Why it happens:** the moment a problem is solved, the motivation to document it evaporates instantly. Documentation competes with the next interesting thing and always loses.

**How to avoid:**
- **The runbook is a deliverable, not a nicety.** PROJECT.md already says "a written runbook per scenario, authored by actually debugging the failure." Make this a **phase exit criterion**: a chaos phase is not complete until its runbook exists and a *second* person (or future-you, cold) could follow it.
- **Runbook format that actually gets written** — keep it short enough that the friction is near zero:
  ```markdown
  ## Symptom: Pods Pending, Karpenter silent
  **First signal:** kubectl get pods shows Pending > 2min
  **Diagnosis:** kubectl logs -n kube-system deploy/karpenter | grep -i "no instance"
  **Root cause (this time):** instance-type allowlist excluded all available Spot capacity in us-east-1a
  **Fix:** widened karpenter.k8s.aws/instance-family to include m6a
  **Prevention:** always offer >=10 instance types
  **Time lost:** 40 min
  ```
- **A `DECISIONS.md` / lightweight ADR per non-obvious choice.** "Why Pod Identity over IRSA", "why single-AZ", "why Terraform owns Argo but Argo owns NodePools." In three months you will not remember, and you will be tempted to undo good decisions.
- **A `COSTS.md` with actual observed session costs.** Log `make up` time, `make down` time, and the day's spend. This turns the budget from an anxiety into a measured, managed thing — and watching it improve is genuinely motivating.
- **Write during, not after.** Keep the runbook open in a split pane while debugging. Post-hoc documentation does not happen.
- **The GSD workflow this project already uses handles some of this** — lean on phase artifacts and `/gsd-extract-learnings` rather than inventing a parallel system.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| `terraform destroy` as the whole of `make down` | Saves writing an ordered teardown | Orphaned ALBs/EBS/nodes billing indefinitely; destroy deadlocks | **Never** — this is the project's existential risk |
| All Terraform in one root module | Simpler at first; auto-parallelism | k8s provider can't destroy a dead cluster (Pitfall 9); state blast radius | Only if zero k8s/helm providers are used |
| `Resource: "*"` in IRSA policies "for now" | Service works immediately | Never tightened; teaches the wrong habit; the project exists to practise this | **Never** — this is the practice |
| Default Helm values for `kube-prometheus-stack` | 5-minute install | Eats 40–60% of a 3-node cluster; OOMKills the app | Only for one session, to *measure* the footprint |
| Skipping PDBs | Fewer YAML files | Every Spot reclaim drops requests; can't demo graceful behaviour | Never for the saga services |
| `latest` image tags | No version bookkeeping | Non-reproducible rebuilds — breaks the core premise | Never |
| Argo `targetRevision: HEAD` | No tag management | Tomorrow's cluster ≠ today's cluster | Acceptable for the active dev branch only; pin for anything you want to reproduce |
| RDS with `skip_final_snapshot = false` | Feels safe | Snapshot storage accrues forever, invisible to teardown checks | Never here — the data has no value |
| In-cluster Postgres instead of RDS | −10 min on `make up`, −1 orphan class | Loses RDS parameter-group/backup/IAM-auth practice | **Recommended as the default**, with a `var.use_rds` toggle for RDS-focused sessions |
| Multi-AZ compute | "Production-shaped" | Cross-AZ transfer charges; 2x public IPv4 on the ALB | Only for deliberate multi-AZ exercises |
| Interface VPC endpoints "to save NAT cost" | Feels like optimization | **$73–131/month — the opposite of the goal** | Single-AZ, session-only, behind a default-false flag |
| 100% trace sampling | Complete traces | Tempo memory dominates the cluster | Fine for a single debugging session; not the default |
| Secrets Manager for every secret | Clean | $0.40/secret/mo × 10 = the whole idle budget | Use SSM Parameter Store (free) + 1–2 consolidated JSON secrets |
| Kyverno straight to `Enforce` | "Security done" | Locks out the cluster; blocks node bootstrap (Pitfall 39) | **Never** — always Audit first |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| **AWS LB Controller** | Forgetting `kubernetes.io/role/elb` + cluster-ownership subnet tags | Tag in the VPC module using a deterministic `cluster_name`; smoke-test an Ingress in `make up` |
| **AWS LB Controller** | `target-type: instance` (default) | `ip` + pod readiness gates + `deregistration_delay=30` for real zero-downtime |
| **Karpenter** | Skipping the SQS interruption queue, or creating it via the upstream CloudFormation | Terraform the SQS queue + EventBridge rules; pass `--interruption-queue`; verify in logs |
| **Karpenter** | Narrow instance-type list → `InsufficientInstanceCapacity` on Spot | Offer ≥10 types across ≥2 families; constrain by family+size, not explicit types |
| **EKS ↔ IAM** | IRSA trust policies break on every cluster rebuild (OIDC ID changes) | **Use EKS Pod Identity** — static trust policy, survives rebuilds |
| **EKS ↔ IAM** | `aws-auth` ConfigMap (legacy) mixed with Access Entries | `authentication_mode = "API"`, Access Entries only |
| **SQS + OTel** | Assuming trace context propagates automatically | Carry `traceparent` explicitly in your own event envelope, including through the outbox |
| **SNS → SQS** | Message attributes lost in the SNS envelope | Enable raw message delivery, or read from the envelope explicitly; test it |
| **EventBridge** | Expecting SQS-style message attributes | Put `traceparent`/`eventId` inside `detail` |
| **SQS + Spring Cloud AWS** | Visibility timeout < p99 processing time | Set visibility > p99; use `ChangeMessageVisibility` heartbeats for long work |
| **RDS + HikariCP** | Default pool 10 × replicas > `max_connections` | `maximum-pool-size: 5`, migrations as a Job, alert on `hikaricp_connections_pending` |
| **ECR + Karpenter** | Image pull adds 60–90s to every new node | Small base images; ECR pull-through cache is *not* free of the same issue — consider a pinned, warm system node group |
| **Argo CD + HPA** | Argo reverts HPA's replica count forever | Omit `replicas` from the manifest, or `ignoreDifferences` on `/spec/replicas` |
| **Argo CD + Kyverno** | Mutating policies cause permanent `OutOfSync` | `ServerSideApply=true`; make the mutation match Git |
| **ESO + Secrets Manager** | $0.40/secret/month × N | SSM Parameter Store (free) or 1–2 consolidated JSON secrets |
| **Terraform + Kubernetes provider** | Provider configured from a resource in the same root module | Split state; `exec` auth; avoid `aws_eks_cluster_auth` (15-min token) |
| **CloudFront** | In the daily loop | 15–45 min to delete — take it out of the loop entirely |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Observability stack memory | App pods `OOMKilled`; Karpenter adds nodes; cost doubles | Explicit limits, 6h retention, 60s scrape, dedicated NodePool with `limits` | Immediately on a 2–3 node cluster |
| Prometheus cardinality | `prometheus_tsdb_head_series` steps up after a deploy; Prometheus OOM | `enforcedSampleLimit`, verify Micrometer URI templating, never label with IDs | ~100k series on a 2Gi Prometheus |
| HikariCP × replicas > RDS `max_connections` | Intermittent `Connection is not available` during deploys | Pool size 5, migrations as Job, `maxSurge: 1` | ~3 replicas on `db.t4g.micro` |
| Cross-AZ pod traffic | `DataTransfer-Regional-Bytes` in Cost Explorer top 3 | Single-AZ compute | Any multi-AZ deployment with chatty observability |
| Karpenter consolidation thrash | Nodes cycling hourly; pods restarting; scrape gaps | `consolidateAfter: 5m`, disruption budget `nodes: "1"` | Immediately with the `0s` default on a small cluster |
| Image pull on new nodes | 60–90s from `Pending` to `Running` | Trim JVM images (jlink/distroless); keep system pool warm | Every Karpenter scale-up |
| VPC CNI IP exhaustion | `failed to assign an IP address to container` | `/20` private subnets + prefix delegation + `WARM_PREFIX_TARGET=1` | `/24` subnets at ~4 nodes; earlier with warm pools |
| CoreDNS with 2 replicas + `ndots:5` | 5s latency spikes; intermittent `UnknownHostException` | PDB, topology spread, `ndots: 2`, JVM DNS TTL 30s | Any node disruption on a ≤3-node cluster |
| Trace sampling at 100% | Tempo ingester memory growth → OOM | 10% head sampling, or tail sampling keeping errors/slow | Under any load test |
| SQS visibility timeout too low | Duplicate processing; `NotVisible` count high | Visibility > p99 + heartbeat | Any slow downstream |

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| GH Actions OIDC trust with `repo:org/*` or no `sub` | **Full AWS account compromise by any GitHub user** | `StringEquals` on the exact `repo:...:ref:refs/heads/main`; constrain `aud`; tfsec rule |
| IRSA trust with `serviceaccount:*:*` | Any pod in any namespace assumes any role | `StringEquals` on the exact SA; one role per service |
| `Resource: "*"` in service policies | Lateral movement; `catalog` can drop `inventory` | Per-service, per-ARN, per-action policies; verify with negative tests |
| Secrets committed to Git | Permanent exposure (history); rotation is the only fix | `gitleaks` pre-commit **and** CI; Kyverno rejecting non-ESO Secrets |
| K8s Secrets unencrypted in etcd | Any `get secrets` principal reads everything | EKS envelope encryption with a KMS key + tight RBAC |
| Terraform state holds plaintext credentials | State bucket = credential store | SSE-KMS, versioning, block public access, TLS-only bucket policy, restricted IAM |
| EKS API `0.0.0.0/0` | Exposure to future CVEs; leaked kubeconfig usable anywhere | Restrict `public_access_cidrs` to your `/32`; keep private access on |
| Kyverno `Enforce` cluster-wide including `kube-system` | **Self-lockout; nodes can't bootstrap; cost climbs while you're locked out** | Audit-first; exclude system namespaces; `failurePolicy: Ignore` here; delete-webhook runbook |
| Long-lived AWS access keys anywhere | The #1 cause of four-figure surprise bills (mining) | OIDC + Pod Identity only; an SCP/IAM policy denying `iam:CreateAccessKey` |
| `imagePullPolicy` + mutable tags | Unverified image runs in-cluster | Digest pinning; Kyverno registry allowlist; Trivy gate in CI |
| No WAF/rate limit on a public ALB | Cost amplification via traffic (LCU charges) | AWS WAF rate rule — but note WAF itself is ~$5/mo + $1/rule, **weigh against the budget** |

## "Looks Done But Isn't" Checklist

- [ ] **`make down`:** Often missing the pre-Terraform `kubectl` teardown — verify `./scripts/verify-teardown.sh` exits 0 and lists nothing.
- [ ] **`make up`:** Often returns before the cluster converges — verify it ends with `argocd app wait root --health` and a smoke test.
- [ ] **Teardown verification:** Often only checks tagged resources — verify it also enumerates ALBs, running instances, available volumes/ENIs, manual RDS snapshots, interface endpoints, and never-expiring log groups.
- [ ] **Spot handling:** Often missing the interruption queue — verify `karpenter` logs show queue polling, not `interruption queue not configured`.
- [ ] **Graceful shutdown:** Often missing the `preStop` sleep — verify **zero 5xx during a rolling deploy under load**, not just that `server.shutdown=graceful` is set.
- [ ] **PDBs:** Often `minAvailable: 1` on a 1-replica Deployment — verify voluntary disruption is not permanently blocked (`kubectl get events | grep DisruptionBlocked`).
- [ ] **NetworkPolicy:** Often not enforced at all — verify with a **negative test** that a pod in `default` genuinely cannot reach `order`.
- [ ] **Distributed tracing:** Often split at the message boundary — verify **one `traceID` contains spans from all four saga services**, via an automated assertion against Tempo.
- [ ] **Idempotency:** Often untested — verify by **replaying the same SQS message 5×** and asserting no state change.
- [ ] **Saga compensation:** Often only the happy-failure path — verify the **compensation-fails** path reaches `COMPENSATION_FAILED` and alerts.
- [ ] **Outbox:** Often loses trace context and has no concurrency control — verify `traceparent` column exists and the relay uses `FOR UPDATE SKIP LOCKED` (or is single-replica).
- [ ] **DLQs:** Often exist with no alarm — verify a CloudWatch alarm at `> 0` and a Grafana panel, and that the **redrive** path has been executed at least once.
- [ ] **Probes:** Often liveness points at bare `/actuator/health` — verify that killing RDS makes pods `NotReady` but does **not** restart them.
- [ ] **JVM sizing:** Often `-Xmx` without accounting for non-heap — verify `container_memory_working_set_bytes` stays < 85% of limit under load.
- [ ] **IRSA/Pod Identity:** Often over-permissive — verify a **negative test** (e.g. `catalog` cannot write to DynamoDB).
- [ ] **IaC scanning:** Often runs but doesn't fail the build — verify a deliberately-bad commit actually blocks the PR.
- [ ] **Argo CD:** Often perpetually `OutOfSync` and ignored — verify all Applications are `Synced`/`Healthy` at the end of `make up`.
- [ ] **Budget alarm:** Often configured but never verified — verify the notification email/SNS actually arrives (trigger it manually once).
- [ ] **Runbooks:** Often describe theory — verify each one was written **while** debugging the real failure and includes the actual command output seen.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Orphaned ALB/EBS/EIP found after teardown | LOW | `verify-teardown.sh` → delete by ARN → add the resource type to the sweep script permanently |
| Orphaned Karpenter instances | LOW-MEDIUM | `aws ec2 terminate-instances` filtered by `tag:karpenter.sh/nodepool` → fix `make down` ordering |
| `terraform destroy` wedged on k8s provider | MEDIUM | `terraform state rm` the `helm_release`/`kubernetes_*` resources only → destroy → **then split the state so it can't recur** |
| `terraform destroy` wedged on VPC dependency | MEDIUM | Find the blocking ENI/SG/ALB via `aws ec2 describe-network-interfaces --filters Name=vpc-id,...` → delete → retry |
| Surprise bill discovered | MEDIUM-HIGH | Cost Explorer grouped by Usage Type → identify → delete → **AWS Support will often waive a first-time learner overage if you ask politely and show remediation** |
| Kyverno self-lockout | MEDIUM | `kubectl delete validatingwebhookconfiguration <name>` → fix policy to Audit → reapply. If API access is lost: `make down && make up` (cheap, by design) |
| Prometheus OOM from cardinality | LOW | Delete the Prometheus PVC/pod → add `enforcedSampleLimit` → identify the bad metric via `topk` before re-enabling |
| Cluster wedged beyond repair | **LOW — this is the superpower** | `make down && make up` (~35 min). The daily-teardown discipline makes most Kubernetes disasters a non-event. **Lean on this rather than heroic debugging — but write down what broke first.** |
| Corrupted Terraform state | HIGH | S3 versioning → restore prior state version → `terraform plan` to reconcile. **Verify S3 versioning is on before you need it.** |
| Secret committed to Git | HIGH | **Rotate the credential immediately** (history rewriting is secondary and often incomplete) → then `git filter-repo` → force push |
| Saga stuck in `COMPENSATING` | MEDIUM | Reconciliation job re-drives → if it fails, manual admin endpoint → **this is why the sweeper job must exist** |

## Pitfall-to-Phase Mapping

Phase names are indicative; the roadmap should map them to its own numbering.

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| 1. Interface VPC endpoints ($73/mo) | **Networking foundation** | `describe-vpc-endpoints` shows only Gateway type |
| 2. Orphaned resources | **Phase 1 — Lifecycle** | `verify-teardown.sh` exits 0 after a real destroy |
| 3. Teardown verification | **Phase 1 — Lifecycle** | Script catches a deliberately-orphaned ALB in a drill |
| 4. CloudWatch log retention | Phase 1 + Observability | No log group with `retentionInDays == null` |
| 5. Route 53 non-prorated | Networking (as a non-decision) | No hosted zones exist |
| 6. ECR accumulation | CI/CD | Lifecycle policy applied; `force_delete = true`; repo < 2 GB |
| 7. Cross-AZ transfer | Networking (AZ strategy) | `DataTransfer-Regional-Bytes` ≈ 0 in Cost Explorer |
| 8. Runaway scale-out | **Phase 0 (account+budget)** + Karpenter | NodePool `limits` set; budget alarm verified to fire |
| 9. K8s provider can't reach dead cluster | **Phase 1 — TF layout** | Full up/down cycle succeeds twice consecutively |
| 10. Slow loop | Phase 1 — Lifecycle | `make up` ≤ 20 min, `make down` ≤ 15 min, timed and logged |
| 11. Version drift | Phase 1 | Lock file committed; exact pins; a rebuild after 30 days succeeds |
| 12. Destroy deadlocks | Phase 1 | Ordered `make down` in the Makefile |
| 13. Consolidation thrash | Karpenter | < 2 NodeClaim churns/hour at steady state |
| 14. `expireAfter` strands nodes | Karpenter | Both `expireAfter` and `terminationGracePeriod` set |
| 15. Spot handling | Karpenter + Spring Boot | Chaos: forced interruption → zero failed orders |
| 16. Karpenter bootstrap | EKS cluster | Karpenter runs on the tainted on-demand system pool |
| 17. Pods Pending debugging | Karpenter + Observability | Runbook exists; Grafana alert on pending > 2 min |
| 18. Subnet tags | Networking → Ingress | Ingress smoke test in `make up` gets an ALB DNS in < 3 min |
| 19. IP exhaustion | **Networking (irreversible)** | `/20` privates; prefix delegation on |
| 20. NetworkPolicy breaks DNS/metrics | Security (**after** observability) | Positive + negative `netpol-test.sh` both pass |
| 21. CoreDNS | EKS cluster + Spring Boot | PDB set; `ndots: 2`; JVM DNS TTL 30s |
| 22. Observability eats the cluster | **Observability (after 2 services)** | Monitoring namespace < 40% of cluster memory |
| 23. Metrics loss on teardown | Observability | Explicit decision recorded in DECISIONS.md |
| 24. Cardinality | Observability + every service | `head_series` stable across deploys; enforced limits |
| 25. Traces split at SQS | **Event backbone (envelope design)** | Automated Tempo assertion: one traceID, four services |
| 26. OTel agent overhead | Spring Boot template | Startup < 40s with the agent; sampling configured |
| 27. JVM OOMKilled | **First Spring Boot service (template it once)** | Working set < 85% of limit under load |
| 28. Probes | First Spring Boot service | Chaos: kill RDS → NotReady, zero restarts |
| 29. Graceful shutdown | First Spring Boot service + Chaos | Rolling deploy under load → zero 5xx |
| 30. Connection pool | `order` service | Alert on `hikaricp_connections_pending`; migrations as a Job |
| 31. Outbox | `order` service | Kill the pod mid-saga → event still published |
| 32. Idempotency | Event backbone + every consumer | Replay a message 5× → no state change |
| 33. Compensation failure | `order` saga | `payment-sim` can fail the **refund**; reaches `COMPENSATION_FAILED` + alert |
| 34. DLQs | Event backbone | Alarm at >0; redrive executed once; runbook written |
| 35. Ordering assumptions | Event backbone | Deliver events out of order in a test → correct final state |
| 36. GH OIDC trust | **CI/CD (before first CI apply)** | `StringEquals` on exact `sub`; tfsec rule enforces it |
| 37. IRSA/Pod Identity scope | EKS cluster + each service | Negative test per service; no `Resource: "*"` in repo |
| 38. Secrets | Security (before first credential) | `gitleaks` in CI; Kyverno rejects non-ESO Secrets |
| 39. Kyverno lockout | **Security — LATE, Audit-first** | Policies survive a Karpenter scale-up; delete-webhook runbook at top of file |
| 40. Public API endpoint | EKS cluster | `public_access_cidrs` is a `/32` |
| 41. Argo `OutOfSync` | GitOps (revisit after HPA/Kyverno) | All Apps `Synced` at end of `make up` |
| 42. Argo rebootstrap | **GitOps — early** | Three consecutive `make up` cycles fully converge unattended |
| 43. TF vs Argo ownership | GitOps | Ownership table in README; `terraform plan` empty after apply |
| 44. Infra-forever | **Roadmap structure itself** | A working end-to-end request by Phase 3 |
| 45. No E2E before everything | **Roadmap ordering** | Minimal Prometheus + Tempo before the 2nd service |
| 46. Stale tutorials | Phase 1 | `VERSIONS.md` maintained |
| 47. No learning capture | Every phase (exit criterion) | Runbook + DECISIONS entry per phase; `COSTS.md` per session |

## Sources

**Verified live this session (HIGH confidence):**
- [Amazon EKS Pricing](https://aws.amazon.com/eks/pricing/) — $0.10/cluster-hr standard, $0.60/hr extended support, 14-month standard support window
- [AWS PrivateLink Pricing](https://aws.amazon.com/privatelink/pricing/) — $0.01/hr per endpoint ENI, $0.01/GB data processing
- [Elastic Load Balancing Pricing](https://aws.amazon.com/elasticloadbalancing/pricing/) — $0.0225/hr ALB/NLB base + LCU
- [Amazon Route 53 Pricing](https://aws.amazon.com/route53/pricing/) — $0.50/hosted zone/month, **not prorated**, free if deleted within 12 hours of creation
- [Amazon EBS Pricing](https://aws.amazon.com/ebs/pricing/) — gp3 ~$0.08/GB-mo, $0.005/provisioned-IOPS-mo
- [Karpenter — Disruption](https://karpenter.sh/docs/concepts/disruption/) — `consolidationPolicy`/`consolidateAfter: 0s` defaults, `Balanced` policy, `expireAfter: 720h` default, `terminationGracePeriod` interaction, NodePool disruption budgets, SQS interruption queue + EventBridge requirement, Node Auto Repair
- [AWS Load Balancer Controller — Subnet Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/subnet_discovery/) — `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`, cluster tag prioritization
- [Spring Boot — Graceful Shutdown](https://docs.spring.io/spring-boot/3.5/reference/web/graceful-shutdown.html) — enabled by default in 3.5+, `spring.lifecycle.timeout-per-shutdown-phase`, `server.shutdown=immediate` to disable
- [Amazon EKS — Assign more IP addresses with prefixes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html) — /28 prefixes, default `max-pods` 110, `WARM_PREFIX_TARGET`, migration guidance, CNI ≥1.9.0/1.10.1 constraint

**MEDIUM confidence — widely-reported patterns, synthesized rather than single-source verified. Flagged inline and worth re-verifying during the relevant phase:**
- The `terraform destroy` orphan inventory for EKS (community-reported, consistent across many issue threads)
- Learner bill horror-story causes (§1.4) — threat model, not citation
- Observability stack memory figures (§5) — typical observed values; **measure yours**
- CloudWatch Logs $0.50/GB ingestion and $0.03/GB-mo storage (page is JS-templated; not re-confirmed this session)
- Public IPv4 $0.005/hr (AWS Feb-2024 change; not re-confirmed on the pricing page this session)
- Secrets Manager $0.40/secret/month
- OTel SQS/EventBridge context-propagation failure modes (§5, Pitfall 25) — strongly reported in community issues; **verify against your pinned OTel agent version**
- `db.t4g.micro` `max_connections` ≈ 80–100 (formula-derived; verify with `SHOW max_connections`)
- Create/delete timings (§2, Pitfall 10) — order-of-magnitude; **record actuals in Phase 1**

---
*Pitfalls research for: cost-constrained AWS EKS e-commerce microservices practice platform*
*Researched: 2026-09-24*
