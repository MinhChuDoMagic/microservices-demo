# 00-bootstrap

This immortal layer contains only resources whose loss would complicate or prevent a rebuild.
Phase 1 adds the versioned S3 state bucket, GitHub OIDC provider and CI roles, and cost guardrails.
Later phases place additional permanent artifacts here when first needed: ECR repositories in
Phase 3, the observability S3 bucket in Phase 5, and the static-site bucket and CloudFront
distribution in Phase 11. Placement in L0, not creation timing, keeps these resources out of the
daily lifecycle.

## State backend decision

The state bucket is created by Terraform with a local backend, then its state is migrated to S3.
The generated `backend.hcl` lives at the repository root beside the Makefile, is gitignored, and is
always passed to Terraform by absolute path. The state key is supplied separately because each
layer has its own key. This is the option-A ruling from the plan 01-04 bootstrap checkpoint and a
clarification of D-16's relative-path wording.

| Layer | State key |
|---|---|
| `00-bootstrap` | `bootstrap/terraform.tfstate` |
| `10-infra` | `infra/terraform.tfstate` |
| `20-data` | `data/terraform.tfstate` |
| `30-gitops` | `gitops/terraform.tfstate` |

The bucket enables versioning, S3-managed encryption, public-access blocking, and native S3
`use_lockfile` locking. Noncurrent versions expire after 30 days while retaining the 10 newest
noncurrent versions. Organization account IDs remain in the gitignored `.aws-account-id` pin and
generated backend config, never in tracked Terraform or documentation.

## State recovery

S3 object versioning is the **only state recovery mechanism**. The `terraform.tfstate.backup` file
left by migration is gitignored local scratch, not a backup strategy. The example below restores the
`infra` layer; replace `LAYER` with `bootstrap`, `infra`, `data`, or `gitops` as needed.

```bash
ROOT="$(git rev-parse --show-toplevel)"
ACCOUNT_ID="$(cat "$ROOT/.aws-account-id")"
REGION="us-east-1"
BUCKET="tfstate-${ACCOUNT_ID}-${REGION}"
LAYER=infra
KEY="${LAYER}/terraform.tfstate"
case "$LAYER" in
	bootstrap) TF_DIR=layers/00-bootstrap ;;
	infra) TF_DIR=layers/10-infra ;;
	data) TF_DIR=layers/20-data ;;
	gitops) TF_DIR=layers/30-gitops ;;
	*) printf 'Unknown layer: %s\n' "$LAYER" >&2; exit 2 ;;
esac

# 1. List retained versions, newest first.
aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" \
	--query 'reverse(sort_by(Versions[?Key==`'"$KEY"'`],&LastModified))[].{When:LastModified,Bytes:Size,IsLatest:IsLatest,VersionId:VersionId}' \
	--output table

# 2. Save the current state and download the chosen version.
aws s3api get-object --bucket "$BUCKET" --key "$KEY" current.tfstate
VERSION_ID='<version-id from the listing>'
aws s3api get-object --bucket "$BUCKET" --key "$KEY" \
	--version-id "$VERSION_ID" recovered.tfstate
jq '{serial,lineage,resource_count:(.resources|length)}' current.tfstate
jq '{serial,lineage,resource_count:(.resources|length)}' recovered.tfstate

# Confirm the lineage matches and record the current serial before recovery.
test "$(jq -r .lineage current.tfstate)" = "$(jq -r .lineage recovered.tfstate)"

# 3. Restore by writing a new current version; keep the bad version for forensics.
aws s3api put-object --bucket "$BUCKET" --key "$KEY" \
	--body recovered.tfstate --content-type application/json

# 4. Reconfigure this layer against remote state and confirm no drift (plan exit 0).
terraform -chdir="$TF_DIR" init -reconfigure -input=false \
	-backend-config="$ROOT/backend.hcl" -backend-config="key=$KEY"
terraform -chdir="$TF_DIR" plan -input=false -detailed-exitcode
rm -f current.tfstate recovered.tfstate
```

Restoring an older version rolls the state `serial` backwards; an intervening apply may therefore
be lost. Record the serial being replaced and ensure no apply is in progress before restoring.
**Never restore a state version with a different `lineage`**; that is a different Terraform state.

## Destroy guard and lifecycle

The state bucket has the literal `prevent_destroy = true` guard:

- A plan that destroys the bucket is rejected.
- A plan that replaces the bucket is also rejected. Changing `var.region` changes the bucket name,
	forces replacement, and fails during planning.
- The guard cannot be controlled by a variable: Terraform lifecycle arguments require literals, so
	no tfvar or command-line flag can unlock it. The recovery strategy is object versioning, not
	disabling the guard.

This layer has no path into the daily lifecycle. Phase 2's `make up`/`make down` targets do not
initialize or destroy `00-bootstrap`.