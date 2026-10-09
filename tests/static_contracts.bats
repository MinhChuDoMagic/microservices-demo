#!/usr/bin/env bats

# Strip full-line comments before every negative source search so rationale text cannot self-invalidate.
load 'helpers/load'

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