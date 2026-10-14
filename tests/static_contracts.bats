#!/usr/bin/env bats

# Strip full-line comments before every negative source search so rationale text cannot self-invalidate.
load 'helpers/load'

log_group_retention_violations() {
  local terraform_root="$1"
  local source_file

  while IFS= read -r -d '' source_file; do
    awk -v source_file="$source_file" '
      function brace_delta(line, stripped, opened, closed) {
        stripped = line
        opened = gsub(/\{/, "", stripped)
        closed = gsub(/\}/, "", stripped)
        return opened - closed
      }
      {
        line = $0
        sub(/^[[:space:]]*#.*/, "", line)
        if (!in_block) {
          if (line ~ /resource[[:space:]]+"aws_cloudwatch_log_group"[[:space:]]+"[^"]+"[[:space:]]*\{/) {
            in_block = 1
            block_line = NR
            depth = brace_delta(line)
            has_retention = 0
          }
          next
        }
        if (depth == 1 && line ~ /^[[:space:]]*retention_in_days[[:space:]]*=/) {
          has_retention = 1
        }
        depth += brace_delta(line)
        if (depth <= 0) {
          if (!has_retention) {
            printf "%s:%d\n", source_file, block_line
          }
          in_block = 0
        }
      }
      END {
        if (in_block && !has_retention) {
          printf "%s:%d\n", source_file, block_line
        }
      }
    ' "$source_file"
  done < <(find "$terraform_root" -type f -name '*.tf' -print0)
}

@test "the generated S3 backend template enables native lockfile locking" {
  grep -Fq 'use_lockfile = true' "$BATS_TEST_DIRNAME/../backend.hcl.example"
}

@test "Terraform layers contain no active DynamoDB state-lock arguments" {
  matches="$(for file in "$BATS_TEST_DIRNAME"/../layers/*/*.tf; do
    grep -v '^[[:space:]]*#' "$file"
  done | grep -E 'dynamodb_table|dynamodb_endpoint' || true)"
  [ -z "$matches" ]
}

