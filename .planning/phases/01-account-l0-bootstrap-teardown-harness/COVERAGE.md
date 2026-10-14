# API Coverage - Phase 01

> Full coverage by default. Opt-outs are explicit, reasoned decisions.

Scope: API capabilities directly used by Phase 01 Terraform resources, AWS CLI checks, and GitHub Actions/OIDC workflows. This matrix describes the project's integrated capabilities, not every operation offered by each provider.

| capability | decision | reason |
|---|---|---|
| AWS IAM control plane | INTEGRATE | Configure the GitHub OIDC provider, scoped roles and policies; inspect roles, account credentials, and role tags. |
| AWS STS identity and federation | INTEGRATE | Verify the active account identity and exchange GitHub OIDC tokens for scoped AWS role sessions. |
| Amazon S3 state and inventory | INTEGRATE | Store versioned Terraform state, acquire native lockfiles, inspect bucket metadata/tags, and safely empty the bootstrap bucket during decommissioning. |
| Amazon EC2 inventory | INTEGRATE | Inspect instances, EBS volumes, snapshots/images, Elastic IPs, network interfaces, security groups, and enabled regions for teardown orphans. |
| Amazon EKS inventory | INTEGRATE | Enumerate clusters and inspect cluster status/tags during the teardown sweep. |
| Elastic Load Balancing v1 inventory | INTEGRATE | Enumerate classic load balancers during the teardown sweep. |
| Elastic Load Balancing v2 inventory | INTEGRATE | Enumerate load balancers and target groups during the teardown sweep. |
| Amazon RDS inventory | INTEGRATE | Enumerate database instances during the teardown sweep. |
| Amazon CloudFront inventory | INTEGRATE | Enumerate global distributions during the teardown sweep. |
| Amazon CloudWatch Logs inventory | INTEGRATE | Enumerate log groups and inspect their tags during the teardown sweep. |
| AWS Resource Groups Tagging API | INTEGRATE | Paginate tagged-resource inventory for the teardown sweep. |
| AWS Budgets | INTEGRATE | Configure the monthly cost ceiling and daily actual-spend tripwire. |
| Cost Explorer allocation-tag API | INTEGRATE | Inspect cost-allocation tag activation and support later per-layer attribution checks. |
| Cost Anomaly Detection API | INTEGRATE | Configure the service-dimension monitor and anomaly subscription. |
| Amazon SNS | INTEGRATE | Configure the cost-alert topic, publishing policy, and email subscription. |
| GitHub repository and Actions APIs | INTEGRATE | Inspect repository identity/settings and workflow runs; run branch-scoped OIDC smoke checks and scheduled teardown checks. |
| DynamoDB Terraform state locking | OPT-OUT | Phase 01 selects S3-native `.tflock` locking; it creates no DynamoDB lock table and makes no DynamoDB lock calls. |
| Route 53 teardown inventory | OPT-OUT | Explicitly excluded from the Phase 01 teardown sweep; no Route 53 resources are provisioned in this phase. |
| ACM teardown inventory | OPT-OUT | Explicitly excluded from the Phase 01 teardown sweep; certificate inventory is outside this phase's scope. |
| ECR teardown inventory | OPT-OUT | Explicitly excluded from the Phase 01 teardown sweep; ECR belongs to the later service/CI phase. |
| GitHub Actions Terraform plan/apply automation | OPT-OUT | Phase 01 workflows smoke-test OIDC and run the scheduled sweep; Terraform plan/apply automation is CD-06 and is out of this phase. |
| AWS Organizations account lifecycle API | OPT-OUT | The dedicated member account is an operator-managed prerequisite; Phase 01 does not create or administer accounts through Organizations APIs. |
| Cost Explorer service enablement API | OPT-OUT | Cost Explorer enablement is a one-time Billing console prerequisite and has no enablement API. |