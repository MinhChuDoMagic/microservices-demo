# 10-infra

This per-session Terraform layer owns the AWS network, EKS cluster, managed node group and add-ons, and AWS-side Karpenter prerequisites. Its remote state key is `infra/terraform.tfstate`. Terraform initialization must go through the repository Makefile so the generated root `backend.hcl` and exact state key are used.

## Operator Access

Set `OPERATOR_CIDR` when running `make up`. The value must be a valid trusted public IPv4 CIDR containing the workstation's current public IPv4 address. The preflight checks reachability before Terraform initialization; a missing, invalid, world-open, or unreachable CIDR stops the operation before apply. The EKS public API endpoint is restricted to this CIDR, and private endpoint access remains enabled inside the VPC.

The AWS identity running Terraform receives the EKS cluster creator administrator access entry. After provisioning, configure `kubectl` for the project cluster with:

```sh
aws eks update-kubeconfig --name microservices-demo --region us-east-1
```

The operator still needs valid AWS credentials and the permissions required by the cluster access entry. `make up` does not install application or platform controllers.

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

The EKS cluster is pinned to Kubernetes `1.34`. The on-demand `t4g.medium` system managed node group has two nodes, the stable label `workload=system`, and the taint `CriticalAddonsOnly=true:NoSchedule`. Platform pods placed on this group must select `workload=system` and tolerate that taint. The four managed add-ons are version-pinned in Terraform and `VERSIONS.md`; EBS CSI is intentionally not installed.

Phase 2 creates Karpenter's AWS-side IAM roles, Pod Identity association, node instance profile, interruption queue, and EventBridge rules in Terraform. The Phase 2 system-node hosting contract is the boundary for the Phase 4 GitOps seam: the Karpenter controller, AWS Load Balancer Controller, and other in-cluster charts/CRs are not installed by this layer. Later GitOps work owns those Kubernetes resources. No Kubernetes or Helm Terraform provider is used in L1.