@test "every Terraform layer configures all four default tags" {
  for layer in "$BATS_TEST_DIRNAME"/../layers/*/; do
    versions_file="${layer}versions.tf"
    for key in Project Layer ManagedBy Environment; do
      grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$versions_file"
    done
  done
}

@test "cost guardrails use exact string thresholds and document strict boundaries" {
  guardrails_file="$BATS_TEST_DIRNAME/../layers/00-bootstrap/cost-guardrails.tf"
  operator_count="$(grep -cF 'comparison_operator       = "GREATER_THAN"' "$guardrails_file")"
  threshold_count="$(grep -Ec '^[[:space:]]*threshold[[:space:]]*=[[:space:]]*"[0-9]+([.][0-9]+)?"$' "$guardrails_file")"

  [ "$operator_count" -eq 5 ]
  [ "$threshold_count" -eq 5 ]
  grep -Fq 'limit_amount = "5"' "$guardrails_file"
  grep -Fq 'limit_amount = "1"' "$guardrails_file"
  grep -Eq 'values[[:space:]]*= \["1"\]' "$guardrails_file"
  grep -Fq 'exactly $5.00 does not notify' "$guardrails_file"
  grep -Fq 'exactly $1.00 do not notify' "$guardrails_file"
}

@test "every Terraform layer uses an exact version pin" {
  matches="$(for versions_file in "$BATS_TEST_DIRNAME"/../layers/*/versions.tf; do
    grep -v '^[[:space:]]*#' "$versions_file"
  done | grep -E 'required_version[[:space:]]*=.*(>=|<=|~>|[<>])' || true)"
  [ -z "$matches" ]
  for versions_file in "$BATS_TEST_DIRNAME"/../layers/*/versions.tf; do
    grep -Eq 'required_version[[:space:]]*=[[:space:]]*"=[[:space:]]*[0-9]' "$versions_file"
  done
}

@test "resources do not repeat keys already supplied by default_tags" {
  resource_sources="$(find "$BATS_TEST_DIRNAME/../layers" -type f -name '*.tf' ! -name 'versions.tf' ! -path '*/.terraform/*' \
    -exec grep -v '^[[:space:]]*#' {} \; 2>/dev/null)"
  matches="$(printf '%s\n' "$resource_sources" | grep -E '^[[:space:]]*(Project|Layer|ManagedBy|Environment)[[:space:]]*=' || true)"
  [ -z "$matches" ]
}

@test "L1 Karpenter uses the pinned EKS module for AWS-side resources" {
  karpenter_file="$BATS_TEST_DIRNAME/../layers/10-infra/karpenter.tf"
  eks_file="$BATS_TEST_DIRNAME/../layers/10-infra/eks.tf"
  [ -f "$karpenter_file" ]
  [ -f "$eks_file" ]

  source="$(grep -v '^[[:space:]]*#' "$karpenter_file")"
  [[ "$source" == *'terraform-aws-modules/eks/aws//modules/karpenter'* ]]
  [[ "$source" == *'version = "21.26.0"'* ]]
  [[ "$source" == *'cluster_name = module.eks.cluster_name'* ]]
  [[ "$source" == *'create_instance_profile = true'* ]]
  [[ "$source" == *'create_pod_identity_association = true'* ]]
  [[ "$source" == *'enable_spot_termination = true'* ]]
  [[ "$source" == *'node_iam_role_name'*'${local.cluster_name}-karpenter-node'* ]]
  [[ "$source" == *'node_iam_role_use_name_prefix = false'* ]]
  [[ "$source" == *'iam_role_name'*'${local.cluster_name}-karpenter-controller'* ]]
  [[ "$source" == *'queue_name = local.cluster_name'* ]]
  [[ "$source" != *'aws_cloudformation_stack'* ]]

  eks_source="$(grep -v '^[[:space:]]*#' "$eks_file")"
  [[ "$eks_source" == *'workload = "system"'* ]]
}

@test "L1 network contract uses two AZ subnet tiers and module-owned NAT routes" {
  vpc_file="$BATS_TEST_DIRNAME/../layers/10-infra/vpc.tf"
  nat_file="$BATS_TEST_DIRNAME/../layers/10-infra/nat.tf"
  [ -f "$vpc_file" ]
  [ -f "$nat_file" ]
  vpc_source="$(grep -v '^[[:space:]]*#' "$vpc_file")"
  nat_source="$(grep -v '^[[:space:]]*#' "$nat_file")"

  [[ "$vpc_source" == *'slice(sort(data.aws_availability_zones.available.names), 0, 2)'* ]]
  [[ "$vpc_source" == *'private_subnets  = ["10.42.16.0/20", "10.42.32.0/20"]'* ]]
  [[ "$vpc_source" == *'intra_subnets   = ["10.42.64.0/24", "10.42.65.0/24"]'* ]]
  [[ "$vpc_source" == *'enable_nat_gateway   = false'* ]]
  [[ "$vpc_source" != *'intra_route_table_ids'* ]]
  [[ "$vpc_source" == *'"kubernetes.io/role/elb"                      = "1"'* ]]
  [[ "$vpc_source" == *'"kubernetes.io/role/internal-elb"             = "1"'* ]]
  [[ "$vpc_source" == *'"karpenter.sh/discovery"                      = local.cluster_name'* ]]
  [[ "$nat_source" == *'instance_type       = "t4g.nano"'* ]]
  [[ "$nat_source" == *'update_route_tables = true'* ]]
  [[ "$nat_source" == *'route_tables_ids = {'* ]]
  [[ "$nat_source" == *'module.vpc.private_route_table_ids[0]'* ]]
  [[ "$nat_source" == *'module.vpc.private_route_table_ids[1]'* ]]
}

@test "L1 endpoint and EKS contracts remain explicit and version-pinned" {
  vpc_file="$BATS_TEST_DIRNAME/../layers/10-infra/vpc.tf"
  variables_file="$BATS_TEST_DIRNAME/../layers/10-infra/variables.tf"
  eks_file="$BATS_TEST_DIRNAME/../layers/10-infra/eks.tf"
  vpc_source="$(grep -v '^[[:space:]]*#' "$vpc_file")"
  variables_source="$(grep -v '^[[:space:]]*#' "$variables_file")"
  eks_source="$(grep -v '^[[:space:]]*#' "$eks_file")"
  endpoint_variable="$(sed -n '/variable "enable_interface_endpoints"/,/^}/p' "$variables_file")"

  [[ "$vpc_source" == *'service_type    = "Gateway"'* ]]
  [[ "$vpc_source" == *'s3 = {'* ]]
  [[ "$vpc_source" == *'dynamodb = {'* ]]
  [[ "$vpc_source" == *'route_table_ids = module.vpc.private_route_table_ids'* ]]
  [[ "$endpoint_variable" == *'default     = false'* ]]
  [[ "$vpc_source" == *'count   = var.enable_interface_endpoints ? 1 : 0'* ]]
  [[ "$eks_source" == *'version = "21.26.0"'* ]]
  [[ "$eks_source" == *'kubernetes_version = "1.34"'* ]]
  [[ "$eks_source" == *'endpoint_public_access_cidrs = [var.operator_cidr]'* ]]
  [[ "$eks_source" == *'capacity_type                  = "ON_DEMAND"'* ]]
  [[ "$eks_source" == *'min_size                       = 2'* ]]
  [[ "$eks_source" == *'desired_size                   = 2'* ]]
  [[ "$eks_source" == *'CriticalAddonsOnly'* ]]
  [[ "$eks_source" == *'value  = "true"'* ]]
  [[ "$eks_source" == *'effect = "NO_SCHEDULE"'* ]]
  [ "$(grep -Ec 'karpenter.sh/discovery"[[:space:]]*=[[:space:]]*local.cluster_name' "$eks_file")" -eq 2 ]
  [[ "$eks_source" == *'addon_version               = "v1.23.2-eksbuild.3"'* ]]
  [[ "$eks_source" == *'addon_version = "v1.34.6-eksbuild.49"'* ]]
  [[ "$eks_source" == *'addon_version = "v1.13.2-eksbuild.51"'* ]]
  [[ "$eks_source" == *'addon_version = "v1.4.0-eksbuild.4"'* ]]
  [[ "$eks_source" != *'aws-ebs-csi-driver'* ]]
}

@test "L1 exact provider module add-on and AMI pins match VERSIONS.md" {
  infra_dir="$BATS_TEST_DIRNAME/../layers/10-infra"
  versions_file="$BATS_TEST_DIRNAME/../VERSIONS.md"
  for provider in cloudinit time tls; do
    grep -Fq "source  = \"hashicorp/$provider\"" "$infra_dir/versions.tf"
  done
  grep -Fq 'version = "= 2.4.1"' "$infra_dir/versions.tf"
  grep -Fq 'version = "= 0.14.2"' "$infra_dir/versions.tf"
  grep -Fq 'version = "= 4.4.1"' "$infra_dir/versions.tf"
  grep -Fq '| `hashicorp/cloudinit` | 2.4.1 |' "$versions_file"
  grep -Fq '| `hashicorp/time` | 0.14.2 |' "$versions_file"
  grep -Fq '| `hashicorp/tls` | 4.4.1 |' "$versions_file"

  grep -Fq 'version = "6.7.3"' "$infra_dir/vpc.tf"
  grep -Fq 'version = "1.6.1"' "$infra_dir/nat.tf"
  grep -Fq 'version = "21.26.0"' "$infra_dir/eks.tf"
  grep -Fq 'version = "21.26.0"' "$infra_dir/karpenter.tf"
  grep -Fq '| `terraform-aws-modules/vpc` | 6.7.3 |' "$versions_file"
  grep -Fq '| `RaJiska/fck-nat` | 1.6.1 |' "$versions_file"
  grep -Fq '| `terraform-aws-modules/eks` | 21.26.0 |' "$versions_file"
  grep -Fq 'ami_release_version            = "1.34.11-20261003"' "$infra_dir/eks.tf"
  grep -Fq '| EKS AL2023 ARM64 node AMI release | `1.34.11-20261003` |' "$versions_file"
  for addon_version in v1.23.2-eksbuild.3 v1.34.6-eksbuild.49 v1.13.2-eksbuild.51 v1.4.0-eksbuild.4; do
    grep -Fq "$addon_version" "$infra_dir/eks.tf"
    grep -Fq "$addon_version" "$versions_file"
  done
  [ "$(grep -Ec 'most_recent[[:space:]]*=([[:space:]]*)false' "$infra_dir/eks.tf")" -eq 4 ]
}

@test "Terraform Kubernetes and Helm providers are restricted to 30-gitops" {
  layers_dir="$BATS_TEST_DIRNAME/../layers"
  expected_layers=(00-bootstrap 10-infra 20-data 30-gitops)
  for layer in "${expected_layers[@]}"; do
    [ -f "$layers_dir/$layer/versions.tf" ]
  done

  matches="$(find "$layers_dir" -type f -name '*.tf' ! -path '*/.terraform/*' ! -path '*/30-gitops/*' \
    -exec grep -v '^[[:space:]]*#' {} \; 2>/dev/null | \
    grep -E 'provider[[:space:]]+"(kubernetes|helm)"|source[[:space:]]*=[[:space:]]*"hashicorp/(kubernetes|helm)"' || true)"
  [ -z "$matches" ]
}

@test "L1 README documents operator access network and GitOps ownership" {
  readme="$BATS_TEST_DIRNAME/../layers/10-infra/README.md"
  [ -f "$readme" ]
  grep -Fq 'infra/terraform.tfstate' "$readme"
  grep -Fq 'OPERATOR_CIDR' "$readme"
  grep -Fq '10.42.16.0/20' "$readme"
  grep -Fq '10.42.64.0/24' "$readme"
  grep -Fq 'persistent ENI' "$readme"
  grep -Fqi 'interface endpoints' "$readme"
  grep -Fq 'enable_interface_endpoints' "$readme"
  grep -Fq '$14.60/month per endpoint' "$readme"
  grep -Fq 'workload=system' "$readme"
  grep -Fq 'CriticalAddonsOnly=true:NoSchedule' "$readme"
  grep -Fq 'Karpenter controller' "$readme"
  grep -Fq 'AWS Load Balancer Controller' "$readme"
  grep -Fq 'Phase 4 GitOps seam' "$readme"
  grep -Fq 'not installed by this layer' "$readme"
}

@test "GitHub workflows do not accept long-lived AWS credentials" {
  workflow_dir="$BATS_TEST_DIRNAME/../.github/workflows"
  for workflow in "$workflow_dir"/*.yml "$workflow_dir"/*.yaml; do
    [[ -f "$workflow" ]] || continue
    matches="$(grep -v '^[[:space:]]*#' "$workflow" | \
      grep -Ei 'aws-access-key-id|aws-secret-access-key|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' || true)"
    [ -z "$matches" ]
  done
}

@test "PROJECT.md requires native S3 locking and has no active lock-table state requirement" {
  project_file="$BATS_TEST_DIRNAME/../.planning/PROJECT.md"
  grep -Fq 'remote state in S3 using native `use_lockfile` locking plus bucket versioning' "$project_file"
  matches="$(grep -niE '(state|terraform|remote.state|backend)[^.]{0,60}lock table|lock table[^.]{0,60}(state|terraform|backend)' "$project_file" | grep -vi 'deprecated' || true)"
  [ -z "$matches" ]
}

@test "CloudWatch log groups in Terraform declare explicit retention" {
  violations="$(log_group_retention_violations "$BATS_TEST_DIRNAME/../layers")"
  [ -z "$violations" ]
}

@test "the CloudWatch retention guard catches violations and ignores comments" {
  fixture_dir="$BATS_TEST_TMPDIR/log-retention"
  mkdir -p "$fixture_dir"
  fixture_file="$fixture_dir/fixture.tf"

  printf '%s\n' \
    '# resource "aws_cloudwatch_log_group" "comment_only" {' \
    '#   name = "/aws/example"' \
    '# }' \
    'resource "aws_cloudwatch_log_group" "missing_retention" {' \
    '  name = "/aws/example"' \
    '}' > "$fixture_file"
  violations="$(log_group_retention_violations "$fixture_dir")"
  [[ "$violations" == *"fixture.tf:4"* ]]
  [ "$(printf '%s\n' "$violations" | wc -l | tr -d ' ')" -eq 1 ]

  printf '%s\n' \
    '# resource "aws_cloudwatch_log_group" "comment_only" {' \
    '#   name = "/aws/example"' \
    '# }' \
    'resource "aws_cloudwatch_log_group" "with_retention" {' \
    '  name = "/aws/example"' \
    '  retention_in_days = 1' \
    '}' > "$fixture_file"
  violations="$(log_group_retention_violations "$fixture_dir")"
  [ -z "$violations" ]
}

@test "Terraform OIDC workflows are scoped, pinned, and documented" {
  workflow_dir="$BATS_TEST_DIRNAME/../.github/workflows"
  plan_workflow="$workflow_dir/oidc-plan-role-smoke.yml"
  apply_workflow="$workflow_dir/oidc-apply-role-smoke.yml"
  versions_file="$BATS_TEST_DIRNAME/../VERSIONS.md"

  [ -f "$plan_workflow" ]
  [ -f "$apply_workflow" ]

  grep -Eq '^[[:space:]]*pull_request:[[:space:]]*$' "$plan_workflow"
  grep -Fq 'vars.AWS_PLAN_ROLE_ARN' "$plan_workflow"
  grep -Fq 'vars.AWS_ACCOUNT_ID' "$plan_workflow"
  grep -Fq 'github.event.pull_request.head.repo.full_name == github.repository' "$plan_workflow"
  grep -Fq 'github.event.pull_request.head.repo.full_name != github.repository' "$plan_workflow"
  grep -Fq 'terraform fmt' "$plan_workflow"
  grep -Fq 'terraform validate' "$plan_workflow"
  grep -Fq 'name: OIDC plan-role smoke check' "$plan_workflow"
  grep -Fq 'does not run `terraform plan`' "$plan_workflow"
  grep -Fq 'requirement CD-06' "$plan_workflow"
  grep -Eq '^[[:space:]]*push:[[:space:]]*$' "$apply_workflow"
  grep -Fq 'branches: [develop]' "$apply_workflow"
  grep -Fq 'vars.AWS_APPLY_ROLE_ARN' "$apply_workflow"
  grep -Fq 'vars.AWS_ACCOUNT_ID' "$apply_workflow"
  grep -Fq 'cancel-in-progress: false' "$apply_workflow"
  grep -Fq 'name: OIDC apply-role smoke check' "$apply_workflow"
  grep -Fq 'does not run `terraform apply`' "$apply_workflow"
  grep -Fq 'requirement CD-06' "$apply_workflow"

  for workflow in "$plan_workflow" "$apply_workflow"; do
    grep -Fq 'contents: read' "$workflow"
    grep -Fq 'id-token: write' "$workflow"
    matches="$(grep -v '^[[:space:]]*#' "$workflow" | grep -E 'pull_request_target|environment:' || true)"
    [ -z "$matches" ]
  done

  workflow_sources="$(grep -h -v '^[[:space:]]*#' "$workflow_dir"/*.yml "$workflow_dir"/*.yaml 2>/dev/null || true)"
  matches="$(printf '%s\n' "$workflow_sources" | grep -Ei 'aws-access-key-id|aws-secret-access-key|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' || true)"
  [ -z "$matches" ]
  matches="$(printf '%s\n' "$workflow_sources" | grep -E 'uses:.*@v[0-9]+$' || true)"
  [ -z "$matches" ]

  while IFS= read -r action; do
    [ -z "$action" ] && continue
    grep -Fq "$action" "$versions_file"
  done < <(printf '%s\n' "$workflow_sources" | sed -nE 's/^[[:space:]]*uses:[[:space:]]*([^@[:space:]]+)@[^[:space:]]+.*/\1/p' | sort -u)
}

