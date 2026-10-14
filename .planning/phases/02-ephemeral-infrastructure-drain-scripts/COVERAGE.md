# API Coverage — AWS and Kubernetes control planes

> Full coverage by default. This phase integrates the listed control-plane capabilities; no capability is opted out.

| capability | decision | reason |
|---|---|---|
| AWS VPC networking: VPCs, subnets, routes, gateways, endpoints, NAT ENI | INTEGRATE | Provision and verify the complete ephemeral network. |
| AWS EKS lifecycle: cluster, managed node group, add-ons, access entries | INTEGRATE | Provision, verify readiness, and destroy the Phase 2 cluster. |
| AWS IAM and STS: operator identity, Terraform roles/policies, Karpenter identity | INTEGRATE | Scope infrastructure operations and Karpenter AWS permissions to the selected account. |
| AWS EC2: NAT instances, persistent ENI, addresses, and network state | INTEGRATE | Preserve routing through instance replacement and verify terminal resource state. |
| AWS ELBv2: load balancer discovery and terminal absence | INTEGRATE | Prove Ingress drain waits for AWS-confirmed deletion. |
| AWS EBS: volume discovery and terminal detach/deletion state | INTEGRATE | Drain persistent-volume resources and verify cleanup safely. |
| AWS SQS and EventBridge: Karpenter interruption queue and rules | INTEGRATE | Terraform owns the interruption resources consumed by Karpenter. |
| Kubernetes API: Ingress, NodePool, PVC, pod, and application sync operations | INTEGRATE | Request safe drains and verify cluster-side state before infrastructure destruction. |
| AWS account inventory APIs: teardown verifier and orphan discovery | INTEGRATE | Determine whether the dedicated account is clean and report uncovered resources. |
| AWS resource discovery/deletion APIs through Cloud Nuke | INTEGRATE | Provide the separately invoked, preview-first, positively Project-tag-scoped recovery path. |
