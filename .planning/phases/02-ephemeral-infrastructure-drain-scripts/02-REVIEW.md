---
phase: 02-ephemeral-infrastructure-drain-scripts
reviewed: 2026-10-15T07:09:05Z
depth: standard
files_reviewed: 26
files_reviewed_list:
  - Makefile
  - COSTS.md
  - VERSIONS.md
  - layers/10-infra/README.md
  - layers/10-infra/vpc.tf
  - layers/10-infra/nat.tf
  - layers/10-infra/eks.tf
  - layers/10-infra/karpenter.tf
  - layers/10-infra/outputs.tf
  - layers/10-infra/variables.tf
  - layers/10-infra/versions.tf
  - sh/down.sh
  - sh/up.sh
  - sh/lifecycle-common.sh
  - sh/drain-ingress.sh
  - sh/drain-nodes.sh
  - sh/drain-pvcs.sh
  - sh/doctor.sh
  - sh/nuke-project.sh
  - sh/cloud-nuke-project.yml
  - tests/phase2_lifecycle.bats
  - tests/static_contracts.bats
  - tests/helpers/stub-aws.bash
  - tests/harness_selftest.bats
  - tests/fixtures/aws/phase2-lifecycle-sequences.json
  - tests/fixtures/aws/README.md
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---
# Phase 02: Code Review Report

**Reviewed:** 2026-10-15T07:09:05Z
**Depth:** standard
**Files Reviewed:** 26
**Status:** issues_found

## Summary

Reviewed the eight phase summaries' created/modified entries and the current versions of all in-scope source, configuration, test, fixture, and operator-documentation files. Planning artifacts and the Terraform provider lockfile were excluded. The working-tree edits in phase-owned source/tests were included. Two warnings remain; no blocker was identified.

## Warnings

### WR-01: [WARNING] Bash elapsed-time origin is not valid across drain subprocesses

**File:** `sh/down.sh:8-10`; `sh/lifecycle-common.sh:21,24,30,36`
**Issue:** `down.sh` exports `LC_STARTED_SECONDS` from its Bash `SECONDS` counter, then sources each drain in a subshell. A child Bash starts a fresh `SECONDS` counter, so its current value is not comparable with the parent's exported origin. A direct probe produced `parent-start=348 child-seconds=0 elapsed=-348`. Consequently drain failure diagnostics can report negative elapsed time, and the helper's 900-second deadline check can be delayed by the parent's elapsed offset. GNU `timeout` still imposes the outer hard 900-second limit, so the hard teardown cap remains enforced.
**Fix:** Use a process-independent monotonic timestamp/origin for helper calculations, or keep the `SECONDS`-based helper clock within one shell process and rely on GNU `timeout` for the cross-process hard cap.

### WR-02: [WARNING] NAT cost estimate does not match the configured instance type

**File:** `COSTS.md:157`; `layers/10-infra/nat.tf:11`
**Issue:** The current worktree configures the fck-nat instance as `t4g.micro`, while the future-leakage table still models an always-on `t4g.nano` at `$3.07/month`. That makes this project's NAT instance cost estimate stale and understates the configured instance's run rate.
**Fix:** Reprice the configured `t4g.micro` instance and update the cost table and related Phase 2 cost guidance to match.

---

_Reviewed: 2026-10-15T07:09:05Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
