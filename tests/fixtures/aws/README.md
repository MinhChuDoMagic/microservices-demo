# AWS Fixture Contract

These are raw AWS CLI response bodies, before any `--query` projection. Every resource-class
fixture is a two-sided oracle: it contains a case the sweep must report and a case it must exclude,
so reporting everything or reporting nothing fails the same contract.

| Fixture | Must report | Must exclude | Exclusion source |
|---|---|---|---|
| `ec2-describe-security-groups.json` | `sg-00000000000000002` (controller-style) and `sg-00000000000000003` (untagged console group) | `sg-00000000000000001` (`default`) | `01-RESEARCH.md`, Part C: Security groups — the `default` SG trap |
| `ec2-describe-instances.json` | `i-00000000000000003` (`stopped`) and `i-00000000000000004` (`running`) | `i-00000000000000001` (`terminated`) and `i-00000000000000002` (`shutting-down`) | `01-RESEARCH.md`, Part C: EC2 instances — terminated instances are not orphans |
| `ec2-describe-volumes.json` | `vol-00000000000000002` (untagged, available 1 GiB gp3) | `vol-00000000000000001` (`in-use`) | `01-RESEARCH.md`, Part C: EBS volumes |
| `ec2-describe-snapshots.json` | `snap-00000000000000002` (manual snapshot) | `snap-00000000000000001` (self-owned AMI backing snapshot) | `01-RESEARCH.md`, Part C: Snapshots — `--owner-ids self` is not optional |
| `ec2-describe-network-interfaces.json` | `eni-00000000000000004` (available plain interface) | `eni-00000000000000001` (requester-managed), `eni-00000000000000002` (`vpc_endpoint`), and `eni-00000000000000003` (`nat_gateway`) | `01-RESEARCH.md`, Part C: ENIs — excluding AWS-managed interfaces |
| `ec2-describe-addresses.json` | `eipalloc-00000000000000002` (unassociated) | `eipalloc-00000000000000001` (associated with its reported parent) | `01-RESEARCH.md`, Part C: Elastic IPs |
| `elbv2-describe-load-balancers.json` | `k8s-demo-ingress` and `half-created-ingress` (`provisioning`) | `baseline-allowed-alb` (baseline allowlist) | `01-RESEARCH.md`, Part C: ALBs / NLBs |
| `elb-describe-load-balancers.json` | `legacy-manual-classic` | `baseline-allowed-classic` (baseline allowlist) | `01-RESEARCH.md`, Part C: ALBs / NLBs (classic extension) |
| `elbv2-describe-target-groups.json` | `orphan-manual-target` (unattached) and `attached-manual-target` | `baseline-allowed-target` (baseline allowlist) | `01-RESEARCH.md`, Part C: Target groups |
| `logs-describe-log-groups.json` | `/aws/eks/demo/unexpected` (retention absent) and `/practice/new-short-retention` | `/practice/baseline-allowed` (baseline allowlist) | `01-RESEARCH.md`, Part C: CloudWatch log groups — the hardest exclusion problem |
| `logs-list-tags-for-resource*.json` | Unowned groups have no tags; bootstrap-tagged group has `Layer=00-bootstrap` | Bootstrap-tagged group | `01-RESEARCH.md`, Part C: CloudWatch log groups — the hardest exclusion problem |
| `iam-list-roles.json` | `/practice/UnexpectedRole` | Service-linked role and Layer-tagged `gha-terraform-*` roles | `01-RESEARCH.md`, Part C: Global-pass mechanics; Gotchas & Landmines 18 |
| `iam-list-role-tags*.json` | Unexpected role has unrelated tags | Both GitHub Actions roles carry `Layer=00-bootstrap` | Plan 01-08 Task 2: IAM role immortality lookup |
| `s3api-list-buckets.json` | `practice-unexpected-bucket` | `tfstate-123456789012-us-east-1` (`Layer=00-bootstrap`) | `01-RESEARCH.md`, Part C: Global-pass mechanics |
| `s3api-get-bucket-location-*.json` | Non-default bucket is in `eu-west-1` | State bucket's null location maps to `us-east-1` | `01-RESEARCH.md`, Part C: Global-pass mechanics; Gotchas & Landmines 19 |
| `s3api-get-bucket-tagging*.json` | Untagged bucket returns `NoSuchTagSet` | State bucket's bootstrap layer tag | Plan 01-08 Task 2: S3 bucket immortality lookup |
| `sts-get-caller-identity.json` | Not a resource inventory; assert the returned account identity is parsed | No resource exclusion applies to this identity response | `01-RESEARCH.md`, Part C: Sweep Script Architecture — preflight |
| `cloudfront-list-distributions.json` | Any distribution in a non-empty response must be reported | This empty-account response has no `DistributionList.Items`; it must normalize to no findings | `01-RESEARCH.md`, Part C: Global-pass mechanics; Gotchas & Landmines 17 |
| `resourcegroupstaggingapi-get-resources*.json` | Project-tagged non-bootstrap resources; continuation token drives the second page | `Layer=00-bootstrap` resources are excluded; absent or empty token terminates pagination | Plan 01-08 Task 3: Project tag scan |
| `ec2-describe-regions.json` | Enabled regions are included in the tier-three scope | The home region is not redundantly tier-three scanned; no `--all-regions` request | Plan 01-08 Task 3: enabled region discovery |
| `*-eu-west-1.json` | Regional EC2, EKS, and RDS fixtures provide reportable findings | Empty load balancer and EIP responses normalize to no findings | Plan 01-08 Task 3: tier-three regional classes |
| `resourcegroupstaggingapi-get-resources-expired-page.err` | Expired continuation token exits 2 | The normal second-page response has an empty token and succeeds | Plan 01-08 Task 3: pagination error handling |

**CloudFront exception:** the required real empty-account response has no distribution entries, so

Tag lookup fixtures use argument-specific suffixes in the replay harness so each raw AWS response
can model the requested role, log-group ARN, or bucket without changing the response schema.
it cannot also provide a reportable distribution without ceasing to represent that response shape.
It pins the absent-`Items` normalization case; the non-empty result behavior is specified above and
must be exercised by a future non-empty response test if the sweep implementation needs that branch.

`ec2-describe-images.json` supplies the self-owned AMI cross-reference used by the snapshot check;
its root-volume snapshot is the image-backed snapshot excluded from `ec2-describe-snapshots.json`.

The expired-credential fixture is `sts-get-caller-identity-expired.err`. It contains the AWS CLI
error text used to drive the hard-error/exit-2 path; it is stderr, not JSON.