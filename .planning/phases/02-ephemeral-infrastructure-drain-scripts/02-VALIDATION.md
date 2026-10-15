---
phase: "02"
slug: "ephemeral-infrastructure-drain-scripts"
status: validated
nyquist_compliant: true
wave_0_complete: true
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

Every planned task is mapped below. Automated commands are planned verifications, not completed results; all task statuses remain pending until execution.

| Task ID | Plan | Wave | Requirement | Verification type | Automated command | Manual gate / status |
|---------|------|------|-------------|-------------------|-------------------|----------------------|
| 02-01-01 | 02-01 | 1 | LIFE-02, LIFE-03, LIFE-04, LIFE-06 | TDD tracer + lifecycle integration | `bats tests/phase2_lifecycle.bats` | passed locally (50 tests) |
| 02-01-02 | 02-01 | 1 | LIFE-03, LIFE-04 | Contract + concurrency | `bats tests/phase2_lifecycle.bats tests/static_contracts.bats` | passed locally (`make test`: 121 tests) |
| 02-02-01 | 02-02 | 2 | NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-08, OWN-02 | Terraform validation | `make validate` | passed locally (`AWS_PROFILE=microservices-demo make validate`) |
| 02-02-02 | 02-02 | 2 | LIFE-01 | Stubbed lifecycle integration | `bats tests/phase2_lifecycle.bats` | passed locally (50 tests) |
| 02-02-03 | 02-02 | 2 | NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-08, OWN-02 | Version ledger + Terraform validation; source pin parity checked in 02-03-02 | `make validate` | passed locally (`AWS_PROFILE=microservices-demo make validate`) |
| 02-03-01 | 02-03 | 3 | EKS-04 | Terraform validation | `make validate` | passed locally (`AWS_PROFILE=microservices-demo make validate`) |
| 02-03-02 | 02-03 | 3 | NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02 | Static L1 network/pin and ownership contracts + Terraform validation | `bats tests/static_contracts.bats && make validate` | passed locally (`make test`: 121 tests; Terraform validation passed) |
| 02-04-01 | 02-04 | 4 | LIFE-03, LIFE-04, EKS-02, OWN-02 | kubectl compatibility gate + state matrix | `bats tests/phase2_lifecycle.bats && shellcheck sh/doctor.sh` | passed locally (50 lifecycle tests; ShellCheck passed) |
| 02-04-02 | 02-04 | 4 | LIFE-03, LIFE-04 | Fixture-backed drains + ShellCheck | `bats tests/phase2_lifecycle.bats && shellcheck sh/*.sh` | passed locally (50 lifecycle tests; ShellCheck passed) |
| 02-05-01 | 02-05 | 5 | LIFE-03, LIFE-04 | AWS transition fixture harness | `bats tests/harness_selftest.bats` | passed locally (`make test`: 121 tests) |
| 02-05-02 | 02-05 | 5 | LIFE-03, LIFE-04 | Transition/failure integration | `bats tests/phase2_lifecycle.bats && bats tests/harness_selftest.bats` | passed locally (`make test`: 121 tests) |
| 02-06-01 | 02-06 | 6 | LIFE-02, LIFE-03, LIFE-04, LIFE-06 | Teardown orchestration integration | `bats tests/phase2_lifecycle.bats` | passed locally (50 tests) |
| 02-06-02 | 02-06 | 6 | LIFE-02, LIFE-03, LIFE-04 | Deadline/retry/static contracts | `bats tests/phase2_lifecycle.bats tests/static_contracts.bats && shellcheck sh/*.sh` | passed locally (`make test`: 121 tests; ShellCheck passed) |
| 02-06-03 | 02-06 | 6 | LIFE-02, LIFE-06 | Timing ledger contract | `bats tests/static_contracts.bats` | passed locally (`make test`: 121 tests) |
| 02-07-01 | 02-07 | 7 | LIFE-02, LIFE-03 | Recovery wrapper/static contracts | `bats tests/phase2_lifecycle.bats tests/static_contracts.bats` | passed locally (`make test`: 121 tests) |
| 02-07-02 | 02-07 | 7 | LIFE-02, LIFE-03 | Tagged/untagged controls + no-auto-invocation | `bats tests/phase2_lifecycle.bats tests/static_contracts.bats` | passed locally (`make test`: 121 tests); live scope proof remains partial, deletion disabled |
| 02-08-01 | 02-08 | 8 | LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-06, NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02 | Local mutation-free preflight | `bats tests/phase2_lifecycle.bats && make test && make validate && shellcheck sh/*.sh` | passed locally; no AWS lifecycle mutation performed |
| 02-08-02 | 02-08 | 8 | LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-06, NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02 | Blocking live acceptance | `bats tests/phase2_lifecycle.bats && make test && make validate` | automated checks passed; M1-M4 pending human acceptance, blocked by Phase 1 gate |

