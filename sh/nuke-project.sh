#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

readonly EXPECTED_REGION="us-east-1"
readonly EXPECTED_PROJECT="microservices-demo"
readonly EXPECTED_CLOUD_NUKE_VERSION="0.52.0"
readonly EXPECTED_CLOUD_NUKE_SHA256="366d209ce427d25342542f4304bc1eb6987daa6561823e761336bc9edfdb710d"
readonly CONFIG_FILE="$ROOT/sh/cloud-nuke-project.yml"
readonly REPORT_ONLY_RESOURCE_TYPES="ec2"
readonly DELETABLE_RESOURCE_TYPES=""

build_scope_args() {
  SCOPE_ARGS=(--region "$EXPECTED_REGION" --config "$CONFIG_FILE")
  local resource_type
  local resource_types="$1"
  while IFS= read -r resource_type; do
    [[ -n "$resource_type" ]] || continue
    SCOPE_ARGS+=(--resource-type "$resource_type")
  done <<< "${resource_types// /$'\n'}"
}

to_json_array() {
  if [[ "$#" -eq 0 ]]; then
    printf '%s\n' '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

resource_types_json() {
  if [[ -z "$1" ]]; then
    printf '%s\n' '[]'
  else
    jq -nc --arg types "$1" '$types | split(" ") | map(select(length > 0))'
  fi
}

print_scope_contract() {
  local report_only_json
  local deletable_json
  local contract_scope=()
  local preview_command=()
  local execution_command=()

  report_only_json="$(resource_types_json "$REPORT_ONLY_RESOURCE_TYPES")"
  deletable_json="$(resource_types_json "$DELETABLE_RESOURCE_TYPES")"
  build_scope_args "$REPORT_ONLY_RESOURCE_TYPES"
  contract_scope=("${SCOPE_ARGS[@]}")
  preview_command=(aws --dry-run "${contract_scope[@]}" --output-format json)
  execution_command=(aws --force "${contract_scope[@]}" --output-format json)

  jq -n \
    --argjson preview_scope "$(to_json_array "${contract_scope[@]}")" \
    --argjson execution_scope "$(to_json_array "${contract_scope[@]}")" \
    --argjson preview_argv "$(to_json_array "${preview_command[@]}")" \
    --argjson execution_argv "$(to_json_array "${execution_command[@]}")" \
    --argjson report_only_resource_types "$report_only_json" \
    --argjson deletable_resource_types "$deletable_json" \
    --arg project "$EXPECTED_PROJECT" \
    --arg region "$EXPECTED_REGION" \
    --arg version "$EXPECTED_CLOUD_NUKE_VERSION" \
    '{contract_only:true, invocation_allowed:false, region:$region, tag_filter:{Project:$project}, untagged_control_eligible:false, report_only_resource_types:$report_only_resource_types, deletable_resource_types:$deletable_resource_types, preview_scope:$preview_scope, execution_scope:$execution_scope, preview_argv:$preview_argv, execution_argv:$execution_argv, expected_version:$version, vpc_included:false}'
}

check_account_and_region() {
  local region
  local expected_account
  local caller_json
  local actual_account

  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$EXPECTED_REGION}}"
  if [[ "$region" != "$EXPECTED_REGION" ]]; then
    printf 'ERROR: recovery is pinned to %s; refusing region %s.\n' "$EXPECTED_REGION" "$region" >&2
    return 2
  fi
  if [[ ! -f "$ROOT/.aws-account-id" ]]; then
    printf '%s\n' 'ERROR: .aws-account-id is required for the recovery account preflight.' >&2
    return 2
  fi
  expected_account="$(tr -d '[:space:]' < "$ROOT/.aws-account-id")"
  if [[ ! "$expected_account" =~ ^[0-9]{12}$ ]]; then
    printf '%s\n' 'ERROR: .aws-account-id must contain exactly 12 digits.' >&2
    return 2
  fi
  export AWS_REGION="$EXPECTED_REGION"
  if ! caller_json="$(aws sts get-caller-identity --output json)"; then
    printf '%s\n' 'ERROR: AWS caller identity could not be verified; refusing recovery.' >&2
    return 2
  fi
  actual_account="$(jq -er '.Account | select(test("^[0-9]{12}$"))' <<< "$caller_json")" || {
    printf '%s\n' 'ERROR: AWS caller identity returned a malformed account ID.' >&2
    return 2
  }
  if [[ "$actual_account" != "$expected_account" ]]; then
    printf 'ERROR: credentials target account %s; expected %s.\n' "$actual_account" "$expected_account" >&2
    return 2
  fi
  printf 'Recovery account/region preflight passed: %s / %s.\n' "$actual_account" "$EXPECTED_REGION"
}

