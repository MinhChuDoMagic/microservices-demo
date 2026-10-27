---
status: partial
phase: 02-ephemeral-infrastructure-drain-scripts
source: 02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md, 02-06-SUMMARY.md, 02-07-SUMMARY.md, 02-08-SUMMARY.md
started: 2026-10-27T02:16:37Z
updated: 2026-10-27T03:39:35Z
---

## Current Test

[testing paused — 1 item outstanding]

## Tests

### 1. Confirm L1 network and EKS acceptance
expected: The L1 configuration targets EKS 1.37, retains the /20 private subnet, data-store no-default-route, and fck-nat ENI routing contracts, and pins the AWS-recommended AL2023 ARM64 AMI 1.37.1-20261023. AWS confirms Pod Identity Agent v1.4.0-eksbuild.4 supports EKS 1.37.
result: pass
reported: "yes"

### 2. Confirm exact version pins
expected: Terraform CLI 1.17.0, AWS provider 6.70.0, EKS module 21.29.0, and the L1 source/lockfile pins agree with VERSIONS.md. AWS confirms the EKS 1.37 add-on versions, Pod Identity Agent compatibility, and recommended AL2023 ARM64 AMI release 1.37.1-20261023.
result: pass
reported: "yes"

### 3. Confirm clean timed lifecycle round-trip
expected: One make up/down round-trip on an empty stack completes with a healthy EKS 1.37 cluster, within the 20-minute up and 25-minute down limits, and verifier exit 0; the accepted gate is one round-trip.
result: skipped
reason: User chose not to rerun the long AWS lifecycle round-trip for a version-pin-only change and requested moving to the next phase.

### 4. Confirm report-only recovery scope
expected: Cloud Nuke remains report-only because the isolated EC2 proof used an additional marker and did not establish the safety of the committed Project-only scope or cascade behavior; make down does not invoke it.
result: [pending]

### 5. Ordered empty-stack teardown preserves verifier outcomes
expected: make down performs the ordered empty-stack teardown and preserves verifier outcomes.
result: pass
source: automated
coverage_id: 02-01-D1

### 6. Unknown or active cluster state cannot reach Terraform destroy
expected: Unknown or active cluster state cannot reach Terraform destroy.
result: pass
source: automated
coverage_id: 02-01-D2

### 7. Fixed deadline excludes bootstrap state
expected: The full make down operation is bounded by one fixed monotonic deadline and excludes bootstrap state.
result: pass
source: automated
coverage_id: 02-01-D3

### 8. make up validates trusted CIDR and healthy EKS components
expected: make up validates trusted CIDR, applies once, and gates success on healthy EKS components.
result: pass
source: automated
coverage_id: 02-02-D2

### 9. Karpenter AWS prerequisites are provisioned
expected: Karpenter AWS prerequisites use the exact EKS module submodule, Pod Identity, instance profile, node role, SQS, and EventBridge resources.
result: pass
source: automated
coverage_id: 02-03-D1

### 10. L1 ownership and operator guidance is documented
expected: L1 operator access, network routing, endpoint costs, and Terraform/GitOps ownership are documented.
result: pass
source: automated
coverage_id: 02-03-D3

### 11. Client/server skew fails preflight when incompatible
expected: Client/server skew is pinned and incompatible kubectl fails preflight.
result: pass
source: automated
coverage_id: 02-04-D1

### 12. EKS state and drain resources are classified fail-closed
expected: EKS state and each controller-created AWS resource set are classified fail-closed.
result: pass
source: automated
coverage_id: 02-04-D2

### 13. Failed drains stop before Terraform destroy
expected: Failed drains stop the ordered teardown before any Terraform destroy.
result: pass
source: automated
coverage_id: 02-04-D3

### 14. AWS fixture sequences fail closed
expected: Ordered sequences advance, reset, preserve errors, and fail closed on missing responses.
result: pass
source: automated
coverage_id: 02-05-D2

### 15. Existing raw fixture behavior is preserved
expected: Existing raw fixture behavior, precedence, and argv logging remain unchanged.
result: pass
source: automated
coverage_id: 02-05-D1

### 16. Drains wait for AWS terminal absence
expected: All three drains wait for AWS terminal absence and failed states never reach Terraform destroy.
result: pass
source: automated
coverage_id: 02-05-D3

### 17. Fixed deadline and bounded retries are enforced
expected: Fixed teardown deadline, compatible timeout preflight, and bounded transient retry behavior.
result: pass
source: automated
coverage_id: 02-06-D1

### 18. Eight-action orchestration preserves verifier exit mapping
expected: Eight-action orchestration, stop-before-destroy behavior, and verifier exit mapping.
result: pass
source: automated
coverage_id: 02-06-D2

### 19. Timing ledger records successful runs only
expected: Successful-only timing ledger schema and explicit Phase 2 acceptance gate.
result: pass
source: automated
coverage_id: 02-06-D3

### 20. Recovery command stays separate and report-only
expected: Separate report-only recovery command, positive Project tag contract, and down-path isolation.
result: pass
source: automated
coverage_id: 02-07-D1

## Summary

total: 20
passed: 18
issues: 0
pending: 1
skipped: 1

## Gaps

[none yet]