---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 02
subsystem: infra
tags: [terraform, aws, eks, bats, bash, fck-nat]
requires:
  - phase: 02-ephemeral-infrastructure-drain-scripts
    provides: Ordered teardown spine and ephemeral state helpers from plan 02-01
provides:
  - Pinned L1 VPC, fck-nat, and EKS Terraform graph
  - One-attempt make up lifecycle with trusted-CIDR preflight and EKS readiness gates
  - Exact L1 provider, module, add-on, Kubernetes, and AMI version ledger
affects: [02-03, infra, EKS, lifecycle]
actuals:
  tokens: 7935
  tasks: 3
  commits: 4
tech-stack:
  added: [Terraform cloudinit/time/tls providers, VPC/EKS/fck-nat modules]
  patterns: [Make-owned Terraform init/apply, explicit readiness polling, preserve partial state on failure]
key-files:
  created:
    - layers/10-infra/vpc.tf
    - layers/10-infra/nat.tf
    - layers/10-infra/eks.tf
    - layers/10-infra/outputs.tf
    - sh/up.sh
  modified:
    - Makefile
    - layers/10-infra/versions.tf
    - layers/10-infra/variables.tf
    - layers/10-infra/.terraform.lock.hcl
    - tests/phase2_lifecycle.bats
    - tests/static_contracts.bats
    - VERSIONS.md
key-decisions:
  - "make up validates the operator CIDR before init and performs exactly one Make-owned L1 apply."
  - "Apply or readiness failures preserve partial state and diagnostics; retry requires an explicit operator rerun."
  - "Terraform outputs supply the cluster and system node group names used by the readiness gate."
patterns-established:
  - "Lifecycle shell scripts delegate Terraform initialization and apply to Make helpers using explicit state keys."
  - "EKS readiness requires ACTIVE status and no reported health issues for the cluster, system group, and four required add-ons."
requirements-completed: [LIFE-01, NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-08, OWN-02]
coverage:
  - id: D1
    description: Pinned L1 VPC, persistent-ENI NAT, and EKS Terraform graph
    requirement: NET-01
    verification:
      - kind: other
        ref: "AWS_PROFILE=microservices-demo make validate"
        status: pass
    human_judgment: true
    rationale: Local validation does not establish live AWS behavior; live acceptance remains behind the Phase 1 human gate.
  - id: D2
    description: make up validates trusted CIDR, applies once, and gates success on healthy EKS components
    requirement: LIFE-01
    verification:
      - kind: integration
        ref: "tests/phase2_lifecycle.bats"
        status: pass
    human_judgment: false
  - id: D3
    description: Exact L1 provider, module, add-on, Kubernetes, and AMI pins are recorded
    requirement: EKS-08
    verification:
      - kind: other
        ref: "VERSIONS.md compared with layers/10-infra source and lockfile"
        status: pass
    human_judgment: true
    rationale: Upstream release-contract verification is not enforced by a local automated ledger-parity test.
duration: multi-session
completed: 2026-10-14
status: complete
---

# Phase 02 Plan 02 Summary

**Pinned L1 networking and EKS provisioning with a trusted-CIDR preflight and fail-closed readiness gate**

## Performance

- **Duration:** Multi-session execution
- **Started:** Not recorded; resumed from an in-progress plan
- **Completed:** 2026-10-14
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments

- Replaced the L1 stub with a pinned two-AZ VPC, fck-nat, and EKS 1.34 graph, including explicit system node and add-on pins.
- Added `make up` with current-public-IP CIDR validation before Terraform, Make-owned initialization and one apply, and readiness checks for the cluster, system node group, and four add-ons.
- Preserved Terraform/AWS diagnostics and partial infrastructure on failure; no automatic retry or destroy is performed.
- Added lifecycle coverage and recorded exact provider, module, add-on, Kubernetes, and AMI pins.

## Task Commits

1. **Task 1: Replace the L1 stub with pinned VPC, fck-nat, and EKS modules** - `f4beec4` (`feat`)
2. **Task 2 RED: Add make up lifecycle contracts** - `5c27da8` (`test`)
3. **Task 2 GREEN: Wire one-attempt apply and readiness gate** - `bfc06ad` (`feat`)
4. **Task 3: Record exact pins** - `2726696` (`docs`)

## Files Created/Modified

- `layers/10-infra/vpc.tf`, `nat.tf`, and `eks.tf` - Pinned L1 network and EKS graph.
- `layers/10-infra/outputs.tf` - Exposes names needed by readiness polling.
- `sh/up.sh` and `Makefile` - Operator preflight, Make-owned init/apply, and health gate.
- `tests/phase2_lifecycle.bats` - CIDR, one-apply, readiness, and failure-preservation contracts.
- `tests/static_contracts.bats` - Excludes generated Terraform module examples from source scanning.
- `VERSIONS.md` and `layers/10-infra/.terraform.lock.hcl` - Exact version and provider checksums.

## Decisions Made

- The public EKS endpoint is limited to the supplied trusted IPv4 CIDR, which must contain the workstation's current public IP before Terraform initialization.
- Readiness requires `ACTIVE` status and an empty health-issue list for the EKS cluster, system group, and all four required managed add-ons.
- Live provisioning was not run; the Phase 1 `human_needed` gate remains a hard stop for AWS mutations and acceptance.

## Deviations from Plan

### Auto-fixed Issues

**1. Exclude generated module examples from the Terraform source scan**
- **Found during:** Plan verification
- **Issue:** The existing default-tag contract scanned `.terraform/modules/**/examples` after Terraform validation downloaded modules, and falsely treated sample tags as project resources.
- **Fix:** Excluded generated `.terraform` files while retaining the tracked-source assertion.
- **Files modified:** `tests/static_contracts.bats`
- **Verification:** The focused contract and full Bats suite pass.
- **Committed in:** `5c27da8`

**2. Expose Terraform resource names for readiness checks**
- **Found during:** Task 2 implementation
- **Issue:** The lifecycle script needed stable cluster and node group identifiers without duplicating Terraform naming assumptions.
- **Fix:** Added `outputs.tf` for the module-derived cluster and system node group names.
- **Files modified:** `layers/10-infra/outputs.tf`
- **Verification:** Terraform validation and lifecycle tests pass.
- **Committed in:** `bfc06ad`

**Total deviations:** 2 auto-fixed (test-scan cache exclusion, output contract). **Impact:** Both changes support reliable local verification and correct readiness lookup; no AWS scope was added.

## Issues Encountered

- The first lifecycle validation invoked the installed tfenv Terraform binary for output lookup. The harness was corrected to stub Terraform outputs, after which all lifecycle tests passed without Terraform apply or AWS calls.
- The first full Bats run exposed the generated-module-example scan issue described above; it is now resolved.

## User Setup Required

None for local validation. Live AWS apply and acceptance remain gated on the outstanding Phase 1 human approval.

## Next Phase Readiness

Plan 02-02 is locally validated. Plan 02-03 owns the remaining L1 static contracts and downstream infrastructure/drain integration. Do not run `make up` against AWS until the Phase 1 human gate is explicitly cleared.

## Self-Check: PASSED

- `AWS_PROFILE=microservices-demo make validate` passed all four layers, formatting, and ShellCheck.
- `bats --print-output-on-failure tests/` passed all 79 tests.
- `git diff --check HEAD~4..HEAD` passed.
- No AWS mutation or Terraform apply was run.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Plan: 02*
*Completed: 2026-10-14*