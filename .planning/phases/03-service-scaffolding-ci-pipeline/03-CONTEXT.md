# Phase 3: Service Scaffolding & CI Pipeline - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the service and CI template exactly once: six Spring Boot skeletons (`api-gateway`, `catalog`, `cart`, `order`, `payment-sim`, `inventory`) on a shared Gradle build convention, a shared Kubernetes deployment template carrying JVM sizing, probes, `preStop`, and graceful shutdown, and GitHub Actions pipelines that build, test, scan, and publish arm64 images to ECR and run Terraform plan/apply through OIDC. Requirements: SVC-09, CD-04, CD-06, SEC-06, SEC-07. No cluster is provisioned and nothing is deployed — Phase 4 deploys. No business logic in the skeletons.

</domain>

<decisions>
## Implementation Decisions

### Spring Boot line (OQ6)
- **D-01:** Pin the Spring Boot **4.1.1** set: Spring Boot 4.1.1, Spring Cloud 2025.1.3, Spring Cloud AWS 4.1.1, Spring Cloud Gateway Server Web MVC (versions per `.planning/research/STACK.md`). — **Reversibility:** costly — every service's build and every starter dependency moves together.
- **D-02:** Runtime JDK is **Temurin 25 (LTS)**.
- **D-03:** Prove the set with a **starter compatibility probe** before the skeletons depend on it: a throwaway/probe module that pulls every starter Milestone 1 will need (web, actuator, Gateway Server Web MVC, Spring Cloud AWS SQS/DynamoDB/EventBridge/SNS, JDBC + Flyway + Postgres, Redis, OTel, Testcontainers, Spring Cloud Contract) and compiles and starts.
- **D-04:** If a starter is incompatible with 4.1.1, **prefer a workaround over falling back** to the 3.5.16 set. The operator explicitly accepted *any* workaround, including version-mismatched pins. This overrides the ROADMAP OQ6 "fall back as a set, never piecemeal" guidance. Each workaround must be recorded (what, why, which starter) in the version catalog comments and in the phase summary so it stays visible.

### Service template & generation
- **D-05:** Create **all six skeletons now** — each with actuator, health groups, and a trivial endpoint only — so Phase 4 has real artifacts to deploy.
- **D-06:** Build tool is **Gradle with Groovy DSL** (not Maven). — **Reversibility:** costly — build files, CI cache, and generator all assume Gradle.
- **D-07:** The "shared parent POM" is realised as a **Gradle version catalog (`gradle/libs.versions.toml`) plus a convention plugin** (`build-logic/` included build or `buildSrc`). Reword SVC-09 in `.planning/REQUIREMENTS.md` and ROADMAP Phase 3 SC1 from "parent POM" to "shared Gradle build convention" as part of this phase.
- **D-08:** Service generation is a Makefile target: **`make new-service NAME=x`** — copies a template, renames it, registers it in `settings.gradle`, the CI build matrix/path filters, and the ECR `var.services` list.
- **D-09:** Kubernetes-side template is a **shared Helm chart** (library chart or common chart) owning startup/readiness/liveness probes, `preStop` sleep, `terminationGracePeriodSeconds`, resources, security context, and JVM env. Per-service charts/values provide only overrides. (Note: `.planning/research/ARCHITECTURE.md` sketched "Kustomize overlays" under `gitops/ecommerce/`; this decision supersedes that sketch.)
- **D-10:** JVM sizing (`MaxRAMPercentage=65`, capped metaspace and direct memory, `ExitOnOutOfMemoryError`) is delivered via **`JAVA_TOOL_OPTIONS` in the shared Helm chart's defaults**, not baked into the image entrypoint. Per-service override via values.