@test "scheduled teardown workflow preserves the three-way verifier result" {
  workflow="$BATS_TEST_DIRNAME/../.github/workflows/scheduled-teardown-sweep.yml"
  versions_file="$BATS_TEST_DIRNAME/../VERSIONS.md"

  [ -f "$workflow" ]
  grep -Fq "cron: '0 2 * * *'" "$workflow"
  grep -Fq 'workflow_dispatch:' "$workflow"
  grep -Fq 'vars.AWS_SWEEP_ROLE_ARN' "$workflow"
  grep -Fq 'vars.AWS_ACCOUNT_ID' "$workflow"
  grep -Fq 'id-token: write' "$workflow"
  grep -Fq 'contents: read' "$workflow"
  grep -Fq "steps.verify.outputs.exit_code == '0'" "$workflow"
  grep -Fq "steps.verify.outputs.exit_code == '1'" "$workflow"
  grep -Fq "steps.verify.outputs.exit_code == '2'" "$workflow"
  grep -Fq 'account state is UNKNOWN' "$workflow"
  grep -Fq '.summary.by_class' "$workflow"
  grep -Fq 'if: always()' "$workflow"
  grep -Fq '.teardown-report.json' "$workflow"
  grep -Fq 'include-hidden-files: true' "$workflow"

  active_workflow="$(grep -v '^[[:space:]]*#' "$workflow")"
  matches="$(printf '%s\n' "$active_workflow" | grep -Ei 'aws[[:space:]]+ce[[:space:]]|cost-explorer' || true)"
  [ -z "$matches" ]

  grep -Fq 'actions/upload-artifact' "$versions_file"
  grep -Fq '.github/workflows/scheduled-teardown-sweep.yml' "$versions_file"
}

