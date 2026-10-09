#!/usr/bin/env bash

stub_aws_start() {
  if [[ -n "${STUB_AWS_DIR:-}" ]]; then
    stub_aws_stop
  fi

  STUB_AWS_ORIGINAL_PATH="$PATH"
  STUB_AWS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stub-aws.XXXXXX")"
  STUB_AWS_CALL_LOG="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/aws-calls.log"
  STUB_AWS_FIXTURE_DIR="${BATS_TEST_DIRNAME:-$(pwd)/tests}/fixtures/aws"
  : > "$STUB_AWS_CALL_LOG"
  export STUB_AWS_CALL_LOG STUB_AWS_FIXTURE_DIR

  cat > "$STUB_AWS_DIR/aws" <<'STUB_AWS'
#!/usr/bin/env bash
set -u

printf '%s ' "$@" >> "$STUB_AWS_CALL_LOG"
printf '\n' >> "$STUB_AWS_CALL_LOG"

service=""
operation=""
for argument in "$@"; do
  [[ "$argument" == -* ]] && continue
  if [[ -z "$service" ]]; then
    service="$argument"
  else
    operation="$argument"
    break
  fi
done

fixture_base="${STUB_AWS_FIXTURE_DIR}/${service}-${operation}"
fixture_selector=""
fixture_kind=""
fixture_region=""
pagination_token=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-name|--bucket|--resource-arn)
      if [[ $# -gt 1 ]]; then
        fixture_selector="$2"
        fixture_kind="$1"
        shift 2
      else
        shift
      fi
      ;;
    --region)
      if [[ $# -gt 1 ]]; then
        fixture_region="$2"
        shift 2
      else
        shift
      fi
      ;;
    --pagination-token)
      if [[ $# -gt 1 ]]; then
        pagination_token="$2"
        shift 2
      else
        shift
      fi
      ;;
    *) shift ;;
  esac
done
if [[ "$service:$operation" == "logs:list-tags-for-resource" && "$fixture_kind" == "--resource-arn" ]]; then
  fixture_selector="${fixture_selector#*:log-group:}"
  fixture_selector="${fixture_selector%:*}"
  fixture_selector="$(printf '%s' "$fixture_selector" | tr -c '[:alnum:]_-' '_')"
fi
if [[ -n "$pagination_token" && ( -f "${fixture_base}-${pagination_token}.err" || -f "${fixture_base}-${pagination_token}.json" ) ]]; then
  fixture_base="${fixture_base}-${pagination_token}"
elif [[ -n "$fixture_selector" && ( -f "${fixture_base}-${fixture_selector}.err" || -f "${fixture_base}-${fixture_selector}.json" ) ]]; then
  fixture_base="${fixture_base}-${fixture_selector}"
elif [[ -n "$fixture_region" && ( -f "${fixture_base}-${fixture_region}.err" || -f "${fixture_base}-${fixture_region}.json" ) ]]; then
  fixture_base="${fixture_base}-${fixture_region}"
fi
if [[ -f "${fixture_base}.err" ]]; then
  cat "${fixture_base}.err" >&2
  exit 255
fi
if [[ -f "${fixture_base}.json" ]]; then
  cat "${fixture_base}.json"
  exit 0
fi

printf 'stub-aws: no fixture; looked for %s.err or %s.json\n' \
  "$fixture_base" "$fixture_base" >&2
exit 99
STUB_AWS
  chmod +x "$STUB_AWS_DIR/aws"
  PATH="$STUB_AWS_DIR:$PATH"
  export PATH
}

stub_aws_stop() {
  if [[ -n "${STUB_AWS_ORIGINAL_PATH:-}" ]]; then
    PATH="$STUB_AWS_ORIGINAL_PATH"
    export PATH
  fi
  if [[ -n "${STUB_AWS_DIR:-}" ]]; then
    rm -rf "$STUB_AWS_DIR"
  fi
  unset STUB_AWS_ORIGINAL_PATH STUB_AWS_DIR STUB_AWS_CALL_LOG STUB_AWS_FIXTURE_DIR
}