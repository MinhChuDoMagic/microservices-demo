# VERSIONS.md

Every version in this project is pinned to an exact version (D-36), never a `~>` range. This file is the single source of truth. If you change a version, change it here and in the file named in the "Pinned in" column, in the same commit.

Last verified against upstream registries: **2026-10-27**

| Artifact | Version | Pin syntax (verbatim) | Pinned in | Source of truth |
|---|---|---|---|---|
| Terraform CLI | 1.17.0 | `1.17.0` | `.terraform-version` | [releases.hashicorp.com](https://releases.hashicorp.com/terraform/1.17.0/) |
| Terraform CLI | 1.17.0 | `required_version = "= 1.17.0"` | `layers/*/versions.tf` | [releases.hashicorp.com](https://releases.hashicorp.com/terraform/1.17.0/) |
| `hashicorp/aws` | 6.70.0 | `version = "= 6.70.0"` | `layers/*/versions.tf` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/6.70.0) |
| `hashicorp/cloudinit` | 2.4.1 | `version = "= 2.4.1"` | `layers/10-infra/versions.tf` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/cloudinit/2.4.1) |
| `hashicorp/time` | 0.14.2 | `version = "= 0.14.2"` | `layers/10-infra/versions.tf` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/time/0.14.2) |
| `hashicorp/tls` | 4.4.1 | `version = "= 4.4.1"` | `layers/10-infra/versions.tf` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/tls/4.4.1) |
| `hashicorp/null` (transitive) | 3.3.2 | `version = "3.3.2"` | `layers/10-infra/.terraform.lock.hcl` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/null/3.3.2) |
| `terraform-aws-modules/vpc` | 6.7.3 | `version = "6.7.3"` | `layers/10-infra/vpc.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.7.3) |
| `terraform-aws-modules/eks` | 21.29.0 | `version = "21.29.0"` | `layers/10-infra/eks.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.29.0) |
| `RaJiska/fck-nat` | 1.6.1 | `version = "1.6.1"` | `layers/10-infra/nat.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/RaJiska/fck-nat/aws/1.6.1) |
| EKS managed add-on `vpc-cni` | `v1.23.2-eksbuild.8` | `addon_version = "v1.23.2-eksbuild.8"` | `layers/10-infra/eks.tf` | [EKS add-on versions](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| EKS managed add-on `kube-proxy` | `v1.37.0-eksbuild.32` | `addon_version = "v1.37.0-eksbuild.32"` | `layers/10-infra/eks.tf` | [EKS add-on versions](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| EKS managed add-on `coredns` | `v1.14.7-eksbuild.22` | `addon_version = "v1.14.7-eksbuild.22"` | `layers/10-infra/eks.tf` | [EKS add-on versions](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| EKS managed add-on `eks-pod-identity-agent` | `v1.4.0-eksbuild.4` | `addon_version = "v1.4.0-eksbuild.4"` | `layers/10-infra/eks.tf` | [EKS add-on versions](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html) |
| EKS Kubernetes | 1.37 | `kubernetes_version = "1.37"` | `layers/10-infra/eks.tf` | [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) |
| `kubectl` | v1.37.1 | `v1.37.1` | `sh/doctor.sh` | [Kubernetes patch releases](https://kubernetes.io/releases/patch-releases/); [version-skew policy](https://kubernetes.io/releases/version-skew-policy/) |
| Cloud Nuke (macOS arm64) | v0.52.0 | `sha256:366d209ce427d25342542f4304bc1eb6987daa6561823e761336bc9edfdb710d` | `sh/nuke-project.sh` | [Official v0.52.0 release](https://github.com/gruntwork-io/cloud-nuke/releases/tag/v0.52.0) |
| EKS AL2023 ARM64 node AMI release | `1.37.1-20261023` | `ami_release_version = "1.37.1-20261023"` | `layers/10-infra/eks.tf` | [EKS optimized AMI releases](https://github.com/awslabs/amazon-eks-ami/releases) |

AWS's 2026-10-27 add-on tables list the pinned VPC CNI, kube-proxy, and CoreDNS versions for EKS 1.37. On 2026-10-27, the `microservices-demo` profile in `us-east-1` confirmed through AWS APIs that `eks-pod-identity-agent` `v1.4.0-eksbuild.4` supports cluster version 1.37 and that the recommended AL2023 ARM64 node AMI release is `1.37.1-20261023`.

## CI actions

| Artifact | Pin | Pinned in |
|---|---|---|
| `actions/checkout` | `v6.0.2` | `.github/workflows/oidc-plan-role-smoke.yml`, `.github/workflows/oidc-apply-role-smoke.yml` |
| `hashicorp/setup-terraform` | `v3.1.2` | `.github/workflows/oidc-plan-role-smoke.yml`, `.github/workflows/oidc-apply-role-smoke.yml` |
| `aws-actions/configure-aws-credentials` | `v6.3.0` | `.github/workflows/oidc-plan-role-smoke.yml`, `.github/workflows/oidc-apply-role-smoke.yml` |
| `actions/upload-artifact` | `v4.6.2` | `.github/workflows/scheduled-teardown-sweep.yml` |

`kubectl v1.37.1` is pinned to the EKS 1.37 minor and is within the Kubernetes version-skew policy.

## Local tooling (not pinned in code)

| Tool | Installed version | Purpose |
|---|---|---|
| `bats-core` | 1.14.0 | Shell test suite |
| `shellcheck` | 0.11.0 | Shell script linting |

## Constraint floors

These are informational; do not relax the exact pins above.

| Consumer | Requires |
|---|---|
| S3 backend `use_lockfile` (GA) | Terraform >= 1.11.0 |
| `terraform-aws-modules/eks` 21.x | Terraform >= 1.5.7, `aws` >= 6.59, `time` >= 0.9, `tls` >= 4.0 |

## Deliberately NOT used

| Thing | Why |
|---|---|
| DynamoDB state-lock table | Deprecated since Terraform 1.11 in favour of S3 native `use_lockfile` locking, as specified in `PROJECT.md`. |
| `kubernetes` provider | Removed as a requirement by EKS module v21. Do not reintroduce. |