@test "versioned-bucket emptier deletes versions and markers until empty" {
  stub_dir="$BATS_TEST_TMPDIR/aws-stub"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2" == "s3api list-object-versions" ]]; then
  [[ "$*" == *"--bucket test-bucket"* && "$*" == *"--max-keys 1000"* ]]
  listing_count=0
  [[ ! -f "$AWS_LIST_COUNT" ]] || listing_count="$(<"$AWS_LIST_COUNT")"
  listing_count=$((listing_count + 1))
  printf '%s' "$listing_count" > "$AWS_LIST_COUNT"
  if [[ "$listing_count" -eq 1 ]]; then
    printf '%s\n' '{"Versions":[{"Key":"state","VersionId":"v1"}],"DeleteMarkers":[{"Key":"state","VersionId":"d1"}]}'
  else
    printf '%s\n' '{"Versions":[],"DeleteMarkers":[]}'
  fi
elif [[ "$1 $2" == "s3api delete-objects" ]]; then
  payload="${!#}"
  jq -e '.Quiet == true and (.Objects | length == 2)' <<< "$payload" >/dev/null
  printf '%s\n' delete >> "$AWS_DELETE_LOG"
  printf '%s\n' '{}'
else
  exit 64
fi
AWS
  chmod +x "$stub_dir/aws"

  output="$(PATH="$stub_dir:$PATH" \
    AWS_LIST_COUNT="$BATS_TEST_TMPDIR/list-count" \
    AWS_DELETE_LOG="$BATS_TEST_TMPDIR/deletes" \
    "$BATS_TEST_DIRNAME/../sh/empty-versioned-bucket.sh" test-bucket)"

  [ "$(<"$BATS_TEST_TMPDIR/list-count")" -eq 2 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/deletes" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"deleted 2 versions/markers"* ]]
  [[ "$output" == *"bucket test-bucket is empty"* ]]
}

@test "bootstrap destruction has one explicitly decommission-only entry point" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"

  [ "$(grep -cE 'terraform.*destroy' "$makefile")" -eq 2 ]
  grep -Fq "nuke-bootstrap         DECOMMISSION:" "$makefile"
  grep -Fq "trap 'restore_nuke_files' EXIT" "$makefile"
  grep -Fq 'if [[ -f "$$BACKEND_BACKUP" ]]' "$makefile"
  grep -Fq 'if [[ -f "$$GUARD_BACKUP" ]]' "$makefile"
  grep -Fq 'sed -i.bak' "$makefile"
}

