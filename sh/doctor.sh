#!/usr/bin/env bash
set -uo pipefail

readonly EXPECTED_REGION="us-east-1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

FAILED=0
ok() { printf '[ok] %s\n' "$1"; }
fail() {
  printf '[fail] %s\n  -> %s\n' "$1" "$2"
  FAILED=1
}
warn() { printf '[warn] %s\n' "$1"; }

printf 'make doctor - preflight for %s\n\n' "$(basename "$ROOT")"

if ! command -v aws >/dev/null 2>&1; then
  fail "AWS CLI not found" "Install AWS CLI v2 from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
else
  AWS_RAW="$(aws --version 2>&1)"
  AWS_VER="${AWS_RAW#aws-cli/}"
  AWS_VER="${AWS_VER%% *}"
  AWS_MAJOR="${AWS_VER%%.*}"
  if [ "$AWS_MAJOR" != "2" ]; then
    fail "AWS CLI is v${AWS_VER}; this project requires v2" "Upgrade AWS CLI: v1 lacks commands used by verify-teardown.sh."
  else
    ok "AWS CLI v${AWS_VER}"
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found" "Install it with 'brew install jq' (macOS) or your system package manager."
else
  ok "jq $(jq --version | sed 's/^jq-//')"
fi

if CALLER_JSON="$(aws sts get-caller-identity --output json 2>&1)"; then
  ACTUAL_ACCOUNT="$(jq -r '.Account' <<<"$CALLER_JSON")"
  ACTUAL_ARN="$(jq -r '.Arn' <<<"$CALLER_JSON")"
  if [ -f "$ROOT/.aws-account-id" ]; then
    EXPECTED_ACCOUNT="$(tr -d '[:space:]' < "$ROOT/.aws-account-id")"
    if [ "$ACTUAL_ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
      fail "Credentials point at account ${ACTUAL_ACCOUNT}, expected ${EXPECTED_ACCOUNT}" "You are pointed at the wrong AWS account (${ACTUAL_ARN}). Fix your AWS profile or the gitignored .aws-account-id pin."
    else
      ok "AWS account ${ACTUAL_ACCOUNT} (${ACTUAL_ARN##*/})"
    fi
  else
    warn "No .aws-account-id pin file; cannot verify the target account."
    warn "Authenticated to ${ACTUAL_ACCOUNT} as ${ACTUAL_ARN}. Create the gitignored pin after confirming the account."
  fi
else
  CALLER_ERROR="$(printf '%s' "$CALLER_JSON" | tr '\n' ' ' | cut -c1-160)"
  fail "AWS credentials are not valid" "aws sts get-caller-identity failed: ${CALLER_ERROR}. Run 'aws configure' or 'aws sso login'."
fi

EFFECTIVE_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}"
if [ "$EFFECTIVE_REGION" != "$EXPECTED_REGION" ]; then
  fail "Effective AWS region is '${EFFECTIVE_REGION:-<unset>}', expected '${EXPECTED_REGION}'" "Export AWS_REGION=${EXPECTED_REGION}; project pricing is region-specific (D-02)."
else
  ok "AWS region ${EFFECTIVE_REGION}"
fi

if [ ! -f "$ROOT/.terraform-version" ]; then
  fail ".terraform-version is missing" "Create it at the repository root with the exact pinned Terraform version (D-36)."
  WANT=""
else
  WANT="$(tr -d '[:space:]' < "$ROOT/.terraform-version")"
fi

if ! command -v terraform >/dev/null 2>&1; then
  fail "Terraform not found" "Install tfenv, then run 'tfenv install' to read .terraform-version."
else
  HAVE="$(terraform version -json 2>/dev/null | jq -r '.terraform_version')"
  if [ -z "$HAVE" ] || [ "$HAVE" != "$WANT" ]; then
    fail "Terraform ${HAVE:-unknown} is on PATH but .terraform-version pins ${WANT:-unknown}" "Run 'tfenv install ${WANT}' and 'tfenv use ${WANT}'."
  else
    ok "Terraform ${HAVE}"
  fi
fi

RV="$(grep -hoE 'required_version[[:space:]]*=[[:space:]]*"= [0-9.]+' "$ROOT"/layers/*/versions.tf 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
if [ -z "$RV" ]; then
  warn "No exact required_version found in layers/*/versions.tf"
elif [ "$(wc -l <<<"$RV" | tr -d ' ')" -ne 1 ]; then
  fail "Layers disagree on required_version: $(tr '\n' ' ' <<<"$RV")" "Pin every layer to the same exact version and reconcile VERSIONS.md."
elif [ "$RV" != "$WANT" ]; then
  fail "required_version pins ${RV} but .terraform-version says ${WANT:-missing}" "Update both version sources and VERSIONS.md in the same commit (D-36)."
else
  ok "required_version (= ${RV}) agrees with .terraform-version"
fi

TFVARS="$ROOT/layers/00-bootstrap/terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  fail "layers/00-bootstrap/terraform.tfvars is missing" "Copy terraform.tfvars.example and set alert_email, github_owner, and github_repo; the real file is gitignored."
else
  for KEY in alert_email github_owner github_repo; do
    VAL="$(grep -E "^[[:space:]]*${KEY}[[:space:]]*=" "$TFVARS" 2>/dev/null | head -1 | sed -E 's/^[^=]*=[[:space:]]*"?([^\"]*)"?.*/\1/' | tr -d '[:space:]')"
    if [ -z "$VAL" ]; then
      fail "tfvars key '${KEY}' is missing or empty" "Set ${KEY} in layers/00-bootstrap/terraform.tfvars."
    elif [ "$KEY" = "alert_email" ]; then
      if [[ ! "$VAL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        fail "alert_email '${VAL}' is not a valid email address" "Set a deliverable email address for the SNS cost-alert subscription."
      else
        ok "alert_email set (${VAL%%@*}@...)"
      fi
    else
      ok "${KEY} is set"
    fi
  done
fi

IGNORE_FAILED=0
for PATH_TO_IGNORE in backend.hcl .aws-account-id terraform.tfstate .teardown-report.json layers/00-bootstrap/terraform.tfvars; do
  if ! git -C "$ROOT" check-ignore -q -- "$PATH_TO_IGNORE"; then
    fail ".gitignore does not ignore ${PATH_TO_IGNORE}" "Add the generated backend, state, report, account pin, and real tfvars to .gitignore before bootstrap."
    IGNORE_FAILED=1
  fi
done
if [ "$IGNORE_FAILED" -eq 0 ]; then
  ok ".gitignore covers generated backend, state, report, account pin, and tfvars"
fi
if git -C "$ROOT" check-ignore -q -- layers/00-bootstrap/terraform.tfvars.example; then
  fail "The terraform.tfvars.example template is ignored" "Add !*.tfvars.example to .gitignore so the safe template remains tracked."
fi

printf '\n'
if [ "$FAILED" -ne 0 ]; then
  printf '%s\n' "doctor: FAILED - fix the items marked [fail], then rerun 'make doctor'."
  exit 1
fi
printf '%s\n' 'doctor: all checks passed.'