### Container image build
- **D-11:** Images are built with a **multi-stage Dockerfile** using Spring Boot layer extraction (explicit dependency/application layers).
- **D-12:** Base images **pinned by digest**, with Renovate or Dependabot proposing bumps.
- **D-13:** The **OTel Java agent is baked into the image now and enabled**, pinned by version. Until Phase 5 provides a collector, the shared chart sets `OTEL_TRACES_EXPORTER=none`, `OTEL_METRICS_EXPORTER=none`, `OTEL_LOGS_EXPORTER=none`; Phase 5 only flips exporters/endpoint.
- **D-14:** Image tags are the **full git SHA only** — no `latest`, no semver. Consistent with ECR `IMMUTABLE` tags (Phase 1 D-21).
- **D-15:** Operator can build locally with **`make image SVC=x`** (native arm64 on Apple Silicon — same architecture as CI).
- **D-16:** **Record compressed image size per service** (CI summary and/or `COSTS.md`); do not gate on it.
- **D-17:** Images run as a **fixed non-root UID** (e.g. 10001) with a read-only-root-filesystem-friendly layout from day one, so Phase 10 Kyverno PSS Restricted needs no template change.

### CI shape & real-AWS boundary
- **D-18:** Phase 3 uses **real AWS only for cluster-free resources**: ECR repositories (immortal L0), ECR scan-on-push, and the OIDC plan/apply path. No cluster, no L1–L3 apply. Unit tests, Trivy, and Checkov run offline. Amend `.planning/notes/real-vs-local-deploy-policy.md` to record this Phase 3 exception.
- **D-19:** ECR repositories go into `layers/00-bootstrap` per Phase 1 D-21: `for_each` over `var.services`, `scan_on_push = true`, `IMMUTABLE` tags, lifecycle policy keeping the last 10 images. Add new repos to `sh/teardown-allowlist.txt`/Layer-tag handling only as the existing sweep contract requires.
- **D-20:** Terraform CI: **`plan` on PRs for all four layers** (plan role); **`apply` on merge to `develop` for `00-bootstrap` only** (apply role). Daily layers stay owned by `make up`/`make down` — a merge must never create billable cluster infrastructure. — **Reversibility:** reversible.
- **D-21:** Service CI uses a **per-service path-filtered matrix**; changes to the shared Gradle convention, version catalog, Dockerfile template, or shared chart rebuild all services.
- **D-22:** PRs build, test, and scan **without pushing**; images are pushed to ECR **only on `develop`**.
- **D-23:** Pushing uses a **new dedicated ECR-push OIDC role** in L0, trusted only from `develop` (immutable-ID subject format per Phase 1), permissions limited to push/pull on the project's ECR repositories. The apply role is not used for image builds.
- **D-24:** Runners: **`ubuntu-24.04-arm`** for image builds — no QEMU/buildx emulation anywhere in the build log (SC2).
- **D-25:** Image CVE gate: Trivy **fails on HIGH/CRITICAL with a fix available**; unfixed CVEs are reported but non-blocking. Exceptions go in `.trivyignore` with a reason and an expiry date.
- **D-26:** SC4 is proved by a **deliberately insecure Terraform fixture** at `tests/fixtures/iac-insecure/` scanned by both Trivy `config` and Checkov in CI (expected-fail job, not blocking real layers); the real layers are scanned with blocking gates. Disagreements are written up in **`docs/SCANNER-DISAGREEMENTS.md`**.
- **D-27:** SC3 is proved by a **throwaway PR** adding a known-vulnerable dependency (CI goes red) plus a **manual push of that image to a scratch tag** so ECR scan-on-push reports it independently. Evidence goes in the phase verification doc; the branch is discarded.

### the agent's Discretion
- Runtime base image choice (e.g. `eclipse-temurin:25-jre`, distroless Java 25, or a jlink-trimmed runtime) — weigh CVE surface, size, and debuggability; must support non-root (D-17) and digest pinning (D-12).
- Exact probe paths/timings, `preStop` sleep length, and `terminationGracePeriodSeconds` values, metaspace/direct-memory cap numbers.
- Renovate vs Dependabot; library chart vs common chart mechanics; `build-logic` vs `buildSrc`.
- Where the starter probe lives and whether it is kept after the phase.
- Exact image-size recording location and format.