@test "daily teardown has one fixed deadline and only ephemeral state keys" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"
  common_script="$BATS_TEST_DIRNAME/../sh/lifecycle-common.sh"
  down_target="$(sed -n '/^down:$/,/^_layer-state:/p' "$makefile")"
  layer_helpers="$(sed -n '/^_layer-state:/,/^verify-teardown:/p' "$makefile")"

  grep -Eq '^down:[[:space:]]*$' "$makefile"
  grep -Fq 'command -v timeout || command -v gtimeout' <<< "$down_target"
  grep -Fq -- '--kill-after=5s 900s bash sh/down.sh' <<< "$down_target"
  [[ "$down_target" != *'--foreground'* ]]
  grep -Fq 'LC_DEADLINE_SECONDS=900' "$common_script"
  grep -Fq 'lc_deadline_expired' "$common_script"
  [ ! -e "$BATS_TEST_DIRNAME/../sh/run-down-with-deadline.py" ]
  [[ "$down_target" != *'DOWN_TIMEOUT'* ]]
  [[ "$down_target" != *'TIMEOUT_SECONDS'* ]]
  [ "$(grep -c 'STARTED_SECONDS=\$SECONDS' "$down_script")" -eq 1 ]
  ! grep -Fq 'LC_STARTED_SECONDS=$SECONDS' "$common_script"
  ! grep -Fq 'LC_DEADLINE_SECONDS:-' "$common_script"
  grep -Fq 'make -s doctor' "$down_script"
  grep -Fq '10-infra) STATE_KEY=infra/terraform.tfstate' <<< "$layer_helpers"
  grep -Fq '20-data) STATE_KEY=data/terraform.tfstate' <<< "$layer_helpers"
  grep -Fq '30-gitops) STATE_KEY=gitops/terraform.tfstate' <<< "$layer_helpers"
  [[ "$layer_helpers" != *'00-bootstrap'* ]]
  grep -Fq -- '-backend-config="$(BACKEND_HCL)"' <<< "$layer_helpers"
  grep -Fq 'key=$$STATE_KEY' <<< "$layer_helpers"
}

