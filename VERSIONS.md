# VERSIONS.md

Every version in this project is pinned to an exact version (D-36), never a `~>` range. This file is the single source of truth. If you change a version, change it here and in the file named in the "Pinned in" column, in the same commit.

Last verified against upstream registries: **2026-09-25**

| Artifact | Version | Pin syntax (verbatim) | Pinned in | Source of truth |
|---|---|---|---|---|
| Terraform CLI | 1.16.4 | `1.16.4` | `.terraform-version` | [releases.hashicorp.com](https://releases.hashicorp.com/terraform/1.16.4/) |
| Terraform CLI | 1.16.4 | `required_version = "= 1.16.4"` | `layers/*/versions.tf` | [releases.hashicorp.com](https://releases.hashicorp.com/terraform/1.16.4/) |
| `hashicorp/aws` | 6.66.0 | `version = "= 6.66.0"` | `layers/*/versions.tf` | [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/6.66.0) |
| `terraform-aws-modules/vpc` | 6.7.3 | `version = "6.7.3"` | `layers/10-infra/vpc.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.7.3) |
| `terraform-aws-modules/eks` | 21.26.0 | `version = "21.26.0"` | `layers/10-infra/eks.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.26.0) |
| `RaJiska/fck-nat` | 1.6.1 | `version = "1.6.1"` | `layers/10-infra/nat.tf` (Phase 2) | [Terraform Registry](https://registry.terraform.io/modules/RaJiska/fck-nat/aws/1.6.1) |

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