### Folded Todos
- **Rescope success criteria for local-only phases** (`.planning/todos/pending/rescope-local-phases.md`) — Phase 3 portion only. Resolved by D-18: SC2, SC3, SC5 keep real ECR/OIDC (cluster-free, L0/IAM only); no SC rewording needed beyond the D-07 "parent POM" wording. Other phases in that todo remain pending.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase contract and project constraints
- `.planning/ROADMAP.md` §"Phase 3: Service Scaffolding & CI Pipeline" — goal, SC1–SC5, OQ6 decision gate, research flags (arm64 chart audit, Boot 4.1.1 starter compatibility).
- `.planning/REQUIREMENTS.md` — SVC-09, CD-04, CD-06, SEC-06, SEC-07 (SVC-09 wording to be updated per D-07).
- `.planning/PROJECT.md` §"Constraints", §"Key Decisions" — no long-lived credentials, cost model, learning-first.
- `.planning/notes/real-vs-local-deploy-policy.md` — local-only policy; amend for D-18.
- `.planning/todos/pending/rescope-local-phases.md` — folded (Phase 3 portion).

### Inherited decisions
- `.planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md` — D-20/D-21 (ECR in L0, `scan_on_push`, `IMMUTABLE`, keep 10), OIDC subject format and role separation, tagging conventions.
- `.planning/phases/02-ephemeral-infrastructure-drain-scripts/02-CONTEXT.md` — `make` as lifecycle entry point; L1–L3 never applied outside `make up`/`make down`.
- `docs/CONVENTIONS.md` — exact pins, four default tags, Makefile-only Terraform init.

### Stack and pitfalls research
- `.planning/research/STACK.md` — Spring Boot 4.1.1 set, Temurin 25, OTel agent baking pattern (multi-stage copy, no init container), compatibility table.
- `.planning/research/SUMMARY.md` §"OQ6" and Phase 1b deliverables.
- `.planning/research/PITFALLS.md` — Pitfalls 26–29 (template-once problems), digest pinning, image size/jlink guidance.
- `.planning/research/ARCHITECTURE.md` §repo layout (`services/`, `gitops/`) and P1b — note D-09 supersedes its Kustomize sketch.

### Existing CI
- `.github/workflows/oidc-plan-role-smoke.yml`, `.github/workflows/oidc-apply-role-smoke.yml` — current OIDC smoke workflows; both explicitly defer real plan/apply to CD-06. Extend or replace.
- `.github/workflows/scheduled-teardown-sweep.yml` — existing sweep role usage pattern.
- `layers/00-bootstrap/oidc.tf` — existing plan/apply/sweep roles; new ECR-push role (D-23) goes here.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Makefile` — lifecycle entry point; add `new-service` and `image` targets alongside existing `doctor`/`up`/`down`.
- `layers/00-bootstrap/oidc.tf` — role/trust-policy pattern with immutable-ID subjects to copy for the ECR-push role.
- Existing OIDC smoke workflows — already do `terraform init -backend=false` + `validate` per layer with Terraform 1.17.0 and `aws-actions/configure-aws-credentials`.
- `tests/static_contracts.bats` + `tests/helpers/load.bash` — Bats static-contract convention for asserting workflow/Terraform properties (e.g. no QEMU, push only on develop).

### Established Patterns
- Exact version pinning everywhere (Terraform, providers, now Gradle catalog and base-image digests).
- Four default tags (`Project`, `Layer`, `ManagedBy`, `Environment`); ECR repos tagged `Layer` = bootstrap.
- `develop` is the only apply/sweep branch; plan role trusts PRs only.
- Fail-closed shell scripts; generated root `backend.hcl` for Terraform init.

### Integration Points
- `var.services` in L0 must stay in sync with `services/*` and the CI matrix — `make new-service` updates all three.
- Phase 4 consumes the shared Helm chart and SHA-tagged images from ECR via Argo CD.
- Phase 5 consumes the baked OTel agent by setting exporter env only.
- `verify-teardown.sh` must continue to treat L0 ECR repos as immortal (not orphans).

</code_context>

<specifics>
## Specific Ideas

- Operator prefers Gradle with Groovy DSL despite roadmap text saying "parent POM" — docs get reworded rather than ignored.
- OTel agent on from day one but silent (exporters `none`) — avoids connection-refused noise before Phase 5.
- CVE proof is a deliberate, discarded experiment, not a permanent negative test.
- Merges must never create billable cluster infrastructure.

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- `rescope-local-phases.md` — portions for Phases 5, 6, 7, 9, 10, 11, 12, 14 remain pending; out of Phase 3 scope.

</deferred>

---

*Phase: 3-Service Scaffolding & CI Pipeline*
*Context gathered: 2026-10-27*