@test "lifecycle timing ledgers are blank and document successful-only round-trip gates" {
  costs_file="$BATS_TEST_DIRNAME/../COSTS.md"
  infra_readme="$BATS_TEST_DIRNAME/../layers/10-infra/README.md"

  grep -Fq '### Successful `make up` runs' "$costs_file"
  grep -Fq '### Successful `make down` runs' "$costs_file"
  grep -Fq 'Stage duration (s)' "$costs_file"
  grep -Fq 'Total monotonic duration (s)' "$costs_file"
  grep -Fq 'Verifier exit' "$costs_file"
  grep -Fq 'failed, orphaned, interrupted, and timed-out attempts never' "$costs_file"
  grep -Fq 'single, fixed 900-second monotonic budget' "$costs_file"
  grep -Fq 'The Phase 2 roadmap' "$infra_readme"
  grep -Fq 'complete operator-visible sequence has eight actions' "$infra_readme"
  grep -Fq 'two consecutive empty-cluster' "$infra_readme"
  grep -Fq 'verifier exit `0` both times' "$infra_readme"
  grep -Fq 'non-overridable 900-second monotonic deadline' "$infra_readme"
}

@test "teardown lock precedes every lifecycle stage and has exit and signal cleanup" {
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"
  lock_line="$(grep -nF 'if ! mkdir "$LOCK_DIR"' "$down_script" | cut -d: -f1)"
  first_stage_line="$(grep -nF "stage 1 'disable Argo auto-sync'" "$down_script" | cut -d: -f1)"

  [ -n "$lock_line" ]
  [ -n "$first_stage_line" ]
  [ "$lock_line" -lt "$first_stage_line" ]
  grep -Fq 'trap cleanup EXIT' "$down_script"
  grep -Fq "trap 'on_signal INT' INT" "$down_script"
  grep -Fq "trap 'on_signal TERM' TERM" "$down_script"
}

