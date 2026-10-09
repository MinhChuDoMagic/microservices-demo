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
  resource_sources="$(find "$BATS_TEST_DIRNAME/../layers" -type f -name '*.tf' ! -name 'versions.tf' \
    -exec grep -v '^[[:space:]]*#' {} \; 2>/dev/null)"
  matches="$(printf '%s\n' "$resource_sources" | grep -E '^[[:space:]]*(Project|Layer|ManagedBy|Environment)[[:space:]]*=' || true)"
  [ -z "$matches" ]
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
  plan_workflow="$workflow_dir/terraform-plan.yml"
  apply_workflow="$workflow_dir/terraform-apply.yml"
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
  grep -Eq '^[[:space:]]*push:[[:space:]]*$' "$apply_workflow"
  grep -Fq 'branches: [develop]' "$apply_workflow"
  grep -Fq 'vars.AWS_APPLY_ROLE_ARN' "$apply_workflow"
  grep -Fq 'vars.AWS_ACCOUNT_ID' "$apply_workflow"
  grep -Fq 'cancel-in-progress: false' "$apply_workflow"

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