---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 04
subsystem: lifecycle
tags: [bash, kubectl, eks, aws, elbv2, ec2, ebs, bats]
requires:
  - phase: 02-ephemeral-infrastructure-drain-scripts
    provides: Pinned L1 EKS/VPC graph, deterministic cluster identity, teardown order, and outer 900-second deadline
provides:
  - Exact kubectl v1.34.12 preflight with upstream skew rationale
  - Shared fail-closed EKS state classification and bounded AWS retry helpers
  - AWS-confirmed Ingress, NodePool, and PVC drains
  - VPC ID output for ELB cleanup when EKS is absent
affects: [02-05, 02-06, 02-08, lifecycle, teardown]
actuals:
  tokens: 10464
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns: [EKS status classification before Kubernetes operations, fixed AWS retry cap inside one outer monotonic deadline, Kubernetes deletion followed by AWS API terminal confirmation]
key-files:
  created:
    - sh/lifecycle-common.sh
    - sh/drain-ingress.sh
    - sh/drain-nodes.sh
    - sh/drain-pvcs.sh
  modified:
    - sh/doctor.sh
    - VERSIONS.md
    - layers/10-infra/README.md
    - layers/10-infra/outputs.tf
    - tests/phase2_lifecycle.bats
key-decisions:
  - "Pin kubectl v1.34.12, matching the EKS 1.34 minor and within Kubernetes' supported one-minor client/server skew."
  - "Only EKS ResourceNotFoundException means ABSENT; authorization, malformed data, and unrecognized status remain UNKNOWN."
  - "CREATING/FAILED clusters use AWS-only resource absence proof; ACTIVE/DEGRADED clusters require a reachable API to request deletion when resources remain."
  - "ELBv2 resources are scoped to the L1 VPC; instances require both cluster discovery and NodePool tags; PVC volumes require cluster ownership and PVC name/namespace tags."
patterns-established:
  - "Every drain performs read-only AWS queries, requests deletion only through kubectl, and reports success only after a valid AWS response confirms an empty resource set."
  - "API errors, malformed responses, unknown states, and residual identifiers fail closed with stage/state/elapsed diagnostics and a full make down rerun instruction."
requirements-completed: [LIFE-03, LIFE-04, EKS-02, OWN-02]
coverage:
  - id: D1
    description: Client/server skew is pinned and incompatible kubectl fails preflight
    requirement: EKS-02
    verification:
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#doctor accepts the pinned kubectl client minor"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#doctor rejects kubectl outside the EKS server skew window"
        status: pass
    human_judgment: false
  - id: D2
    description: EKS state and each controller-created AWS resource set are classified fail-closed
    requirement: LIFE-04
    verification:
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#Ingress drain waits for ELBv2 load balancers and target groups to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#NodePool drain waits for tagged Karpenter instances to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#PVC drain waits for PVC-owned EBS volumes to disappear"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#CREATING clusters use only AWS absence proof and report residual Ingress IDs"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#FAILED clusters stop on residual Karpenter instances without kubectl"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#DEGRADED clusters preserve Kubernetes errors and PVC attachment diagnostics"
        status: pass
    human_judgment: false
  - id: D3
    description: Failed drains stop the ordered teardown before any Terraform destroy
    requirement: LIFE-03
    verification:
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a permanent ELBv2 error fails the drain and prevents destroy"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a failed NodePool drain stops make down before Terraform destroy"
        status: pass
      - kind: unit
        ref: "tests/phase2_lifecycle.bats#a failed PVC drain stops make down before Terraform destroy"
        status: pass
    human_judgment: false
duration: multi-session
completed: 2026-10-14
status: complete
---

# Phase 02 Plan 04 Summary

**Three repeatable drains now require AWS terminal absence and fail closed across partial or unhealthy EKS states**

## Performance