@test "nuke-bootstrap rejects a wrong confirmation before changing state" {
  stub_dir="$BATS_TEST_TMPDIR/aws-stub"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$AWS_CALL_LOG"
if [[ "$1 $2" == "sts get-caller-identity" ]]; then
  printf '%s\n' 123456789012
else
  exit 64
fi
AWS
  chmod +x "$stub_dir/aws"
  guard_file="$BATS_TEST_DIRNAME/../layers/00-bootstrap/main.tf"
  guard_before="$(shasum -a 256 "$guard_file")"

  if output="$(printf 'WRONG STRING\n' | \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$BATS_TEST_TMPDIR/aws-calls" \
      make -s nuke-bootstrap 2>&1)"; then
    fail "nuke-bootstrap accepted an incorrect confirmation"
  fi

  [[ "$output" == *"confirmation mismatch"* ]]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/aws-calls" | tr -d ' ')" -eq 1 ]
  [[ "$(<"$BATS_TEST_TMPDIR/aws-calls")" == "sts get-caller-identity --query Account --output text" ]]
  [ "$guard_before" = "$(shasum -a 256 "$guard_file")" ]
  [ ! -e "${guard_file}.bak" ]
}

@test "nuke-bootstrap migrates and verifies local state before emptying the bucket" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  target="$(sed -n '/^nuke-bootstrap:/,$p' "$makefile")"

  [[ "$target" == *'init -input=false -migrate-state -force-copy'* ]]
  [[ "$target" == *'terraform -chdir="$(BOOTSTRAP_DIR)" state list'* ]]
  [[ "$target" == *'aws_s3_bucket.tfstate'* ]]
  [[ "$target" != *'-backend=false'* ]]

  migration_line="$(grep -nF 'init -input=false -migrate-state -force-copy' <<< "$target" | cut -d: -f1)"
  state_line="$(grep -nF 'state list' <<< "$target" | cut -d: -f1)"
  empty_line="$(grep -nF 'empty-versioned-bucket.sh' <<< "$target" | cut -d: -f1)"
  [ "$migration_line" -lt "$state_line" ]
  [ "$state_line" -lt "$empty_line" ]
}