`nyquist_compliant: true` records complete plan/task verification coverage only; it does not mean tests ran, Wave 0 completed, or live/manual acceptance passed.

---

## Wave 0 Requirements

- [x] Lifecycle suite and TDD-first tracer: `02-01-01` (Wave 1) creates `tests/phase2_lifecycle.bats` and proves the initial end-to-end teardown path.
- [x] AWS transition fixtures: `02-05-01` and `02-05-02` (Wave 5) create/replay EKS, ELBv2, EC2, and EBS transitions, errors, unknown states, and terminal absence.
- [x] Recovery tagged/untagged controls: `02-07-02` (Wave 7) adds tagged-target, same-type untagged-control, preview parity, and VPC-exclusion assertions.
- [x] kubectl compatibility gate: `02-04-01` (Wave 4) pins/checks a client compatible with EKS 1.34 before any drain use.

These prerequisites are mapped to their owning tasks but have not executed; `wave_0_complete` remains `false`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| M1: Two consecutive clean, zero-orphan up/down cycles within wall-clock limits; owner `02-08-02` (Wave 8) | LIFE-01, LIFE-02, LIFE-06 | Requires real AWS lifecycle timing and the existing account teardown verifier | Run two complete cycles on an empty cluster; record each successful duration and verifier exit 0 in `COSTS.md`; do not start application code until both pass. **PENDING; blocked until Phase 1 gate passes.** |
| M2: AWS-confirmed VPC-wide ELBv2 drain while a standalone ALB is removed; owner `02-08-02` (Wave 8) | LIFE-04 | A no-op empty-cluster drain cannot prove the production ELBv2 poll waits for terminal absence | After the Phase 1 gate passes, in the dedicated account and `us-east-1` after `make up`, validate Project/L1 tags and record the L1 VPC, two existing private subnets in distinct AZs, default security group, and ALB ARN. Create an internal ALB using `aws elbv2 create-load-balancer` with those subnets and the default security group, no listener or target group; confirm its ARN/VPC with `describe-load-balancers`. Run the complete `make down` in terminal 1 and confirm the Ingress drain remains blocked while this ALB is visible and Terraform destroy has not started. In terminal 2 delete only the recorded ARN; verify terminal 1 proceeds only after a fresh AWS response shows it absent, then complete all eight teardown stages and the verifier. This proves the VPC-wide ELBv2 poll/terminal-absence contract only, not controller provisioning or Ingress-to-controller events. **PENDING; all live actions remain behind the blocking human gate.** |
| M3: Recovery command stays within project-tagged resource scope; owner `02-08-02` (Wave 8), with controls from `02-07-02` (Wave 7) | LIFE-03 | Requires a disposable tagged resource and same-type untagged control against the selected recovery tool | Preview both controls; prove only the tagged target is eligible, verify VPC is excluded, and report uncovered resources without widening scope. **PENDING.** |
| M4: Operator reaches EKS API using approved access path; owner `02-08-02` (Wave 8), with compatibility preflight from `02-04-01` (Wave 4) | LIFE-03, LIFE-04 | Depends on the selected network and identity path, not unit-test stubs | From the normal operator environment, authenticate to the Phase 2 cluster and run the drain preflight without opening the endpoint to `0.0.0.0/0`. **PENDING.** |

---

## Validation Sign-Off

- [x] All 18 tasks have an automated verify; Wave 0 prerequisites are mapped to their creating tasks.
- [x] Sampling continuity: no three consecutive tasks without automated verification.
- [x] Wave 0 prerequisite coverage is mapped; execution remains pending (`wave_0_complete: false`).
- [x] No watch-mode flags; planned local feedback latency remains under 60 seconds.
- [x] Task/wave mapping and manual-gate ownership are complete (`nyquist_compliant: true` describes strategy coverage only, not completed execution or sign-off).

**Approval:** pending; automated local validation passed, while live gates M1-M4 remain pending and blocked by Phase 1 `human_needed` status.

## Validation Audit 2026-10-15

| Metric | Count |
|--------|-------|
| Automated task checks cross-referenced | 18 |
| Local verification commands passed | 4 |
| Live acceptance gates pending | 4 |

- `bats tests/phase2_lifecycle.bats`: 50 passed.
- `make test`: 121 passed.
- `AWS_PROFILE=microservices-demo make validate`: all four Terraform layers passed.
- `shellcheck sh/*.sh`: passed.
- No AWS lifecycle operation was run. M1-M4 and the blocking 02-08-02 checkpoint remain unresolved; plan 02-07's Cloud Nuke deletion allowlist remains empty.