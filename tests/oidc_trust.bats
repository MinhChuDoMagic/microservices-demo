#!/usr/bin/env bats

# T1 checks inspect HCL directly; rendering Terraform plans may require AWS credentials.
load 'helpers/load'

setup() {
  OIDC_FILE="$BATS_TEST_DIRNAME/../layers/00-bootstrap/oidc.tf"
  [[ -f "$OIDC_FILE" ]] || skip 'MISSING — created in 01-07'
}

active_oidc_source() {
  grep -v '^[[:space:]]*#' "$OIDC_FILE"
}

@test "both policies use exact StringEquals for subject and audience" {
  source="$(active_oidc_source)"
  [ "$(printf '%s\n' "$source" | grep -Ec 'test[[:space:]]*=[[:space:]]*"StringEquals"')" -ge 4 ]
  [ "$(printf '%s\n' "$source" | grep -Fc ':aud')" -ge 2 ]
  [ "$(printf '%s\n' "$source" | grep -Fc ':sub')" -ge 2 ]
  printf '%s\n' "$source" | grep -Fq 'sts.amazonaws.com'
}

@test "the provider ARN attribute is the federated principal" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Eq 'identifiers[[:space:]]*=[[:space:]]*\[aws_iam_openid_connect_provider\.github\.arn\]'
}

@test "plan and apply subjects are distinct and scoped to their triggers" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Eq 'values[[:space:]]*=[[:space:]]*\[local\.gh_sub_pr\]'
  printf '%s\n' "$source" | grep -Eq 'values[[:space:]]*=[[:space:]]*\[local\.gh_sub_main\]'
  printf '%s\n' "$source" | grep -Eq 'gh_sub_pr[[:space:]]*=.*pull_request'
  printf '%s\n' "$source" | grep -Eq 'gh_sub_main[[:space:]]*=.*refs/heads/main'
}

@test "subject construction supports immutable repository IDs without wildcards" {
  source="$(active_oidc_source)"
  printf '%s\n' "$source" | grep -Fq 'github_owner_id'
  printf '%s\n' "$source" | grep -Fq 'github_repo_id'
  subjects="$(printf '%s\n' "$source" | grep -E 'gh_sub_(main|pr)[[:space:]]*=')"
  [[ "$subjects" != *'*'* ]]
}

@test "policies avoid prefix and set-operator condition forms" {
  source="$(active_oidc_source)"
  ! printf '%s\n' "$source" | grep -Eq 'StringLike|For(All|Any)Values:'
}

@test "neither role uses the reserved GitHubActions name" {
  source="$(active_oidc_source)"
  ! printf '%s\n' "$source" | grep -Fq 'GitHubActions'
}