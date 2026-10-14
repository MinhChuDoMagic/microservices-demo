---
phase: "02"
slug: "ephemeral-infrastructure-drain-scripts"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-14"
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.14.0; ShellCheck 0.11.0 |
| **Config file** | `tests/` Bats suites and `tests/helpers/load.bash` |
| **Quick run command** | `bats tests/phase2_lifecycle.bats` |
| **Full suite command** | `make test` |
| **Infrastructure validation** | `make validate` |
| **Estimated runtime** | ~60 seconds for local checks; live AWS acceptance is separate |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/phase2_lifecycle.bats` and targeted ShellCheck for edited scripts.
- **After every plan wave:** Run `make test` and `make validate`.
- **Before `/gsd-verify-work`:** Full suite must be green; live acceptance gates below must be complete.
- **Max feedback latency:** 60 seconds for local checks.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| Pending planner task mapping | Pending | 0/1 | LIFE-01, LIFE-02, LIFE-06 | — | Failed or unknown AWS state never counts as clean; no application code before two clean cycles | unit + live acceptance | `bats tests/phase2_lifecycle.bats`; two live `make up`/`make down` cycles | ❌ W0 | ⬜ pending |
| Pending planner task mapping | Pending | 0/1 | LIFE-03, LIFE-04 | — | First failed drain stops teardown before Terraform destroy; AWS terminal state is polled under one shared deadline | contract + stubbed integration | `bats tests/phase2_lifecycle.bats` | ❌ W0 | ⬜ pending |
| Pending planner task mapping | Pending | 0/1 | NET-01, NET-02, NET-03, NET-04, NET-05, NET-07 | — | Intra subnets have no default route; interface endpoints default off; NAT routes target the persistent ENI | static + live infrastructure | `make test`; `make validate`; live network probes | ❌ W0 | ⬜ pending |
| Pending planner task mapping | Pending | 0/1 | EKS-01, EKS-02, EKS-04, EKS-08 | — | EKS minor/add-ons are pinned; Karpenter AWS resources remain Terraform-owned | static + AWS API + live infrastructure | `make test`; `make validate`; `aws eks describe-addon-versions --region us-east-1 --kubernetes-version 1.34` | ❌ W0 | ⬜ pending |
| Pending planner task mapping | Pending | 0/1 | OWN-02 | — | L1 contains no Kubernetes or Helm Terraform provider | static contract | `make test` | ✅ existing suite | ⬜ pending |

*The planner must replace provisional task mappings with the final PLAN.md task IDs and wave assignments before this strategy is considered complete.*

---

## Wave 0 Requirements

- [ ] `tests/phase2_lifecycle.bats` — exact teardown order, partial-state handling, idempotent rerun, bounded retries, shared deadline, preserved errors, verifier exit codes, and stop-before-destroy behavior.
- [ ] AWS EKS/ELBv2/EC2/EBS fixtures — terminal absence, transient API errors, and unknown/error states.
- [ ] Recovery-tool safety test — tagged disposable target appears in preview; same-type untagged control does not; VPC type is absent from executable allowlist.
- [ ] Pin a `kubectl` client compatible with EKS 1.34 before live drain acceptance.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Two consecutive clean, zero-orphan up/down cycles within the wall-clock limits | LIFE-01, LIFE-02, LIFE-06 | Requires real AWS lifecycle timing and the existing account teardown verifier | Run two complete cycles on an empty cluster; record each successful duration and verifier exit 0 in `COSTS.md`; do not start application code until both pass. |
| AWS-confirmed ALB drain while deletion is in progress | LIFE-04 | A no-op empty-cluster drain cannot prove asynchronous controller cleanup | Create a temporary non-application Ingress fixture, run `make down`, and capture the AWS-observed ALB terminal state before destroy proceeds. |
| Recovery command stays within project-tagged resource scope | LIFE-03 | Requires a disposable tagged resource and same-type untagged control against the selected recovery tool | Preview both controls; prove only the tagged target is eligible, verify VPC is excluded, and report uncovered resources without widening scope. |
| Operator can reach the EKS API using the approved access path | LIFE-03, LIFE-04 | Depends on the selected network and identity path, not unit-test stubs | From the normal operator environment, authenticate to the Phase 2 cluster and run the drain preflight without opening the endpoint to `0.0.0.0/0`. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter after task mapping and validation

**Approval:** pending