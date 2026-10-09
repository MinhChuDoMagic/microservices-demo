#!/usr/bin/env bash
set -euo pipefail

readonly REPO_VARIABLES=(AWS_PLAN_ROLE_ARN AWS_APPLY_ROLE_ARN)
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-no-access-keys.XXXXXX")"
readonly TEMP_DIR
FAILURES=0

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

gh_checked() {
  local description="$1"
  shift
  local result
  local rc

  if result="$("$@")"; then
    printf '%s' "$result"
  else
    rc=$?
    printf 'GH-ERROR: %s (gh exited %s)\n' "$description" "$rc" >&2
    return 1
  fi
}

check_secret_store() {
  local description="$1"
  shift
  local count

  if count="$(gh_checked "$description" "$@")"; then
    :
  else
    exit 2
  fi
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    printf 'GH-ERROR: %s returned a non-numeric count: %s\n' "$description" "$count" >&2
    exit 2
  fi
  if (( count == 0 )); then
    printf 'PASS: %s is empty.\n' "$description"
  else
    printf 'FAIL: %s contains %s secret(s).\n' "$description" "$count" >&2
    FAILURES=1
  fi
}

root_key_count="$(aws iam get-account-summary \
  --query 'SummaryMap.AccountAccessKeysPresent' --output text)"
if [[ ! "$root_key_count" =~ ^[0-9]+$ ]]; then
  printf 'FAIL: AWS account summary returned an invalid root-key count: %s\n' \
    "$root_key_count" >&2
  exit 2
elif [[ "$root_key_count" == "0" ]]; then
  printf '%s\n' 'PASS: root account has no access keys.'
else
  printf 'FAIL: root account has %s access key(s). Delete them from the root identity security-credentials page; the CLI cannot remove them.\n' \
    "$root_key_count" >&2
  FAILURES=1
fi

users_json="$(aws iam list-users --output json)"
user_count="$(jq '.Users | length' <<< "$users_json")"
if (( user_count == 0 )); then
  printf '%s\n' 'PASS: per-user check found zero IAM users.'
else
  while IFS= read -r username; do
    [[ -n "$username" ]] || continue
    keys_json="$(aws iam list-access-keys --user-name "$username" --output json)"
    key_count="$(jq '.AccessKeyMetadata | length' <<< "$keys_json")"
    if (( key_count == 0 )); then
      printf 'PASS: IAM user %s has no access keys.\n' "$username"
    else
      printf 'FAIL: IAM user %s has %s access key(s):\n' "$username" "$key_count" >&2
      jq -r '.AccessKeyMetadata[] | "  \(.AccessKeyId)  \(.Status)  created \(.CreateDate)"' \
        <<< "$keys_json" >&2
      FAILURES=1
    fi
  done < <(jq -r '.Users[]?.UserName' <<< "$users_json")
  printf 'PASS: per-user access-key check completed for %s IAM user(s).\n' "$user_count"
fi

credential_state="$(aws iam generate-credential-report --query State --output text)"
for ((attempt = 0; attempt < 30; attempt++)); do
  [[ "$credential_state" == "COMPLETE" ]] && break
  sleep 2
  credential_state="$(aws iam generate-credential-report --query State --output text)"
done
if [[ "$credential_state" != "COMPLETE" ]]; then
  printf 'FAIL: credential report did not complete (last state: %s).\n' \
    "$credential_state" >&2
  exit 2
fi

credential_report="$(aws iam get-credential-report --query Content --output text)"
decode_base64() {
  if base64 --decode </dev/null >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}
if ! printf '%s' "$credential_report" | decode_base64 > "$TEMP_DIR/credential-report.csv"; then
  printf '%s\n' 'FAIL: could not decode the AWS credential report.' >&2
  exit 2
fi

if report_findings="$(awk -F, '
  NR == 1 {
    for (i = 1; i <= NF; i++) column[$i] = i
    if (!column["user"] || !column["access_key_1_active"] || !column["access_key_2_active"]) {
      print "FAIL: credential report is missing access-key columns."
      invalid = 1
      exit
    }
    valid = 1
    next
  }
  $(column["access_key_1_active"]) == "true" || $(column["access_key_2_active"]) == "true" {
    printf "FAIL: credential report shows an active access key for %s.\n", $(column["user"])
    found = 1
  }
  END {
    if (invalid || !valid) exit 2
    if (found) exit 1
    print "PASS: credential report confirms no active root or IAM-user access keys."
  }
' "$TEMP_DIR/credential-report.csv")"; then
  printf '%s\n' "$report_findings"
else
  rc=$?
  printf '%s\n' "$report_findings" >&2
  if (( rc == 1 )); then
    FAILURES=1
  else
    printf '%s\n' 'FAIL: credential report could not be validated.' >&2
    exit 2
  fi
fi

if repository="$(gh_checked 'repository identity lookup' gh repo view --json nameWithOwner --jq .nameWithOwner)"; then
  :
else
  exit 2
fi

# Confirmed with `gh secret list --help`: --app selects the shared stores and --env selects an environment.
for app in actions dependabot codespaces; do
  check_secret_store "GitHub ${app} secret store" \
    gh secret list --repo "$repository" --app "$app" --json name --jq 'length'
done

if environment_names="$(gh_checked 'repository environment enumeration' \
  gh api --paginate "repos/${repository}/environments" --jq '.environments[].name')"; then
  :
else
  exit 2
fi
environment_count=0
if [[ -n "$environment_names" ]]; then
  while IFS= read -r environment; do
    [[ -n "$environment" ]] || continue
    environment_count=$((environment_count + 1))
    check_secret_store "GitHub environment '${environment}' secret store" \
      gh secret list --repo "$repository" --env "$environment" --json name --jq 'length'
  done <<< "$environment_names"
fi
printf 'PASS: GitHub environment secret stores checked (%s environment(s)).\n' \
  "$environment_count"

if variables_json="$(gh_checked 'repository variable list' \
  gh variable list --repo "$repository" --json name,value)"; then
  :
else
  exit 2
fi
for variable_name in "${REPO_VARIABLES[@]}"; do
  variable_value="$(jq -r --arg name "$variable_name" \
    '[.[] | select(.name == $name)] | first | .value // empty' <<< "$variables_json")"
  if [[ -n "$variable_value" ]]; then
    printf 'PASS: repository variable %s is present.\n' "$variable_name"
  else
    printf 'FAIL: required repository variable %s is missing or empty.\n' \
      "$variable_name" >&2
    FAILURES=1
  fi
done

printf '%s\n' 'CI invariant: the apply role denies IAM user, access-key, and login-profile creation.'
if (( FAILURES != 0 )); then
  exit 1
fi
printf '%s\n' 'PASS: no long-lived AWS access keys or GitHub repository secrets were found.'