verify_cloud_nuke_binary() {
  local binary_path
  local actual_sha256
  local version_output

  binary_path="$(command -v "${CLOUD_NUKE_BIN:-cloud-nuke}" || true)"
  if [[ -z "$binary_path" || ! -f "$binary_path" || ! -x "$binary_path" ]]; then
    printf '%s\n' 'ERROR: the pinned Cloud Nuke binary is unavailable.' >&2
    return 2
  fi
  if ! command -v shasum >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: shasum is required to verify the Cloud Nuke release binary.' >&2
    return 2
  fi
  actual_sha256="$(shasum -a 256 "$binary_path" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$EXPECTED_CLOUD_NUKE_SHA256" ]]; then
    printf '%s\n' 'ERROR: Cloud Nuke SHA-256 does not match the official v0.52.0 macOS arm64 release.' >&2
    return 2
  fi
  if ! version_output="$("$binary_path" --version 2>&1)" || \
    ! grep -Eq "(^|[^0-9])v?${EXPECTED_CLOUD_NUKE_VERSION//./\\.}([^0-9]|$)" <<< "$version_output"; then
    printf 'ERROR: Cloud Nuke did not report the pinned version %s.\n' "$EXPECTED_CLOUD_NUKE_VERSION" >&2
    return 2
  fi
  printf 'Verified Cloud Nuke v%s (SHA-256 %s).\n' "$EXPECTED_CLOUD_NUKE_VERSION" "$actual_sha256"
  CLOUD_NUKE_PATH="$binary_path"
}

run_verifier() {
  local verifier_rc
  if ./sh/verify-teardown.sh; then
    printf '%s\n' 'Teardown verifier reports no uncovered resources.'
    return 0
  else
    verifier_rc=$?
  fi
  case "$verifier_rc" in
    1) printf '%s\n' 'Uncovered resources remain in .teardown-report.json for explicit handling.' >&2 ;;
    2) printf '%s\n' 'Teardown verification failed; account state is unknown.' >&2 ;;
    *) printf 'Teardown verifier returned unexpected exit %s.\n' "$verifier_rc" >&2; verifier_rc=2 ;;
  esac
  return "$verifier_rc"
}

if [[ "${1:-}" == --print-scope-contract && $# -eq 1 ]]; then
  print_scope_contract
  exit 0
elif [[ $# -ne 0 ]]; then
  printf 'Usage: %s\n' "${0##*/}"
  exit 2
fi

check_account_and_region

if [[ -z "$DELETABLE_RESOURCE_TYPES" ]]; then
  printf '%s\n' 'No Cloud Nuke resource type has passed live tagged-target, same-type untagged-control, and cascade proof.'
  printf '%s\n' 'All types remain report-only; no Cloud Nuke preview or deletion was invoked.'
  run_verifier
  exit $?
fi

verify_cloud_nuke_binary
build_scope_args "$DELETABLE_RESOURCE_TYPES"
scope_args=("${SCOPE_ARGS[@]}")

printf '%s\n' '==> Previewing the exact scoped Cloud Nuke target set.'
"$CLOUD_NUKE_PATH" aws --dry-run "${scope_args[@]}" --output-format json
printf '%s\n' '==> Executing the same scoped target set without a second prompt (--force).'
"$CLOUD_NUKE_PATH" aws --force "${scope_args[@]}" --output-format json
run_verifier