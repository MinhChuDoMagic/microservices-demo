# 10-infra

This per-session Terraform layer owns the AWS network, EKS cluster, managed node group and add-ons, and AWS-side Karpenter prerequisites. Its remote state key is `infra/terraform.tfstate`. Terraform initialization must go through the repository Makefile so the generated root `backend.hcl` and exact state key are used.

## Operator Access

Set `OPERATOR_CIDRS` when running `make up` to a comma-separated list of trusted public IPv4 CIDRs. Each CIDR must be unique, valid, and not world-open; the list must include the workstation's current public IPv4 address. The preflight checks reachability before Terraform initialization; a missing, invalid, or unreachable list stops the operation before apply. The EKS public API endpoint is restricted to exactly this list, and private endpoint access remains enabled inside the VPC.

The AWS identity running Terraform receives the EKS cluster creator administrator access entry. After provisioning, configure `kubectl` for the project cluster with:

```sh
aws eks update-kubeconfig --name microservices-demo --region us-east-1
```

The operator still needs valid AWS credentials and the permissions required by the cluster access entry. `make up` does not install application or platform controllers.

## Teardown Access And Recovery

### Teardown sequence and acceptance gate

`make down` applies one fixed, non-overridable 1500-second monotonic deadline from preflight
through final verification. It runs these eight numbered actions in order:

1. Disable Argo auto-sync when the root application exists; a confirmed absent application is skipped.
2. Drain Ingress load balancers and target groups.
3. Drain Karpenter NodePool instances.
4. Drain PVC-owned EBS volumes.
5. Destroy `30-gitops`.
6. Destroy `20-data`.
7. Destroy `10-infra`.
8. Verify teardown and preserve the verifier's clean/orphan/error result.

The Phase 2 roadmap's seven named steps count the three drains, three Terraform destroys, and
final verification; that count excludes Argo auto-sync preparation. The implementation numbers
that preparation as action 1, so the complete operator-visible sequence has eight actions.
Successful drains proceed directly to the next action. Any unresolved drain stops before the
first destroy; remediate the reported resource/access issue and start a fresh `make down` from
action 1. Do not extend or reset the deadline for an individual run.

Before application code begins, complete one empty-cluster `make up` -> `make down`
round-trip with verifier exit `0`. This is a hard Phase 2 gate, not a target inferred
from local tests or timing estimates.

Lifecycle commands require the exact `kubectl` pin in `VERSIONS.md`; `make doctor` rejects a different client before draining. Kubernetes supports kubectl within one minor version of the API server; the current pin (v1.37.1) matches the EKS 1.37 control plane.

The approved operator API path is the public EKS endpoint restricted to the explicit trusted IPv4 CIDRs passed as `OPERATOR_CIDRS` to `make up`. Never use `0.0.0.0/0`. Multiple exact `/32` entries may be used for known, trusted egress addresses, but do not add a broad range to accommodate rotating WARP egress. If the workstation's public address changes outside the configured list or the API becomes unreachable, restore access from a trusted operator network and update the endpoint allowlist through the normal Terraform-owned `make up` path; do not widen access. After access is restored, rerun `make down` from its first step.

Drain recovery treats EKS states as follows:

| EKS state | Drain rule |
|---|---|
| `ABSENT` | Only an EKS `ResourceNotFound` response proves absence; drains may pass after their AWS resource queries are valid and terminal. |
| `CREATING` | Kubernetes controllers may not be operational. AWS-only predicates may pass a drain only when its complete resource set is confirmed absent/terminal; residual IDs block teardown. |
| `FAILED` | Same AWS-only proof rule as `CREATING`; residual IDs require resource-specific operator remediation. |
| `DEGRADED` | Require Kubernetes API access plus AWS terminal-state evidence. If API access fails while resources remain, stop before destroy and report the original error and IDs. |
| `ACTIVE` | Require working Kubernetes API access to request deletion, then AWS API evidence of terminal absence. |
| `UNKNOWN` | Fail closed. Authorization errors, malformed responses, and other API errors never mean absence. |

For any blocked drain, preserve the originating error, identify the stage/state and residual resources, remediate access or the named resource, then rerun `make down` from step one. A fresh run passes only drains whose full AWS resource sets are confirmed absent or terminal; a failed attempt does not automatically clean residual resources (D-03, D-04).

The ELBv2 drain scopes load balancers and target groups to the L1 VPC. The NodePool drain queries only instances tagged with both `karpenter.sh/discovery=microservices-demo` and `karpenter.sh/nodepool`. The PVC drain queries only volumes tagged `kubernetes.io/cluster/microservices-demo=owned` and carrying both `kubernetes.io/created-for/pvc/name` and `kubernetes.io/created-for/pvc/namespace`; volumes without this ownership evidence are not automatically deleted by the drain.

## Network Contract

The VPC uses the first two sorted available Availability Zones in `us-east-1` and these fixed subnet tiers:

| Tier | CIDRs | Route behavior |
|---|---|---|
| Public | `10.42.0.0/24`, `10.42.1.0/24` | Internet gateway routes for public load balancers and the NAT instance. |
| Private | `10.42.16.0/20`, `10.42.32.0/20` | Default egress routes are owned by fck-nat and target its persistent ENI, so instance replacement does not invalidate the routes. |
| Intra | `10.42.64.0/24`, `10.42.65.0/24` | No default route; reserved for data resources that do not need general internet egress. |

S3 and DynamoDB gateway endpoints are attached to both private route tables. The public and private subnets carry deterministic EKS/load-balancer discovery tags; security groups also carry the Karpenter discovery tag.

Interface endpoints are controlled by `enable_interface_endpoints`, which defaults to `false`. Enabling the current five endpoints (ECR API, ECR DKR, Secrets Manager, SQS, and STS) in two Availability Zones is approximately `$14.60/month per endpoint`, or `$73/month` for all five, before data-processing charges. Enable them only for a deliberate comparison session and disable them again afterward.

## EKS And Controller Placement

The EKS cluster is pinned to Kubernetes `1.37`. The on-demand `t4g.medium` system managed node group has two nodes, the stable label `workload=system`, and the taint `CriticalAddonsOnly=true:NoSchedule`. Platform pods placed on this group must select `workload=system` and tolerate that taint. The four managed add-ons are version-pinned in Terraform and `VERSIONS.md`; EBS CSI is intentionally not installed.

Phase 2 creates Karpenter's AWS-side IAM roles, Pod Identity association, node instance profile, interruption queue, and EventBridge rules in Terraform. The Phase 2 system-node hosting contract is the boundary for the Phase 4 GitOps seam: the Karpenter controller, AWS Load Balancer Controller, and other in-cluster charts/CRs are not installed by this layer. Later GitOps work owns those Kubernetes resources. No Kubernetes or Helm Terraform provider is used in L1.

The Karpenter controller policy uses the module's inline-policy mode to stay within AWS's 6,144-character managed-policy limit; this changes the policy attachment type, not its permissions.