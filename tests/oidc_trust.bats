#!/usr/bin/env bats

# T1 checks inspect HCL directly; rendering Terraform plans may require AWS credentials.
load 'helpers/load'

setup() {
  OIDC_FILE="$BATS_TEST_DIRNAME/../layers/00-bootstrap/oidc.tf"
}

active_oidc_source() {
  grep -v '^[[:space:]]*#' "$OIDC_FILE"
}

policy_block() {
  awk -v marker="data \"aws_iam_policy_document\" \"$1\" {" '
    $0 == marker { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$OIDC_FILE" | grep -v '^[[:space:]]*#'
}

@test "provider has one client ID and no configured thumbprint" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Fq 'url            = "https://${local.gh_oidc_host}"'
  [ "$(printf '%s\n' "$source" | grep -Fc 'client_id_list = ["sts.amazonaws.com"]')" -eq 1 ]
  ! printf '%s\n' "$source" | grep -Eq '^[[:space:]]*thumbprint_list[[:space:]]*='
}

@test "both trust policies use exact web-identity trust and the provider ARN" {
  source="$(active_oidc_source)"
  [ "$(printf '%s\n' "$source" | grep -Fc 'actions = ["sts:AssumeRoleWithWebIdentity"]')" -eq 2 ]
  ! printf '%s\n' "$source" | grep -Fq 'sts:AssumeRole"'
  [ "$(printf '%s\n' "$source" | grep -Fc 'identifiers = [aws_iam_openid_connect_provider.github.arn]')" -eq 2 ]
}

@test "both trust policies require exact audience and subject conditions" {
  for name in gha_plan_trust gha_apply_trust; do
    policy="$(policy_block "$name")"
    [ -n "$policy" ]
    [ "$(printf '%s\n' "$policy" | grep -Fc 'test     = "StringEquals"')" -eq 2 ]
    printf '%s\n' "$policy" | grep -Fq 'variable = "${local.gh_oidc_host}:aud"'
    printf '%s\n' "$policy" | grep -Fq 'values   = ["sts.amazonaws.com"]'
    printf '%s\n' "$policy" | grep -Fq 'variable = "${local.gh_oidc_host}:sub"'
  done
}

@test "plan and apply trust subjects are disjoint" {
  source="$(active_oidc_source)"
  plan="$(policy_block gha_plan_trust)"
  apply="$(policy_block gha_apply_trust)"
  printf '%s\n' "$plan" | grep -Fq 'values   = [local.gh_sub_pr]'
  ! printf '%s\n' "$plan" | grep -Fq 'local.gh_sub_main'
  printf '%s\n' "$apply" | grep -Fq 'values   = [local.gh_sub_develop]'
  ! printf '%s\n' "$apply" | grep -Fq 'local.gh_sub_pr'
  printf '%s\n' "$source" | grep -Eq 'gh_sub_pr[[:space:]]*=[[:space:]]*"\$\{local\.gh_repo_ref\}:pull_request"'
  printf '%s\n' "$source" | grep -Eq 'gh_sub_develop[[:space:]]*=[[:space:]]*"\$\{local\.gh_repo_ref\}:ref:refs/heads/develop"'
}

@test "subject construction supports immutable IDs and contains no wildcard" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Fq 'github_owner_id'
  printf '%s\n' "$source" | grep -Fq 'github_repo_id'
  printf '%s\n' "$source" | grep -Fq 'var.github_owner_id == null'
  printf '%s\n' "$source" | grep -Fq 'var.github_repo_id == null'
  subjects="$(printf '%s\n' "$source" | grep -E 'gh_sub_(develop|pr)[[:space:]]*=')"
  [[ "$subjects" != *'*'* ]]
}

@test "policies avoid prefix and set-operator condition forms" {
  source="$(active_oidc_source)"
  ! printf '%s\n' "$source" | grep -Eq 'StringLike|For(AllValues|AnyValue):'
}

@test "neither role uses the reserved GitHubActions name" {
  source="$(active_oidc_source)"
  ! printf '%s\n' "$source" | grep -Fq 'GitHubActions'
}

@test "plan-role write and delete permissions are limited to lock files" {
  policy="$(policy_block gha_plan_state)"
  printf '%s\n' "$policy" | grep -Fq 'resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]'
  [ "$(printf '%s\n' "$policy" | grep -Fc 's3:DeleteObject')" -eq 1 ]
}

@test "apply deny blocks account and credential administration" {
  policy="$(policy_block gha_apply_guardrails)"
  for action in \
    'organizations:*' 'account:CloseAccount' 'account:DisableRegion' \
    'account:EnableRegion' 'billing:*' 'payments:*' 'invoicing:*' \
    'consolidatedbilling:*' 'tax:*' 'aws-portal:*' 'iam:CreateUser' \
    'iam:CreateAccessKey' 'iam:CreateLoginProfile'; do
    printf '%s\n' "$policy" | grep -Fq "\"$action\""
  done
  ! printf '%s\n' "$policy" | grep -Eq '"(budgets|ce):'
}

@test "apply role has the scheduled administrator posture and output" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Fq 'arn:aws:iam::aws:policy/AdministratorAccess'
  grep -Fq 'TEMPORARY (D-28). Phase 10 replaces AdministratorAccess' "$OIDC_FILE"
  printf '%s\n' "$source" | grep -Fq 'output "gha_apply_role_arn"'
}