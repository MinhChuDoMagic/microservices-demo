# Stack Research

**Domain:** Cost-constrained, teardown-per-day AWS EKS e-commerce microservices practice platform
**Researched:** 2026-09-24
**Confidence:** HIGH for version pins (every version below was fetched live from GitHub release redirects, Maven Central `maven-metadata.xml`, npm registry, Terraform Registry API, Helm `index.yaml`, AWS docs, and the AWS Price List API on 2026-09-24). MEDIUM/LOW items are explicitly tagged inline.

> **Method note.** All configured search MCP providers are disabled in `.planning/config.json` and no `WebSearch` tool was available to this agent. Verification was performed by direct HTTPS fetch of authoritative registries and vendor documentation. Anything NOT verified this way is tagged `[UNVERIFIED]` with the reason.

---

## Executive Summary — the five things that will break your tutorials

Ranked by how badly stale guidance will hurt you:

1. **`terraform-aws-modules/eks/aws` is at v21.x** (v21.26.0). v21 **removed the `aws-auth` submodule**, **removed IRSA for Karpenter entirely**, and now **defaults Karpenter to EKS Pod Identity** (`create_pod_identity_association = true`). It requires AWS provider **>= 6.0** and Terraform **>= 1.5.7**. Every v19/v20 tutorial is wrong.
2. **Karpenter is on the `v1` API** (`karpenter.sh/v1` NodePool, `karpenter.k8s.aws/v1` EC2NodeClass). The `kubelet` block moved from NodePool to EC2NodeClass, `amiSelectorTerms` is now required, and `ttlSecondsUntilExpired`/`consolidation` were replaced by `expireAfter`/`terminationGracePeriod`/`disruption.budgets`. All v1beta1 YAML is dead.
3. **Loki's Simple Scalable (SSD) mode is deprecated and removed in Loki 4.0** — and SSD is still the Helm chart's *default*. You must explicitly set `deploymentMode: SingleBinary`. **Promtail hit end-of-life on 2026-03-02**; the supported log shipper is Grafana Alloy.
4. **tfsec is dead** — the repo's own GitHub title is literally "Tfsec is now part of Trivy". Use Trivy's `config`/misconfig scanner, or Checkov. Do not add tfsec.
5. **AWS Load Balancer Controller is at v3.x** (v3.5.0) and **Argo CD is at v3.5.3**. Both crossed major versions; v2.x manifests and values files will not transfer cleanly.

And the cost fact that dominates everything: **an EKS control plane is $0.10/cluster/hour ($73/month)** (verified on the EKS pricing page). Your ≤$5/month idle budget is only achievable if `make down` destroys the cluster itself. Idle cost is therefore S3 + DynamoDB + ECR + Route53-free — essentially cents. Design for that explicitly.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Terraform** | `1.16.4` (pin `>= 1.13`) | All infrastructure | Registry modules test against Terraform, not OpenTofu. EKS module v21 hard-requires `>= 1.5.7`. Use `.terraform-version`/tfenv so rebuilds are deterministic. |
| **AWS Provider** | `~> 6.66` (6.66.0 latest) | AWS resources | **Mandatory** — EKS module v21 requires provider `>= 6.0`. v6 introduced region-per-resource (`region` argument), which the modules now expose. |
| **`terraform-aws-modules/eks/aws`** | `~> 21.26` (21.26.0, pub. 2026-09-23) | EKS cluster + MNG + Karpenter IAM | The de facto standard. v21 gives you Pod Identity for Karpenter for free and access-entry-only auth (no `aws-auth` ConfigMap footgun on rebuild). |
| **`terraform-aws-modules/vpc/aws`** | `~> 6.7` (6.7.3) | VPC, subnets, route tables | Major v6 — note v5 examples won't transfer. Set `enable_nat_gateway = false`; fck-nat manages routes. |
| **`terraform-aws-modules/iam/aws`** | `~> 6.8` (6.8.2) | IRSA/Pod Identity roles, OIDC for GH Actions | Use the `iam-github-oidc-provider` + `iam-github-oidc-role` submodules for CI. |
| **`RaJiska/fck-nat/aws`** | `~> 1.6` (1.6.1, pub. 2026-08-15) | NAT egress | **Actively maintained** (813k downloads/month, released 6 weeks ago). See the NAT section for the real cost math. |
| **Amazon EKS** | **Kubernetes `1.34`** | Control plane | Standard support currently covers **1.36, 1.35, 1.34**; extended covers 1.33/1.32/1.31. Target **1.34**, not 1.36 — see rationale below. |
| **Karpenter** | `1.14.1` | Node provisioning + Spot interruption | Required: k8s 1.36 needs Karpenter `>= 1.13`, 1.34 needs `>= 1.6`. v1.14.1 covers both. Install from `oci://public.ecr.aws/karpenter/karpenter`. |
| **Argo CD** | `3.5.3` (chart `argo-cd` 10.9.2) | GitOps CD | Major v3 line. Chart 10.x. |
| **Java (JDK)** | **Temurin 25 (LTS)** | Runtime for all Spring services | Spring Boot 4.1.1 supports Java 17–26. 25 is the current LTS and gives you compact object headers + generational ZGC/Shenandoah, which matter on tiny Spot nodes. |
| **Spring Boot** | `4.1.1` | All containerized services | GA and coherent with Spring Cloud 2025.1.x, Spring Cloud AWS 4.1.1, Gateway 5.0.3, and — critically — **OTel Java instrumentation already supports Spring Boot 4** (verified in the OTel changelog: WebMVC, WebFlux, Spring Cloud Gateway, actuator, and the starter all have explicit Boot 4 support). Requires Spring Framework 7.0.9+. |
| **React + Vite** | React `19.3.0`, Vite `8.3.0`, `@vitejs/plugin-react` `6.1.1` | Frontend SPA | Vite 8 is current. Build to S3 + CloudFront with **OAC**. |

#### Why Kubernetes 1.34, not 1.36

EKS charges the same $0.10/hr for any standard-support version, so there is no cost argument. The argument is rebuild reliability, which is your hard constraint:

- **1.36 permanently disables the `gitRepo` volume type** and **enables `StrictIPCIDRValidation` by default** — API rejects CIDRs with leading zeros or ambiguous host bits (`192.168.0.5/24`). Third-party charts still ship such values.
- **1.36 changes SELinux volume labeling to GA defaults**, with known issues sharing volumes between privileged/unprivileged pods — exactly your observability DaemonSet shape.
- 1.34 has been in standard support long enough that every chart in this document has been exercised against it.

