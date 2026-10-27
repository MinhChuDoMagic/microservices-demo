# Phase 3: Service Scaffolding & CI Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-27
**Phase:** 3-Service Scaffolding & CI Pipeline
**Areas discussed:** Spring Boot line (OQ6), Service template & generation, Container image build, CI shape & real-AWS boundary
**Todo folded:** rescope-local-phases.md (Phase 3 portion)

---

## Spring Boot line (OQ6)

| Option | Description | Selected |
|--------|-------------|----------|
| Spring Boot 4.1.1 set | Boot 4.1.1 + Cloud 2025.1.3 + Cloud AWS 4.1.1 + Gateway Server Web MVC | ✓ |
| Spring Boot 3.5.16 set | Boot 3.5.16 + Cloud 2025.0.x + Cloud AWS 3.4.2 + Gateway 4.3.5 | |
| You decide | Decide from probe result | |

| Option | Description | Selected |
|--------|-------------|----------|
| Starter compatibility probe | Throwaway module with every M1 starter must compile and start | ✓ |
| Skeletons only | web + actuator; discover later | |

| Option | Description | Selected |
|--------|-------------|----------|
| Whole-set fallback | Any incompatible starter → whole 3.5.16 set | |
| Prefer workaround | Stay on Boot 4, work around the lagging starter | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Workarounds stay version-aligned | No Boot-3-era starter pinned onto Boot 4 | |
| Any workaround is fine | | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Temurin 25 | LTS, compact object headers, generational ZGC | ✓ |
| Temurin 21 | | |

**Notes:** "Any workaround is fine" overrides the ROADMAP's "never piecemeal" guidance; workarounds must be recorded.

---

## Service template & generation

| Question | Options | Selected |
|----------|---------|----------|
| Skeleton count | All six now / Template + one exemplar | All six now |
| Build tool | Maven multi-module / Gradle | Gradle |
| Parent POM equivalent | Convention plugin + catalog, reword docs / Keep wording | Convention plugin + catalog, reword docs |
| Gradle DSL | Kotlin / Groovy | Groovy |
| Generation | `make new-service NAME=x` / Maven archetype / Manual copy | `make new-service NAME=x` |
| K8s template | Shared Helm chart / Kustomize base / You decide | Shared Helm chart |
| JVM flags location | Helm chart env / Image ENTRYPOINT | Helm chart env |

---

## Container image build

| Question | Options | Selected |
|----------|---------|----------|
| Image tool | Multi-stage Dockerfile / Jib / Buildpacks | Multi-stage Dockerfile |
| Base image | Temurin JRE / jlink on distroless / Distroless Java 25 | Free text: "it's up to you" |
| Pinning | Digest + bot / Digest manual / Tag only | Digest + bot updates |
| OTel agent | Bake disabled / Bake enabled / Defer to Phase 5 | Bake now, enabled |
| OTel export | Exporters none until Phase 5 / OTLP default endpoint | Exporters none until Phase 5 |
| Image tag | Git SHA only / SHA + semver | Git SHA only |
| Local build | `make image SVC=x` / CI only | `make image SVC=x` |
| Image size | Record / Gate / Ignore | Record, don't gate |
| Non-root | Now / Defer to Phase 10 | Non-root UID now |

---

## CI shape & real-AWS boundary

| Question | Options | Selected |
|----------|---------|----------|
| AWS boundary | Real ECR + OIDC, no cluster / Strictly local | Real ECR + OIDC; no cluster |
| Apply scope | Plan all, apply L0 only / Plan+apply L0 only / Apply all on merge | Plan all, apply L0 only |
| Triggers | Per-service path-filter matrix / Build all | Per-service path-filter matrix |
| Push when | develop only / PRs too | Push on develop only |
| CVE gate | HIGH+CRITICAL fixable only / incl. unfixed | HIGH+CRITICAL, fixable only |
| ECR push role | Dedicated ECR-push role / Reuse apply role | Dedicated ECR-push OIDC role |
| Disagreement doc | Fixture + docs/SCANNER-DISAGREEMENTS.md / ADR / You decide | Fixture + docs/SCANNER-DISAGREEMENTS.md |
| CVE proof | Throwaway PR + manual ECR push / Permanent negative test | Throwaway PR + manual ECR push |

---

## the agent's Discretion

- Runtime base image selection
- Probe paths/timings, preStop length, grace period, metaspace/direct-memory caps
- Renovate vs Dependabot; library vs common chart; build-logic vs buildSrc
- Starter probe location/lifetime; image-size recording format

## Deferred Ideas

- rescope-local-phases.md — non-Phase-3 portions remain pending
