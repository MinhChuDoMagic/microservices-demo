---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 03
subsystem: infra
tags: [terraform, aws, eks, karpenter, gitops, bats]
requires:
  - phase: 02-ephemeral-infrastructure-drain-scripts
    provides: Pinned L1 network/EKS graph and one-attempt make up path from plan 02-02
provides:
  - Terraform-owned Karpenter IAM, Pod Identity, node profile, SQS, and EventBridge resources
  - Stable system-node workload label and controller placement contract
  - Mechanical L1 network, pin, provider-boundary, and ownership documentation checks
affects: [02-04, 02-05, 02-06, infra, GitOps]
actuals:
  tokens: 3317
  tasks: 2
  commits: 4
tech-stack:
  added: [terraform-aws-modules/eks Karpenter submodule v21.26.0]
  patterns: [Pod Identity for Karpenter, explicit node role/profile, tracked-source static contracts]
key-files:
  created:
    - layers/10-infra/karpenter.tf
  modified:
    - layers/10-infra/eks.tf
    - layers/10-infra/README.md
    - tests/static_contracts.bats
key-decisions:
  - "Use the pinned EKS v21.26 Karpenter submodule, which scopes PassRole to its generated node role and owns the interruption event path."
  - "The Karpenter controller and AWS Load Balancer Controller remain later GitOps-owned workloads; Phase 2 only prepares their AWS resources and system-node placement contract."
patterns-established:
  - "Karpenter node IAM trust is account-scoped; its controller receives AWS access through EKS Pod Identity."
  - "Static Terraform scans exclude generated .terraform module examples and inspect tracked source only."
requirements-completed: [NET-01, NET-02, NET-03, NET-04, NET-05, NET-07, EKS-01, EKS-02, EKS-04, EKS-08, OWN-02]
coverage:
  - id: D1
    description: Karpenter AWS prerequisites use the exact EKS module submodule, Pod Identity, instance profile, node role, SQS, and EventBridge resources
    requirement: EKS-04
    verification:
      - kind: unit
        ref: "tests/static_contracts.bats#L1 Karpenter uses the pinned EKS module for AWS-side resources"
        status: pass
      - kind: other
        ref: "AWS_PROFILE=microservices-demo make validate"
        status: pass
    human_judgment: false
  - id: D2
    description: L1 networking, EKS node hosting, endpoints, tags, add-on pins, and provider boundary are statically guarded
    requirement: NET-01
    verification:
      - kind: unit
        ref: "tests/static_contracts.bats#L1 network contract uses two AZ subnet tiers and module-owned NAT routes"
        status: pass
      - kind: unit
        ref: "tests/static_contracts.bats#L1 endpoint and EKS contracts remain explicit and version-pinned"
        status: pass
      - kind: unit
        ref: "tests/static_contracts.bats#Terraform Kubernetes and Helm providers are restricted to 30-gitops"
        status: pass
    human_judgment: true
    rationale: Static contracts and Terraform validation do not prove live AWS provisioning or subnet/route behavior; live acceptance remains behind the Phase 1 human gate.
  - id: D3
    description: L1 operator access, network routing, endpoint costs, and Terraform/GitOps ownership are documented
    requirement: OWN-02
    verification:
      - kind: unit
        ref: "tests/static_contracts.bats#L1 README documents operator access network and GitOps ownership"
        status: pass
    human_judgment: false
duration: multi-session
completed: 2026-10-14
status: complete
---

# Phase 02 Plan 03 Summary

**Karpenter AWS prerequisites now live in L1 Terraform with scoped Pod Identity and an explicit GitOps hosting boundary**

## Performance

- **Duration:** Multi-session execution
- **Started:** Not recorded; resumed from the Phase 2 execution
- **Completed:** 2026-10-14
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added the exact EKS v21.26.0 Karpenter submodule for controller/node roles, Pod Identity association, access entry, instance profile, interruption queue, queue policy, and EventBridge rules/targets.
- Scoped `iam:PassRole` through the module's node-role ARN and EC2 service condition; enabled source-account condition on the node role trust.
- Added stable `workload=system` node labels and documented required node selector/taint toleration for later platform controllers.
- Extended static contracts across VPC/AZ/subnet routing, endpoint behavior, EKS capacity/add-ons/tags, exact pins, provider boundary, and README ownership statements.
- Replaced the L1 stub README with operator access, state, routing, endpoint-cost, and Phase 2/Phase 4 GitOps boundary guidance.

## Task Commits

1. **Task 1 RED: Add Karpenter AWS ownership contract** - `db31658` (`test`)
2. **Task 1 GREEN: Add Terraform-owned Karpenter AWS resources** - `a35654b` (`feat`)
3. **Task 2 RED: Verify L1 network and ownership contracts** - `987a604` (`test`)
4. **Task 2 GREEN: Define L1 operator and GitOps boundaries** - `5264c65` (`docs`)

## Files Created/Modified

- `layers/10-infra/karpenter.tf` - Pinned Karpenter AWS resources through the EKS module submodule.
- `layers/10-infra/eks.tf` - Stable system workload label.
- `layers/10-infra/README.md` - L1 operation, network, cost, and ownership contracts.
- `tests/static_contracts.bats` - Karpenter, network, EKS, pin-parity, README, and provider-boundary assertions.

## Decisions Made

- Use the EKS module's maintained Karpenter submodule rather than duplicating its IAM/event resources. Its v21.26.0 source defines scoped PassRole, Pod Identity trust/association, SQS queue policy, and interruption event wiring.
- Keep the interruption queue named after the cluster for the future controller setting; keep all in-cluster controllers and CRs outside L1 Terraform.
- Use `workload=system` plus the existing `CriticalAddonsOnly=true:NoSchedule` taint as the stable platform placement contract.

## Deviations from Plan

### Auto-fixed Issues

**1. Add the system workload label to the EKS managed node group**
- **Found during:** Task 1 implementation
- **Issue:** The plan's must-have hosting contract required stable labels, but the existing group only had its taint.
- **Fix:** Added `workload = "system"` to the system node group and documented the matching selector/toleration.
- **Files modified:** `layers/10-infra/eks.tf`, `layers/10-infra/README.md`, `tests/static_contracts.bats`
- **Verification:** Static contract suite and all-layer Terraform validation pass.
- **Committed in:** `a35654b` (label), `5264c65` (README), `987a604` (contract)

**Total deviations:** 1 auto-fixed (missing stable node label). **Impact:** Required to satisfy the stated platform hosting contract; no Kubernetes resource or AWS mutation was added.

## Issues Encountered

- Initial README contract validation correctly failed against the original stub; the provider-boundary assertion was also adjusted to permit the currently empty 30-gitops provider set while forbidding Kubernetes/Helm providers elsewhere.
- The first Terraform validation reported formatting only; formatting `karpenter.tf` resolved it and validation passed.

## User Setup Required

None for local checks. No AWS apply was run; live verification remains gated on the Phase 1 human approval.

## Next Phase Readiness

Plan 02-03 is locally complete. The next Phase 2 plan can build on the pinned L1 network/EKS/Karpenter ownership contracts. Do not perform live provisioning or acceptance until the Phase 1 human gate is explicitly cleared.

## Self-Check: PASSED

- `bats --print-output-on-failure tests/` passed all 85 tests.
- `AWS_PROFILE=microservices-demo make validate` passed all four layers, formatting, and ShellCheck.
- Editor diagnostics reported no errors in the changed files.
- `git diff --check HEAD~4..HEAD` passed.
- No AWS mutation or Terraform apply was run.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Plan: 03*
*Completed: 2026-10-14*