Since you rebuild daily, upgrading later is a `terraform apply` away — and doing a 1.34 → 1.35 → 1.36 in-place upgrade is itself a high-value practice exercise. (EKS now also supports **rollback to the previous minor within 7 days** of an in-place upgrade — a genuinely new capability worth practising.)
Confidence: **HIGH** on the version/support facts (AWS docs), **MEDIUM** on the 1.34-vs-1.36 judgement call (it's an opinion, not a fact).

---

### Kubernetes Platform Addons

| Component | Version | Install as | Notes |
|-----------|---------|-----------|-------|
| **AWS Load Balancer Controller** | app `v3.5.0`, chart `3.5.0` (`https://aws.github.io/eks-charts`) | Helm via Argo CD | **Major v3.** v2.x values are not drop-in. Supports Pod Identity. |
| **External Secrets Operator** | chart `2.11.0` | Helm via Argo CD | **API is `external-secrets.io/v1`** (stable) — verified in live docs. `v1beta1` is legacy; the v0.10 shift is long past. Chart is now on the **2.x** line. Use `refreshPolicy` + `target.immutable` semantics deliberately. |
| **Kyverno** | app `v1.19.1`, chart `3.9.1` | Helm via Argo CD | Policy API is `kyverno.io/v1` for ClusterPolicy; the v1.11/v1.12-era `validate.podSecurity` and `ValidatingPolicy`/CEL work has landed. **Kyverno is not free on a tiny cluster** — admission + background + reports + cleanup controllers. Run with `backgroundController.enabled=false` and `reportsController.enabled=false` for a practice cluster unless you're specifically practising policy reports. |
| **metrics-server** | `v0.9.0` | Helm via Argo CD | Required for HPA on `catalog`. |
| **EBS CSI driver** | `v1.66.0` | **EKS managed addon** with `pod_identity_association` | Use the managed addon, not Helm — the EKS module v21 wires Pod Identity for you and it's one less rebuild-order dependency. |
| **VPC CNI / kube-proxy / CoreDNS** | latest (module default `most_recent = true`) | EKS managed addons | v21 defaults `addons.most_recent = true` and `resolve_conflicts_on_create = "NONE"`. Both changed from v20 — if you pinned addon versions from an old tutorial, drop the pins. |
| **Karpenter** | `1.14.1` | Helm from `oci://public.ecr.aws/karpenter/karpenter` | See Karpenter section. |
| **Argo CD** | `3.5.3` / chart `10.9.2` | Helm bootstrap, then self-manage | See GitOps section. |

---

### Observability Stack

| Component | Chart version | App version | Critical config |
|-----------|---------------|-------------|-----------------|
| **kube-prometheus-stack** | `91.5.1` | prometheus-operator `v0.94.1` | Chart `kubeVersion: >=1.25.0-0`. Chart major jumped past 90 — anything referencing `5x.x`/`6x.x` is a year+ stale. Disable `grafana.enabled` here **only if** you install Grafana separately; simpler to leave it on. |
| **Grafana (standalone chart)** | `10.5.15` | — | Only if not using the bundled one. |
| **Loki** | chart `7.3.0` | Loki `3.6.12` | **`deploymentMode: SingleBinary`, `singleBinary.replicas: 1`, `loki.storage.type: s3`.** The chart's *default* is SSD, which is **deprecated and removed in Loki 4.0** (verified in Grafana docs). Monolithic is documented as suitable up to ~20GB/day — vastly more than this cluster produces. |
| **Tempo** | chart `1.24.4` | Tempo `2.9.0` | Use the **`tempo`** chart (monolithic), **not `tempo-distributed`** (chart 1.61.3). Distributed spins up distributor/ingester/querier/query-frontend/compactor — 5+ extra pods you cannot afford on a 2-node Spot cluster. Back it with S3. |
| **Grafana Alloy** | chart `1.12.1` | `v1.19.2` | **Log/telemetry shipper. Promtail reached EOL 2026-03-02** (verified — Grafana docs banner). Alloy replaces it and can also run as your OTLP receiver. |
| **OpenTelemetry Java agent** | `v2.31.1` | — | See OTel section. |
| **OpenTelemetry Java SDK BOM** | `1.66.0` | — | Only needed for manual spans. |

**Cost/footprint warning:** kube-prometheus-stack + Loki + Tempo + Alloy + Grafana is realistically **~2.5–4 GiB of pod memory requests** before your application runs. Budget node capacity accordingly (see Karpenter section). `[UNVERIFIED — this is an estimate from component defaults, not a measured figure. Measure it in Phase 1 and record the real number.]`

---

### Java / Spring Stack

| Artifact | Version | Purpose |
|----------|---------|---------|
| `org.springframework.boot:spring-boot-starter-parent` | **`4.1.1`** | Parent POM (fallback: `3.5.16` — see risk note) |
| `org.springframework.cloud:spring-cloud-dependencies` | **`2025.1.3`** | Spring Cloud BOM aligned to Boot 4 |
| `org.springframework.cloud:spring-cloud-starter-gateway-server-webmvc` | **`5.0.3`** | **API gateway — use the MVC flavour** |
| `io.awspring.cloud:spring-cloud-aws-dependencies` | **`4.1.1`** | SNS/SQS/DynamoDB/Secrets integration |
| `software.amazon.awssdk:bom` | **`2.55.4`** | AWS SDK for Java v2 |
| `io.opentelemetry.instrumentation:opentelemetry-spring-boot-starter` | **`2.31.1`** | OTel (starter flavour) |
| `io.opentelemetry:opentelemetry-bom` | `1.66.0` | OTel API/SDK for manual instrumentation |
| `org.testcontainers:testcontainers-bom` | **`2.0.5`** | Integration testing |
| `au.com.dius.pact.provider:junit5` | `4.7.5` | Contract testing (if Pact chosen) |
| GraalVM / Native Build Tools | GraalVM Community **25**, NBT **1.1.8** | Native image (see below — **do not use for M1**) |

#### Spring Cloud Gateway: **use Server Web MVC, not WebFlux**

Spring Cloud Gateway 5.0.3 ships two Server flavours (verified in the reference docs: "Spring Cloud Gateway Server WebFlux" and "Spring Cloud Gateway Server Web MVC"). Choose **`spring-cloud-starter-gateway-server-webmvc`** because:

- With **Java 25 virtual threads** (`spring.threads.virtual.enabled=true`), the blocking MVC model gets WebFlux-class concurrency without Reactor's debugging tax. A Reactor stack trace is a terrible place to learn distributed tracing.
- **OTel context propagation is dramatically simpler on the servlet stack.** Reactor context propagation across `flatMap` boundaries is the single most common source of "my trace breaks at the gateway" — which would directly sabotage your "one trace follows an order end-to-end" requirement.
- Your six backend services are all MVC. One programming model, one mental model.

Use WebFlux Gateway **only if** you specifically want to practise reactive backpressure — which is not on your requirements list.
Confidence: **HIGH** on the flavours existing and versions; **MEDIUM** on the recommendation (opinion).

#### Spring Boot 4.1.1 vs 3.5.16 — the one real fork

Recommend **4.1.1**. Verified facts supporting it:
- Boot 4.1.1 requires Java 17+, compatible through Java 26, needs Spring Framework 7.0.9+.
- Spring Cloud 2025.1.3, Spring Cloud AWS 4.1.1 and Gateway 5.0.3 are all GA on the Boot 4 line.
- The OTel Java instrumentation changelog contains explicit entries: *"Spring starter: support Spring Boot 4"*, *"Spring WebMVC: support Spring Boot 4"*, *"Spring Cloud Gateway: support Spring Boot 4"*, *"Spring Boot actuator autoconfigure: support Spring Boot 4"*.

**Risk / escape hatch:** Boot 4 restructured autoconfiguration into many fine-grained `spring-boot-*` modules. Some third-party starters lag. If you hit an unresolvable incompatibility, fall back to **Spring Boot 3.5.16** + **Spring Cloud 2025.0.x** + **Spring Cloud AWS 3.4.2** + **Gateway 4.3.5** — all verified as current on their respective maintenance lines. Decide this once, in Phase 2, and pin it in a shared parent POM.

#### GraalVM native image: **NO for Milestone 1**

- Native build adds **3–8 minutes per service per CI run** and you have 6 services. `[UNVERIFIED — order-of-magnitude from general experience, not measured for this codebase.]`
- Testcontainers, Spring Cloud Gateway filters, and dynamic proxies all need reachability metadata hints — you will spend your learning budget on GraalVM configuration, not AWS.
- **The OTel Java *agent* does not work with native images at all.** You'd be forced onto the starter-only path with reduced instrumentation coverage.
- JVM startup on Java 25 with **CDS/AOT cache** (`-XX:AOTCache`) gets you most of the cold-start benefit for near-zero effort.

Revisit native image in M2 as a deliberate experiment on **one** service.

#### JVM flags that actually matter on tiny Spot nodes

```
JAVA_TOOL_OPTIONS="\
  -XX:MaxRAMPercentage=70.0 \
  -XX:InitialRAMPercentage=50.0 \
  -XX:+UseSerialGC \
  -XX:MaxMetaspaceSize=128m \
  -XX:+ExitOnOutOfMemoryError \
  -XX:+UseCompactObjectHeaders \
  -Xss512k"
```

Rationale (each of these is a real gotcha, not boilerplate):
- **`MaxRAMPercentage=70`, not the default 25%.** The JVM's `MaxRAMPercentage` default wastes ~75% of a container limit. 70% leaves room for metaspace, thread stacks, code cache, and direct buffers — all of which live *outside* the heap and all of which count toward the cgroup limit that OOMKills you.
- **`UseSerialGC` under ~2 vCPU / ~1 GiB.** The JVM's ergonomics pick G1 once it sees ≥2 CPUs and ≥1792MB, and G1's region/remembered-set overhead is pure waste at this size. Serial GC has the smallest footprint. If you give a service ≥2 GiB, switch to G1 and measure.
- **`ExitOnOutOfMemoryError`** — makes the pod die cleanly so Kubernetes restarts it, instead of limping. Essential for your OOMKill chaos scenario to produce a clean signal.
- **`UseCompactObjectHeaders`** (JDK 24+, production-ready in 25) — typically 10–20% heap reduction on object-heavy Spring apps. `[UNVERIFIED percentage — measure it.]`
- Always set **`resources.limits.memory` == `resources.requests.memory`** (Guaranteed QoS) for JVM pods. Burstable JVM pods on Spot nodes are how you get non-reproducible OOMKills.
- **`-XX:ActiveProcessorCount`** is worth knowing about: the JVM reads cgroup CPU *quota*, so a `cpu: 500m` limit makes it see 1 CPU and size thread pools accordingly. If you set CPU requests but no limits, the JVM sees the whole node. Pick one and be consistent.

Confidence: **MEDIUM** — these flags are well-established JVM-on-Kubernetes practice, but they were not verified against a live doc in this session and the exact percentages are workload-dependent.

---

### OpenTelemetry: agent vs starter

**Use the Java agent (`opentelemetry-javaagent.jar` v2.31.1) for Milestone 1.**

| | Java agent `2.31.1` | Spring Boot starter `2.31.1` |
|---|---|---|
| Instrumentation breadth | Everything (JDBC, Redis/Lettuce, AWS SDK v2, SQS/SNS, Tomcat, Gateway, Hibernate) | Subset; AWS SDK and messaging coverage is narrower |
| Code/build changes | Zero — `-javaagent:` + env vars | Dependency + config per service |
| Startup cost | ~1–3s extra (bytecode weaving) | Negligible |
| GraalVM native | **Not supported** | Supported |
| Spring Boot 4 | Supported (verified in changelog) | Supported (verified in changelog) |

For your requirement — *"a trace that follows a single order end-to-end across the full saga"* — agent breadth is decisive. The saga crosses HTTP → Postgres → SNS/SQS → DynamoDB → Redis. The agent instruments **AWS SDK v2 SQS/SNS context propagation** out of the box; that's the hardest link in your chain and the one most likely to silently break with the starter.

**Deployment pattern:** bake the agent into the image via a multi-stage Dockerfile copy (do **not** use an init container + `emptyDir` — it adds a rebuild failure mode for zero benefit here).

**Wiring to Tempo:**
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.observability.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_SERVICE_NAME=order
OTEL_RESOURCE_ATTRIBUTES=service.namespace=shop,deployment.environment=dev
OTEL_TRACES_SAMPLER=parentbased_always_on   # practice cluster: sample everything
OTEL_METRICS_EXPORTER=none                  # Prometheus scrapes /actuator/prometheus instead
OTEL_LOGS_EXPORTER=none                     # Alloy ships stdout to Loki instead
```
Emit **exemplars** from Micrometer (`management.prometheus.metrics.export.properties`) so Grafana can jump metric → trace. That single wire is what makes the RED dashboard actually useful, and it's the thing most tutorials skip.
Confidence: **HIGH** on versions and Boot 4 support; **MEDIUM** on the exact env var set (standard OTel spec, not re-verified line-by-line this session).

---

## Karpenter v1 — the current API shape

Verified live from `karpenter.sh/docs`. Version **1.14.1**.

**Compatibility matrix (verified):**

| Kubernetes | 1.30 | 1.31 | 1.32 | 1.33 | 1.34 | 1.35 | 1.36 |
|---|---|---|---|---|---|---|---|
| Karpenter | >= 0.37 | >= 1.0.5 | >= 1.2 | >= 1.5 | >= 1.6 | >= 1.9 | >= 1.13 |

### What changed v1beta1 → v1 (why your tutorial is wrong)

- `apiVersion: karpenter.sh/v1` (NodePool, NodeClaim) and `karpenter.k8s.aws/v1` (EC2NodeClass).
- **`nodeClassRef` now requires `group` + `kind` + `name`** (was `apiVersion`/`name`).
- **The entire `kubelet` block moved from NodePool `spec.template.spec.kubelet` to EC2NodeClass `spec.kubelet`.** Docs state this explicitly: *"Objects for setting Kubelet features have been moved from the NodePool spec to the EC2NodeClasses spec."*
- **`amiSelectorTerms` is now required** on EC2NodeClass. `amiFamily` alone is no longer sufficient — it's required only when you don't use an `alias` term. The `alias: al2023@latest` form is the ergonomic one.
- `ttlSecondsUntilExpired` → **`expireAfter`** (`720h` or `Never`), now on `spec.template.spec`.
- New **`terminationGracePeriod`** on NodePool — the forced-deletion ceiling for a draining node.
- `disruption.consolidationPolicy` + **`disruption.budgets`** (replaces the old ad-hoc rate limiting).

### Minimal current-API pair for this project

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]              # Graviton: ~20% cheaper, and forces multi-arch image practice
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "m", "c", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["3"]
      expireAfter: 168h
      terminationGracePeriod: 5m
  limits:
    cpu: "8"
    memory: 16Gi                          # HARD COST CEILING — set this, always
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m                  # aggressive: this is a practice cluster
    budgets:
      - nodes: "20%"
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: al2023@latest                # REQUIRED in v1
  subnetSelectorTerms:
    - tags: { "karpenter.sh/discovery": "${CLUSTER_NAME}" }
  securityGroupSelectorTerms:
    - tags: { "karpenter.sh/discovery": "${CLUSTER_NAME}" }
  kubelet:                                # MOVED HERE in v1
    maxPods: 40
    systemReserved: { cpu: 100m, memory: 100Mi }
    kubeReserved:   { cpu: 200m, memory: 200Mi }
```

> **`limits.cpu`/`limits.memory` on the NodePool is your single most important cost guardrail.** A misconfigured HPA + unbounded NodePool is the classic way a practice cluster silently becomes a $200 bill. Set it before you write your first Deployment.

### Spot interruption handling (verified)

Karpenter watches an **SQS queue** fed by **EventBridge rules**. It handles:
Spot Interruption Warnings, Scheduled Change Health Events, Instance Terminating, Instance Stopping, and Instance Status Check Failures. On a Spot warning it **immediately begins draining and provisions a replacement in parallel**, using the 2-minute notice window.

Two gotchas worth knowing:
- **Karpenter does NOT act on Spot Rebalance Recommendations** — only interruption warnings. AWS Node Termination Handler can, but the docs warn it causes *more* churn. **Do not install NTH.** Karpenter alone is correct.
- The SQS queue + EventBridge rules must be provisioned by you. The `terraform-aws-modules/eks/aws` Karpenter submodule creates them (`enable_irsa`-era tutorials created them by CloudFormation — use the module).

### Karpenter's own node: confirmed pattern

**Yes — a small EKS managed node group for Karpenter itself is the correct and required pattern.** Karpenter cannot provision the node it runs on. Recommended shape for this project:

| | Config | Cost |
|---|---|---|
| **System MNG** | 2 × `t4g.small` **On-Demand**, `capacity_type = "ON_DEMAND"` | ~$0.0336/hr |
| **Karpenter-managed** | Spot, arm64, `t4g`/`m7g`/`c7g` | variable, ~$0.01–0.03/hr |

Put Karpenter, CoreDNS, and Argo CD's application-controller/repo-server on the On-Demand MNG (taint + toleration, or just let the scheduler do it). Everything else — your services and the observability stack — goes to Karpenter Spot. Two nodes rather than one because Argo CD + kube-prometheus-stack + Karpenter genuinely will not fit on one `t4g.small`.

**Rebuild-order gotcha:** Karpenter's Helm release must land *after* the MNG exists, and the `karpenter.sh/discovery` tags must exist on subnets/SGs *before* the first NodePool reconcile. Get this wrong and `make up` fails intermittently. Express it as an explicit `depends_on` in Terraform.

---

## IAM for Pods: **EKS Pod Identity**, with IRSA as a narrow exception

**Verdict: Pod Identity is the current AWS recommendation and has strictly better Terraform support.** The strongest single piece of evidence is not a blog post — it's the EKS module v21 upgrade guide (verified):

> *"Karpenter: Native support for IAM roles for service accounts (IRSA) has been removed; EKS Pod Identity is now enabled by default … `create_pod_identity_association` is now set to `true` by default."*

The most-used EKS Terraform module in the world **deleted the IRSA path**. That's the answer.

| | **EKS Pod Identity** | **IRSA** |
|---|---|---|
| Trust policy | One static principal: `pods.eks.amazonaws.com` | Per-cluster OIDC provider ARN + `sub` condition |
| **Rebuild impact (critical for you)** | Role is **cluster-independent** — survives teardown/rebuild untouched | Trust policy embeds the cluster's OIDC issuer ID, which **changes on every cluster recreate** → every role's trust policy must be rewritten every rebuild |
| Terraform | `aws_eks_pod_identity_association` — one flat resource | OIDC provider + TLS cert data source + per-role assume-role policy document |
| Credential path | EKS Auth service assumes; Pod Identity Agent DaemonSet issues to SDK (one call per node) | Each pod's SDK does its own `AssumeRoleWithWebIdentity` |
| Scale limit | 5,000 associations/cluster | Practically unbounded |
| Cross-account | Supported (via role chaining) | Supported |
| Requires | Pod Identity Agent addon on every node | Nothing on-node |

**Pod Identity wins decisively on your #1 constraint.** With IRSA, a destroy/recreate changes `oidc-eks.<region>.amazonaws.com/id/<NEW_ID>` and every IAM role trust policy goes stale. That is precisely the class of "rebuild breaks" failure that kills this project.

Additional v21 gotcha: **the module changed the OIDC issuer host from `oidc.eks.*` to the dual-stack `oidc-eks.*` endpoint.** If you do keep any IRSA roles, hand-written trust policies copied from tutorials will not match.

**Use IRSA only for:** anything that must obtain credentials before the Pod Identity Agent DaemonSet is Ready on a fresh node (rare), or a controller whose SDK predates Pod Identity support. **Everything in this project — ALB Controller v3, ESO 2.x, EBS CSI, Karpenter 1.14, and all six Spring services on AWS SDK v2 2.55.4 — supports Pod Identity.**

`[UNVERIFIED]` The exact minimum AWS SDK for Java v2 version required for Pod Identity's container-credentials path — verify empirically in Phase 1. 2.55.4 is far beyond any plausible floor.

---

## NAT, VPC Endpoints, and the cost trap

### The verified numbers

Fetched from the **AWS Price List API** (`AmazonVPC`, us-east-1) on 2026-09-24:

| Item | Verified price | Monthly (730h) |
|---|---|---|
| **Interface VPC endpoint** (`USE1-VpcEndpoint-Hours`) | **$0.01 per endpoint-hour, per AZ ENI** | **$7.30 per endpoint per AZ** |
| Interface endpoint data (`USE1-VpcEndpoint-Bytes`) | $0.01/GB | — |
| **Gateway endpoint** (S3, DynamoDB) | **no charge line exists — free** | **$0.00** |
| NAT Gateway | $0.045/hr + $0.045/GB `[UNVERIFIED — from the EC2 price list, not re-fetched]` | ~$32.85 + data |
| `t4g.nano` (fck-nat) | ~$0.0042/hr | ~$3.07 + ~$0.80 EBS |

### The trap, quantified

You asked for this carefully, so here it is explicitly. A "minimal NAT-free EKS cluster" needs interface endpoints for **ECR API, ECR DKR, STS, EC2, CloudWatch Logs, ELB, SQS, SNS, Secrets Manager, and Autoscaling** — call it 10. Plus the free S3 gateway endpoint (mandatory — ECR image *layers* live in S3).

| Design | Monthly | Hourly |
|---|---|---|
| **fck-nat `t4g.nano` + S3 gateway endpoint only** ✅ | **~$3.90** | **~$0.005** |
| Managed NAT Gateway + S3 gateway endpoint | ~$32.85+ | ~$0.045 |
| **Zero-NAT: 10 interface endpoints × 1 AZ** ❌ | **~$73.00** | **~$0.100** |
| Zero-NAT: 10 interface endpoints × 2 AZ ❌❌ | ~$146.00 | ~$0.200 |
| fck-nat + 10 interface endpoints (worst of both) ❌❌ | ~$76.90 | ~$0.105 |

**Interface endpoints cost 2.4× a NAT Gateway and 19× fck-nat.** The "replace NAT with VPC endpoints to save money" advice is **actively wrong at this scale** — it's a latency, data-sovereignty, and bandwidth-cost optimisation for clusters pushing terabytes, not a cost optimisation for a two-node practice cluster.

### Recommendation

```
fck-nat t4g.nano in ONE public subnet
  + S3 Gateway Endpoint      (free, MANDATORY — ECR layers + Loki/Tempo chunks)
  + DynamoDB Gateway Endpoint (free, and you use DynamoDB)
  + ZERO interface endpoints
```

Single-AZ fck-nat is correct here: multi-AZ fck-nat doubles instance cost for HA you explicitly don't need, and cross-AZ NAT traffic incurs data-transfer charges. **Accept the single point of failure — then use it as a chaos scenario** ("kill the NAT instance, watch image pulls fail, watch the ASG replace it"). That's a better lesson than paying for HA.

Set `fck-nat`'s ASG to `min=max=desired=1` so it self-heals, and use `ha_mode = false`.

**Why the S3 gateway endpoint is non-negotiable:** without it, every ECR image layer pull, every Loki chunk flush, and every Tempo block write traverses the fck-nat `t4g.nano`. A `t4g.nano` has ~32 Mbps baseline network with burst credits — pulling ~1.5 GB of container images on a cold `make up` will exhaust burst and make your rebuild crawl. The gateway endpoint routes that traffic off the NAT for free. **This single free resource is the difference between a 6-minute and a 20-minute rebuild.** `[UNVERIFIED — t4g.nano baseline bandwidth figure and the rebuild-time delta are estimates; measure on first build.]`

**Consider adding interface endpoints only if:** a specific chaos scenario requires a fully NAT-less private subnet. Then add exactly the two you need (ECR API + ECR DKR, ~$14.60/mo for the session) and destroy them with the rest.

---

## GitOps: Argo CD

**Version: `v3.5.3`, chart `argo-cd` 10.9.2** (verified from the argo-helm index).

### Resource footprint — it is genuinely not trivial

Argo CD deploys 6–7 workloads: `application-controller` (StatefulSet), `repo-server`, `server`, `applicationset-controller`, `notifications-controller`, `dex-server`, and **Redis**.

Approximate default requests: **~1 CPU / ~1.5–2 GiB** across the set, with `application-controller` and `repo-server` being the heavy ones (repo-server forks `helm template`/`kustomize build` subprocesses and spikes hard on large charts — rendering kube-prometheus-stack 91.5.1 is a *big* template job).
`[UNVERIFIED — chart default resource blocks were not fetched in this session. Read `values.yaml` for chart 10.9.2 and record the real numbers in Phase 3.]`

**Slim it for a two-node cluster:**
```yaml
dex:            { enabled: false }   # no SSO on a single-operator cluster
notifications:  { enabled: false }   # no Slack integration in M1
applicationSet: { enabled: true }    # keep — you want this pattern
server:
  extraArgs: ["--insecure"]          # ALB terminates TLS; skip double TLS
redis-ha:       { enabled: false }
controller:
  resources: { requests: { cpu: 250m, memory: 512Mi }, limits: { memory: 1Gi } }
repoServer:
  resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { memory: 1Gi } }
```
Disabling dex + notifications removes two pods for zero functional loss here.

### App-of-apps vs ApplicationSet

**Use both, at different layers — this is the current idiomatic split:**

| Layer | Pattern | Why |
|---|---|---|
| **Root / bootstrap** | **App-of-apps** — one `Application` pointing at `gitops/bootstrap/` containing child `Application`s for each platform addon | Explicit **`syncWave` ordering** is the whole point. ESO must sync before anything consuming a Secret; ALB Controller before any Ingress; Kyverno's webhook **last** or it blocks its own dependencies' admission. ApplicationSet gives you no ordering primitive. |
| **Application services** | **ApplicationSet** with a **Git directory generator** over `gitops/apps/*` | Your 6 services are homogeneous. Drop a directory, get an Application. Zero boilerplate, and adding service #7 in M2 is a `mkdir`. |

**Sync waves for this project (get this right or `make up` is flaky):**
```
-2  namespaces, Kyverno CRDs + policy exceptions
-1  External Secrets Operator, EBS CSI, metrics-server
 0  Karpenter NodePool/EC2NodeClass, AWS Load Balancer Controller
 1  ExternalSecret resources (need ESO CRDs + Pod Identity live)
 2  observability: kube-prometheus-stack, Loki, Tempo, Alloy
 3  application services (ApplicationSet-generated)
 4  Kyverno enforce-mode policies  ← LAST. Always last.
```

**Teardown gotcha (this will bite you):** Argo CD Applications with `finalizers: [resources-finalizer.argocd.argoproj.io]` will **hang `terraform destroy` forever** if the cluster API is already gone or Argo CD is deleted first. Your `make down` must either (a) delete all Applications and wait, before destroying the cluster, or (b) `kubectl patch` finalizers off. Bake this into the Makefile in Phase 1, not after your first 40-minute hung destroy.

Similarly: **Kubernetes `Service type: LoadBalancer` and ALB Ingresses leak ELBs and orphan security groups** that block VPC deletion. Your teardown-verification check must specifically hunt for orphaned ELBs, ENIs, and security groups — this is the #1 cause of failed `terraform destroy` on EKS.

---

## CI: GitHub Actions

| Tool | Version | Notes |
|---|---|---|
| `aws-actions/configure-aws-credentials` | **`v6.3.0`** | v6 is current. **Pin by commit SHA, not tag** for a security-themed project. |
| `aws-actions/amazon-ecr-login` | `v2` | |
| **Trivy** | **`v0.74.0`** | Image scanning **and** IaC misconfig scanning — one tool, two jobs |
| **Checkov** | **`3.3.19`** | Optional second IaC opinion |
| **tfsec** | ~~`v1.28.14`~~ | ☠️ **DEAD — do not use** |

### tfsec is deprecated — verified

The `aquasecurity/tfsec` GitHub repository's own page title reads: **"Tfsec is now part of Trivy"**. Last release `v1.28.14`. It has been folded into Trivy's misconfiguration scanner.

**Action:** update the PROJECT.md requirement *"tfsec/Checkov IaC scanning"* → **"Trivy `config` scanning, with Checkov as an optional second opinion"**.

```yaml
# Image scan
- uses: aquasecurity/trivy-action@master
  with: { image-ref: '...', severity: 'HIGH,CRITICAL', exit-code: '1' }
# IaC scan — replaces tfsec entirely
- uses: aquasecurity/trivy-action@master
  with: { scan-type: 'config', scan-ref: './terraform', severity: 'HIGH,CRITICAL', exit-code: '1' }
```

Run **Checkov too** — it catches different classes (it's better at cross-resource/graph checks; Trivy is better at CVE + registry integration). They disagree usefully. Since this is a learning project, the disagreements *are* the lesson.

### OIDC federation

One `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com` (thumbprint no longer required — AWS validates via its own trust store `[UNVERIFIED — behaviour change not re-verified this session]`). Use `terraform-aws-modules/iam/aws//modules/iam-github-oidc-role`.

**Two roles, not one:**
- `gha-ecr-push` — narrow, `sub: repo:OWNER/REPO:*` (needed on PRs)
- `gha-terraform` — broad, **`sub: repo:OWNER/REPO:ref:refs/heads/main`** or `environment:prod`

Never let a PR from a fork assume the Terraform role. The `sub` condition must use `StringLike` with an anchored pattern — a wildcard `repo:OWNER/*` is the classic misconfiguration and is worth deliberately introducing and then catching with Checkov as an exercise.

---

## Frontend: React + Vite → S3 + CloudFront

| Package | Version |
|---|---|
| `react` / `react-dom` | **`19.3.0`** |
| `vite` | **`8.3.0`** |
| `@vitejs/plugin-react` | **`6.1.1`** |
| `typescript` | `7.0.2` (TS 7 is current; `5.x` is long stale) |

### Cheapest correct CloudFront setup

**Use OAC (`aws_cloudfront_origin_access_control`). OAI is legacy and AWS has stopped adding features to it** — notably OAI cannot sign requests to SSE-KMS-encrypted objects or to S3 in newer regions.

```hcl
resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "spa-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

Then: **S3 bucket fully private** (`aws_s3_bucket_public_access_block` all-true, **no website endpoint**), bucket policy granting `s3:GetObject` to `cloudfront.amazonaws.com` conditioned on `AWS:SourceArn` = the distribution ARN.

**Cost specifics:**
- CloudFront free tier: 1 TB out + 10M requests/month, **perpetual, not 12-month**. Your frontend is effectively free. `[UNVERIFIED — free tier terms not re-fetched this session.]`
- **`PriceClass_100`** — cheapest edge set, and irrelevant for a single-operator project.
- **Use the default `*.cloudfront.net` certificate.** ACM certs are free, but a custom domain is explicitly out of scope, and a cert in `us-east-1` is one more cross-region dependency in your rebuild.
- SPA routing: use a **CloudFront Function** (not Lambda@Edge — CF Functions are ~1/6 the price and have no cold start) or `custom_error_response` mapping 403/404 → `/index.html` 200. The `custom_error_response` route is free; prefer it.
- **CloudFront distributions take 3–8 minutes to create and ~10–15 minutes to fully delete.** This will dominate your `make down` wall-clock. Consider putting the frontend in a **separate Terraform state/stack with its own lifecycle** so the expensive-to-destroy-but-nearly-free-to-keep CloudFront distribution can persist across sessions while the EKS stack churns daily. This is a genuinely important design decision for your rhythm.

---

## Testing

| Tool | Version | Role |
|---|---|---|
| **Testcontainers for Java** | **`2.0.5`** | Postgres, Redis, LocalStack in integration tests |
| **LocalStack** | **`4.14.0`** | DynamoDB/SNS/SQS/Secrets Manager emulation |
| **Spring Cloud Contract** | via Spring Cloud `2025.1.3` | **Recommended** contract testing |
| Pact (`au.com.dius.pact.provider:junit5`) | `4.7.5` | Alternative |

### ⚠️ Testcontainers 2.0 is a major version — artifact IDs changed

Verified from the Testcontainers docs: modules are now `org.testcontainers:testcontainers-mysql`, **not** `org.testcontainers:mysql`. Every dependency line in every pre-2026 tutorial is wrong. Import `testcontainers-bom:2.0.5` and use the new `testcontainers-<module>` artifact IDs.

Also note Testcontainers 2.0 dropped/raised baselines around Docker API and shaded deps — if you hit weirdness on Colima/Podman, that's where to look. `[UNVERIFIED — full 2.0 breaking-change list not fetched.]`

### Contract testing: **Spring Cloud Contract over Pact**

- You are 100% Spring on both sides of every contract. SCC's `@AutoConfigureStubRunner` + generated WireMock stubs is far less ceremony than running a Pact Broker.
- **A Pact Broker is another service to host and destroy daily.** That directly conflicts with your teardown constraint. SCC stubs are Maven artifacts — they live in your existing registry.
- Pact's advantage (polyglot, language-neutral) is worth it only when consumers are in different languages. Your one Python component is a Lambda **event consumer**, not an HTTP consumer — so validate it with **JSON Schema on the EventBridge/SNS payload**, which is the right tool anyway.

Confidence: **MEDIUM** — versions HIGH, recommendation is opinion.

### LocalStack scope

Use LocalStack **only** for SNS/SQS/DynamoDB/Secrets Manager in unit-level integration tests. **Do not try to emulate EKS, IAM policy evaluation, or ALB.** The free tier's IAM enforcement is not faithful, and believing a LocalStack IAM pass means your real policy works is a trap that will cost you a debugging session. Real AWS is cheap at this scale — use it for anything IAM-adjacent.

---

## Installation / bootstrap order

```bash
# Toolchain
brew install tfenv kubectl helm awscli k9s jq
tfenv install 1.16.4 && tfenv use 1.16.4
brew install --cask temurin@25

# Node (frontend)
npm create vite@latest frontend -- --template react-ts
npm i react@19.3.0 react-dom@19.3.0
npm i -D vite@8.3.0 @vitejs/plugin-react@6.1.1 typescript@7.0.2

# Scanners
brew install trivy checkov
```

```hcl
# versions.tf — the pins that matter
terraform {
  required_version = ">= 1.13, < 2.0"
  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 6.66" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }  # [UNVERIFIED version]
    helm       = { source = "hashicorp/helm",       version = "~> 3.0"  }  # [UNVERIFIED version]
    tls        = { source = "hashicorp/tls",        version = "~> 4.0"  }  # required >= 4.0 by EKS v21
  }
}
```

**Split state into three stacks.** This is a direct consequence of your daily-teardown constraint:

| Stack | Lifecycle | Contents |
|---|---|---|
| `00-bootstrap` | **Never destroyed** | S3 state bucket, DynamoDB lock table, ECR repos, GitHub OIDC provider + roles, AWS Budgets |
| `10-platform` | **Rarely destroyed** | CloudFront + S3 SPA bucket, Route53 (none), Secrets Manager secrets |
| `20-cluster` | **Destroyed daily** | VPC, fck-nat, EKS, MNG, Karpenter IAM/SQS, RDS, ElastiCache, DynamoDB tables |

`make down` only destroys `20-cluster`. This keeps ECR images and CloudFront warm (making `make up` far faster) while dropping to near-zero idle cost. **ECR storage is $0.10/GB/month** — 6 service images at ~200 MB is ~$0.12/month. `[UNVERIFIED — ECR price not re-fetched.]`

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| **Terraform 1.16.4** | **OpenTofu 1.12.6** | OpenTofu is a genuinely viable drop-in and adds **native state encryption** + early variable evaluation. Choose it if BUSL licensing matters to you or you want state encryption without KMS-in-backend plumbing. **Not recommended here** only because registry modules (EKS v21) are CI-tested against Terraform, and a module/tofu incompatibility would burn learning budget on the wrong problem. Confidence: MEDIUM (opinion). |
| Terraform EKS module | **eksctl** | eksctl is fine for throwaway clusters and its Karpenter/addon wiring is pleasant, but it **cannot express your VPC + fck-nat + RDS + DynamoDB + IAM estate**, and you'd end up with two sources of truth. Your project requires *everything* in Terraform. Not a real option. |
| Karpenter | Cluster Autoscaler | CA only scales pre-defined ASGs — no bin-packing, no instance-type flexibility, and much worse Spot diversification. Strictly worse for both cost and learning here. |
| **Pod Identity** | IRSA | Only for controllers without Pod Identity support, or if you specifically want to practise OIDC trust policies (defensible — it *is* a SAP-C02 topic). |
| **Loki SingleBinary** | Loki microservices mode | Only at >20GB/day. SSD mode is **not** an option — deprecated, removed in Loki 4.0. |
| **Tempo (monolithic)** | tempo-distributed | Never, at this scale. 5+ extra pods. |
| **Grafana Alloy** | Promtail | Never — **EOL 2026-03-02**. |
| **Spring Boot 4.1.1** | Spring Boot 3.5.16 | If you hit a third-party starter that hasn't migrated to Boot 4's modularised autoconfiguration. Fall back as a *set*: Boot 3.5.16 + Spring Cloud 2025.0.x + Spring Cloud AWS 3.4.2 + Gateway 4.3.5. |
| **Gateway Server Web MVC** | Gateway Server WebFlux | Only if practising reactive backpressure is itself a goal. |
| **OTel Java agent** | OTel Spring Boot starter | Required if you go GraalVM native (agent is unsupported there), or if agent startup latency ever matters. |
| **Trivy `config`** | Checkov | Run both. They catch different things; that's the point. |
| **Spring Cloud Contract** | Pact | If M2 adds a non-JVM HTTP consumer. |
| **fck-nat** | NAT Gateway | If a chaos scenario needs NAT to be genuinely HA, or if you ever exceed ~5 Gbps. Neither applies. |
| **Kyverno** | Gatekeeper/OPA | Gatekeeper if you want to practise Rego specifically. Kyverno's YAML-native policies are lighter and the ecosystem has consolidated on it. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| **tfsec** | Officially merged into Trivy; repo title is "Tfsec is now part of Trivy". Unmaintained. | `trivy config` |
| **Promtail** | **EOL 2026-03-02.** No support, no updates. | **Grafana Alloy** `1.12.1` / `v1.19.2` |
| **Loki SSD / `deploymentMode: SimpleScalable`** | **Deprecated; removed in Loki 4.0.** And it's the chart default, so you must opt *out*. | `deploymentMode: SingleBinary` |
| **`tempo-distributed` chart** | 5+ components for a cluster that produces a trickle of spans. | `tempo` chart `1.24.4` |
| **EKS module v19/v20 + `aws-auth` submodule** | Removed in v21. Access Entries are the only supported path. | `terraform-aws-modules/eks/aws ~> 21.26` + `access_entries` |
| **Karpenter `v1beta1` Provisioner/AWSNodeTemplate/NodePool YAML** | API removed. `kubelet` moved, `nodeClassRef` shape changed, `amiSelectorTerms` now required. | `karpenter.sh/v1` + `karpenter.k8s.aws/v1` |
| **AWS Node Termination Handler** | Karpenter handles interruptions natively; NTH additionally reacts to Rebalance Recommendations and the Karpenter docs explicitly warn this **increases node churn**. | Karpenter's SQS/EventBridge interruption queue alone |
| **10 interface VPC endpoints "to avoid NAT"** | **~$73/month — 2.4× a NAT Gateway and 19× fck-nat.** Verified $0.01/endpoint/AZ/hour. | fck-nat + free S3/DynamoDB **gateway** endpoints only |
| **CloudFront OAI** | Legacy; no SSE-KMS support, no new-region support, feature-frozen. | **OAC** (`aws_cloudfront_origin_access_control`) |
| **GraalVM native image (M1)** | Adds minutes per service per build, breaks the OTel Java agent, needs reachability metadata for Testcontainers/Gateway/proxies. Burns infra learning budget on JVM tooling. | JVM + Java 25 **AOT cache** (`-XX:AOTCache`) |
| **Testcontainers `org.testcontainers:postgresql`** | Artifact IDs changed in 2.0 → `testcontainers-postgresql`. | `testcontainers-bom:2.0.5` + `testcontainers-*` artifacts |
| **`-Xmx` fixed heap in containers** | Breaks when you resize the pod; doesn't account for off-heap. | `-XX:MaxRAMPercentage=70.0` |
| **G1GC on sub-2GiB pods** | Region + remembered-set overhead is pure waste; JVM ergonomics pick it automatically at ≥2 CPU/1792MB. | `-XX:+UseSerialGC` below ~2 GiB |
| **Multi-AZ fck-nat / multi-AZ RDS** | Doubles cost for HA you explicitly don't need, plus cross-AZ data transfer. | Single AZ; make the SPOF a chaos scenario |
| **Karpenter NodePool with no `limits`** | An HPA misconfiguration becomes an unbounded bill. | Always set `limits: {cpu, memory}` |
| **Spot for the system/Karpenter node group** | Karpenter cannot reschedule the node it runs on. Losing it deadlocks the cluster. | 2 × `t4g.small` **On-Demand** MNG |
| **Pinning EKS addon versions from a tutorial** | v21 changed defaults to `most_recent = true` / `resolve_conflicts_on_create = "NONE"`. | Let the module manage addon versions |
| **Argo CD `dex` + `notifications`** | Two pods, zero value for a single operator with no Slack. | `dex.enabled=false`, `notifications.enabled=false` |

---

## Version Compatibility Matrix

| Component | Must be compatible with | Constraint | Source |
|---|---|---|---|
| `terraform-aws-modules/eks/aws` 21.x | Terraform | **>= 1.5.7** | v21 upgrade guide |
| `terraform-aws-modules/eks/aws` 21.x | AWS provider | **>= 6.0** | v21 upgrade guide |
| `terraform-aws-modules/eks/aws` 21.x | TLS provider | **>= 4.0** | v21 upgrade guide |
| Karpenter 1.14.1 | Kubernetes 1.34 | ✅ (needs >= 1.6) | Karpenter compat matrix |
| Karpenter 1.14.1 | Kubernetes 1.36 | ✅ (needs >= 1.13) | Karpenter compat matrix |
| kube-prometheus-stack 91.5.1 | Kubernetes | `>= 1.25.0-0` | chart `kubeVersion` |
| Spring Boot 4.1.1 | Java | **17 – 26** (use 25 LTS) | Spring Boot system requirements |
| Spring Boot 4.1.1 | Spring Framework | **>= 7.0.9** | Spring Boot system requirements |
| Spring Boot 4.1.1 | Maven / Gradle | Maven >= 3.6.3 / Gradle 8.14+ or 9.x | Spring Boot system requirements |
| Spring Boot 4.1.1 | Tomcat | 11.0.x (Servlet 6.1) | Spring Boot system requirements |
| Spring Boot 4.1.1 | GraalVM (if used) | Community **25** + Native Build Tools **1.1.8** | Spring Boot system requirements |
| Spring Cloud 2025.1.3 | Spring Boot | 4.1.x | Maven Central alignment |
| Spring Cloud Gateway 5.0.3 | Spring Boot 4 / Framework 7 | ✅ explicit | SCG reference docs |
| Spring Cloud AWS 4.1.1 | Spring Boot | 4.x | Maven Central |
| OTel Java instrumentation 2.31.1 | Spring Boot 4 | ✅ (WebMVC, WebFlux, SCG, actuator, starter) | OTel CHANGELOG |
| EKS Pod Identity | AWS SDK Java v2 | recent; 2.55.4 far exceeds floor | `[UNVERIFIED floor]` |
| EKS standard support | Kubernetes | **1.36, 1.35, 1.34** (14 months) | EKS docs |
| EKS extended support | Kubernetes | 1.33, 1.32, 1.31 (+12 months, **$0.60/hr**) | EKS docs + pricing |

---

## Cost Model Sanity Check

| Item | Idle (stack destroyed) | Active (per hour) |
|---|---|---|
| EKS control plane | $0.00 | **$0.100** |
| 2 × `t4g.small` On-Demand MNG | $0.00 | ~$0.034 |
| Karpenter Spot nodes (~2 × `t4g.medium` spot) | $0.00 | ~$0.025 |
| fck-nat `t4g.nano` | $0.00 | ~$0.004 |
| RDS Postgres `db.t4g.micro` single-AZ | $0.00 | ~$0.016 |
| ElastiCache `cache.t4g.micro` | $0.00 | ~$0.017 |
| ALB | $0.00 | ~$0.023 |
| EBS (nodes + RDS) | $0.00 | ~$0.010 |
| **Active total** | | **~$0.23/hr ✅** (budget $0.30) |
| S3 (state + Loki/Tempo) | ~$0.50/mo | |
| DynamoDB (lock + app tables, on-demand) | ~$0.10/mo | |
| ECR (6 images) | ~$0.15/mo | |
| CloudFront + S3 SPA | ~$0.10/mo | |
| **Idle total** | **~$0.85/mo ✅** (budget $5) | |

`[UNVERIFIED — only the EKS control plane ($0.10/hr) and the VPC endpoint ($0.01/endpoint-hour) rates were fetched from authoritative AWS sources this session. All other line items are estimates and must be validated against the AWS Pricing Calculator in Phase 1.]`

**Headroom is thin at ~$0.23/hr against a $0.30 ceiling.** Two structural levers if you exceed it:
1. **Stop RDS + ElastiCache between sessions rather than destroying them.** A stopped RDS instance bills only storage — but AWS **auto-starts a stopped RDS instance after 7 days**, which is a silent-bill trap. Destroy + snapshot-restore is safer for your rhythm, at the cost of restore time.
2. **Drop ElastiCache; run Redis as a pod.** Saves ~$0.017/hr and removes a slow-to-provision resource from the critical path of `make up`. You lose the "managed Redis" practice, which is a real but small loss.

---

## Sources

All fetched live on **2026-09-24**. Provider: direct HTTPS (`curl`) — no search MCP available.

| Source | What was verified | Confidence |
|---|---|---|
| GitHub `releases/latest` redirects (26 repos) | Terraform 1.16.4, OpenTofu 1.12.6, AWS provider 6.66.0, EKS module 21.26.0, Karpenter 1.14.1, Argo CD 3.5.3, ALB Controller 3.5.0, ESO chart 2.11.0, Kyverno 1.19.1, metrics-server 0.9.0, EBS CSI 1.66.0, OTel Java 2.31.1, Spring Boot 4.1.1, AWS SDK Java 2.55.4, Trivy 0.74.0, Checkov 3.3.19, configure-aws-credentials 6.3.0, Testcontainers 2.0.5, LocalStack 4.14.0, fck-nat 1.6.1 | **HIGH** |
| `repo1.maven.org` `maven-metadata.xml` | All Java artifact versions (authoritative; note `search.maven.org` solr index was returning **stale** data and was discarded) | **HIGH** |
| `registry.npmjs.org` | React 19.3.0, Vite 8.3.0, plugin-react 6.1.1, TypeScript 7.0.2 | **HIGH** |
| `registry.terraform.io/v1/modules/*` | Module latest versions + publish dates (fck-nat 1.6.1 pub. 2026-08-15, 813k dl/mo → actively maintained) | **HIGH** |
| Helm `index.yaml` (prometheus-community, grafana, aws/eks-charts, argoproj, kyverno) | kube-prometheus-stack 91.5.1 / operator v0.94.1 / `kubeVersion >=1.25.0-0`; loki 7.3.0 / 3.6.12; tempo 1.24.4 / 2.9.0; grafana 10.5.15; alloy 1.12.1 / v1.19.2; argo-cd 10.9.2 / v3.5.3; aws-load-balancer-controller 3.5.0; kyverno 3.9.1 | **HIGH** |
| `docs.aws.amazon.com/eks/.../kubernetes-versions.html` | Standard support 1.36/1.35/1.34; extended 1.33/1.32/1.31; 14+12 month windows; 7-day rollback | **HIGH** |
| `aws.amazon.com/eks/pricing/` | $0.10/cluster/hr standard, $0.60/hr extended | **HIGH** |
| `pricing.us-east-1.amazonaws.com/.../AmazonVPC/.../us-east-1/index.json` | Interface endpoint **$0.01/endpoint-hour**; $0.01/GB; gateway endpoints free | **HIGH** |
| `raw.githubusercontent.com/.../terraform-aws-eks/master/docs/UPGRADE-21.0.md` | Full v20→v21 breaking-change list, incl. Karpenter IRSA removal + Pod Identity default, `aws-auth` removal, addon default changes, `oidc-eks` endpoint change | **HIGH** |
| `karpenter.sh/docs/concepts/{nodepools,nodeclasses,disruption}/` + `/upgrading/compatibility/` | v1 API shapes, kubelet relocation, interruption event list, SQS/EventBridge requirement, Rebalance-Recommendation caveat, k8s compat matrix | **HIGH** |
| `docs.aws.amazon.com/eks/.../pod-identities.html` | Pod Identity vs IRSA tradeoffs, `pods.eks.amazonaws.com` principal, 5,000 association limit | **HIGH** |
| `grafana.com/docs/loki/latest/get-started/deployment-modes/` | **SSD deprecated, removed in Loki 4.0**; monolithic good to ~20GB/day | **HIGH** |
| `grafana.com/docs/loki/latest/send-data/promtail/` | **Promtail EOL 2026-03-02**; migrate to Alloy | **HIGH** |
| `github.com/aquasecurity/tfsec` (page title) | **"Tfsec is now part of Trivy"** | **HIGH** |
| `docs.spring.io/spring-boot/system-requirements.html` | Java 17–26, Framework 7.0.9+, Maven 3.6.3+, Tomcat 11, GraalVM 25 / NBT 1.1.8; stable lines 4.1.1 / 4.0.8 / 3.5.16 | **HIGH** |
| `docs.spring.io/spring-cloud-gateway/reference/` | Server WebFlux vs Server Web MVC flavours; 5.0.3 stable on Framework 7 / Boot 4 | **HIGH** |
| `raw.githubusercontent.com/.../opentelemetry-java-instrumentation/main/CHANGELOG.md` | Explicit Spring Boot 4 support entries for starter, WebMVC, WebFlux, Spring Cloud Gateway, actuator | **HIGH** |
| `external-secrets.io/latest/api/externalsecret/` | API is `external-secrets.io/v1`; generators `v1alpha1`; refreshPolicy/immutable semantics | **HIGH** |
| `java.testcontainers.org` | 2.0.5; **artifact IDs now `testcontainers-<module>`** | **HIGH** |

### Explicitly NOT verified — treat as MEDIUM/LOW and confirm in Phase 1

1. **Argo CD chart 10.9.2 default resource requests** — footprint figures are estimates. Read `values.yaml`.
2. **Observability stack total memory footprint** (~2.5–4 GiB) — estimate only.
3. **NAT Gateway hourly rate, EC2/RDS/ElastiCache/ALB/EBS/ECR rates** — the entire cost model except EKS control plane and VPC endpoints. Validate with the AWS Pricing Calculator.
4. **CloudFront free-tier terms** (1 TB / 10M req perpetual).
5. **GitHub OIDC provider thumbprint no longer required.**
6. **Minimum AWS SDK for Java v2 version for Pod Identity.**
7. **`kubernetes` and `helm` Terraform provider current versions** — placeholder constraints above.
8. **JVM flag impact percentages** (`UseCompactObjectHeaders` ~10–20%) and `t4g.nano` baseline bandwidth.
9. **Full Testcontainers 2.0 breaking-change list** beyond the artifact-ID rename.
10. **GraalVM native build time per service** (3–8 min estimate).

### Recommended PROJECT.md corrections

- `"tfsec/Checkov IaC scanning"` → **`"Trivy config + Checkov IaC scanning"`** (tfsec is dead).
- `"IRSA / EKS Pod Identity"` → **`"EKS Pod Identity (IRSA only where unavoidable)"`** — IRSA's cluster-bound OIDC trust policies actively fight your daily-rebuild constraint.
- Add an explicit requirement: **`"make down` must delete Argo CD Applications and verify no orphaned ELBs/ENIs/security groups before destroying the VPC."`** This is the single most likely cause of a broken teardown.

---
*Stack research for: cost-constrained teardown-per-day AWS EKS microservices practice platform*
*Researched: 2026-09-24*
