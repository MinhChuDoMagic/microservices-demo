# 00-bootstrap

This immortal layer is populated in Phase 1 with the versioned S3 state bucket, GitHub OIDC provider and CI roles, and cost guardrails. Its remote state key is `bootstrap/terraform.tfstate`; S3 bucket versioning is the recovery mechanism for state. To recover a prior version, list versions and download the chosen version:

```sh
BUCKET="$(terraform -chdir=layers/00-bootstrap output -raw state_bucket_name)"
aws s3api list-object-versions --bucket "$BUCKET" --prefix bootstrap/terraform.tfstate --output table
aws s3api get-object --bucket "$BUCKET" --key bootstrap/terraform.tfstate --version-id "<version-id>" terraform.tfstate.recovery
```