- **Duration:** Multi-session execution
- **Started:** Not recorded; resumed from Phase 2 execution
- **Completed:** 2026-10-14
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Pinned kubectl v1.34.12 and made `make doctor` reject any client other than the exact pin before lifecycle use. Recorded the official patch release and one-minor skew rationale.
- Documented the restricted public endpoint path using the trusted `OPERATOR_CIDR`; `0.0.0.0/0` remains prohibited. Added recovery instructions and the ABSENT/CREATING/FAILED/DEGRADED/ACTIVE/UNKNOWN matrix.
- Added shared EKS status classification, bounded retry of classified transient AWS errors, AWS/Kubernetes error preservation, residual diagnostics, and remediation/rerun reporting.
- Added Ingress and LoadBalancer Service deletion with ELBv2 polling for all load balancers and target groups in the L1 VPC.
- Added NodePool deletion with EC2 polling scoped to deterministic cluster-discovery and NodePool tags.
- Added PVC deletion with EBS polling scoped to cluster ownership and both PVC identity tags; attachment/state information is included in failures.
- Added a stable L1 `vpc_id` output so residual ELBv2 resources remain discoverable after EKS reports `ResourceNotFoundException`.
- Added 104 repository Bats contracts, including transition, retry, malformed/error response, recovery-state, and stop-before-destroy cases.

## Task Commits

1. **Task 1: Gate lifecycle on compatible kubectl** - `2dfbf3f` (`feat`)
2. **Task 2 RED: Verify fail-closed AWS drains** - `3c2eb6d` (`test`)
3. **Task 2 RED: Bound retries and Ingress failures** - `9d95fd7` (`test`)
4. **Task 2 GREEN: Add AWS-confirmed lifecycle drains** - `7332fdf` (`feat`)

## Files Created/Modified

- `sh/lifecycle-common.sh` - EKS status classification, AWS retry cap, kubectl API probe, and diagnostics.
- `sh/drain-ingress.sh` - Ingress/LoadBalancer Service deletion and ELBv2 absence predicate.
- `sh/drain-nodes.sh` - Karpenter NodePool deletion and tagged EC2 instance absence predicate.
- `sh/drain-pvcs.sh` - PVC deletion and tagged EBS volume absence predicate.
- `sh/doctor.sh`, `VERSIONS.md` - Exact kubectl pin and skew validation.
- `layers/10-infra/README.md`, `layers/10-infra/outputs.tf` - Recovery/ownership contract and stable VPC ID output.
- `tests/phase2_lifecycle.bats` - Mutation-free service response sequences and safety contracts.

## Decisions Made

- Treat `ResourceNotFoundException` as the sole ABSENT proof; all other EKS errors and malformed/unknown responses fail closed.
- Map EKS `DELETING`, `PENDING`, and `UPDATING` into the DEGRADED path, which still requires API reachability when resources remain.
- Retry transient AWS failures at most three times per request; bounded polling and sleeps run inside the existing single 900-second monotonic teardown process deadline.
- Do not invoke AWS delete APIs or automated recovery from a drain. On residual resources, provide resource-specific operator remediation and require a fresh `make down` from stage one.

## Deviations from Plan

### Auto-fixed Issues

**1. Expose the L1 VPC ID as a Terraform output**
- **Found during:** Task 2 implementation
- **Issue:** When EKS is already absent, its `describe-cluster` response cannot provide the VPC ID needed to find residual target groups/load balancers; the existing Terraform outputs had no VPC ID.
- **Fix:** Added the stable `vpc_id` output and use it only as fallback when EKS does not return the VPC ID.
- **Files modified:** `layers/10-infra/outputs.tf`
- **Verification:** All-layer Terraform validation and ELBv2 transition/ABSENT-state Bats tests pass.
- **Committed in:** `7332fdf`

**Total deviations:** 1 auto-fixed (missing stable VPC output). **Impact:** Enables the required VPC-scoped cleanup check when the cluster control plane is absent; no AWS mutation or provider boundary change.

## Issues Encountered

- The first new transition test exposed a fixture call-indexing error, corrected before the feature validation; the service sequence tests then passed.
- AWS polling is read-only and fixture-backed in local verification. Live EKS/ELBv2/EC2/EBS behavior remains gated by the Phase 1 human approval.

## User Setup Required

Install the exact `kubectl v1.34.12` pin before invoking lifecycle commands. No cloud-side setup or mutation was performed.

## Next Phase Readiness

Plan 02-04 is locally complete. The shared drain helpers are available for subsequent lifecycle work. Do not run live `make up`, `make down`, or any AWS mutation until the Phase 1 human gate is explicitly cleared.

## Self-Check: PASSED

- `make test` passed all 104 Bats tests.
- `AWS_PROFILE=microservices-demo make validate` passed all four Terraform layers, formatting checks, and ShellCheck.
- Editor diagnostics reported no errors in the changed files.
- `git diff --check 5ca66d8..HEAD` passed.
- No AWS mutation, Terraform apply, or live kubectl operation was run.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Plan: 04*
*Completed: 2026-10-14*