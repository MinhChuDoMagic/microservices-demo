#!/usr/bin/env bash
# Phase 1 sweep. Route 53, ACM, and ECR are intentionally out of scope.
set -euo pipefail

readonly EXIT_CLEAN=0
readonly EXIT_ORPHANS=1
readonly EXIT_ERROR=2
readonly IMMORTAL_TAG_KEY="Layer"
readonly IMMORTAL_TAG_VALUE="00-bootstrap"
readonly ALLOWLIST="${ALLOWLIST:-scripts/teardown-allowlist.txt}"
readonly REPORT="${REPORT:-.teardown-report.json}"
readonly HOME_REGION="${AWS_REGION:-us-east-1}"
readonly CLASS_KEYS='ebs_volumes
security_groups
load_balancers
target_groups
ec2_instances
snapshots
elastic_ips
enis
log_groups
eks_clusters
rds_instances
iam
cloudfront
s3_buckets
tagged'

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-teardown.XXXXXX")"
FINDINGS="$WORK_DIR/findings.ndjson"
ERRORS="$WORK_DIR/errors.ndjson"
: > "$FINDINGS"
: > "$ERRORS"

HARD_ERROR=0
ACCOUNT_ID=""
CALLER_ARN=""
ALLOW=("")
AWS_CALL_COUNT=0
ALLOWLIST_COUNT=0

# shellcheck disable=SC2329
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# shellcheck disable=SC2329
on_err() {
  local rc=$?
  local line="$1"
  printf 'verify-teardown: INTERNAL ERROR at line %s (rc=%s)\n' "$line" "$rc" >&2
  exit "$EXIT_ERROR"
}
trap 'on_err "$LINENO"' ERR

fail_hard() {
  local scope="$1"
  local message="$2"
  HARD_ERROR=1
  jq -nc --arg scope "$scope" --arg message "$message" \
    '{scope:$scope,message:$message}' >> "$ERRORS"
  printf 'verify-teardown: ERROR [%s] %s\n' "$scope" "$message" >&2
}

record() {
  local class="$1"
  local region="$2"
  local id="$3"
  local arn="$4"
  local reason="$5"
  local tags="$6"
  local discovered_by="$7"
  jq -nc --arg class "$class" --arg region "$region" --arg id "$id" \
    --arg arn "$arn" --arg reason "$reason" --argjson tags "$tags" \
    --arg discovered_by "$discovered_by" \
    '{class:$class,id:$id,arn:$arn,region:$region,reason:$reason,tags:$tags,discovered_by:$discovered_by}' \
    >> "$FINDINGS"
}

aws_json() {
  local scope="$1"
  shift
  local stdout_file
  local stderr_file
  local rc
  local message

  AWS_CALL_COUNT=$((AWS_CALL_COUNT + 1))
  stdout_file="$WORK_DIR/stdout.$AWS_CALL_COUNT"
  stderr_file="$WORK_DIR/stderr.$AWS_CALL_COUNT"

  if aws "$@" > "$stdout_file" 2> "$stderr_file"; then
    cat "$stdout_file"
    return 0
  else
    rc=$?
  fi

  message="$(tr -d '\r' < "$stderr_file" | tail -3 | tr '\n' ' ')"
  case "$message" in
    *AccessDenied*|*UnauthorizedOperation*|*AuthFailure*|*ExpiredToken*|\
    *InvalidClientTokenId*|*SignatureDoesNotMatch*|*"Unable to locate credentials"*|\
    *"security token included in the request is expired"*)
      fail_hard "$scope" "credential/permission failure: $message"
      return 1
      ;;
    *OptInRequired*|*"Could not connect to the endpoint URL"*|*EndpointConnectionError*|\
    *UnsupportedOperation*|*InvalidAction*)
      case "$scope" in
        tier3:*)
          printf 'verify-teardown: note [%s] service unavailable in region; skipping\n' "$scope" >&2
          printf 'null'
          return 0
          ;;
      esac
      fail_hard "$scope" "endpoint/service unavailable: $message"
      return 1
      ;;
    *Throttl*|*RequestLimitExceeded*)
      fail_hard "$scope" "throttled (set AWS_RETRY_MODE=adaptive): $message"
      return 1
      ;;
    *)
      fail_hard "$scope" "unclassified AWS error (rc=$rc): $message"
      return 1
      ;;
  esac
}

preflight() {
  local identity

  if ! command -v aws >/dev/null 2>&1; then
    HARD_ERROR=1
    printf '%s\n' '{"scope":"preflight","message":"aws CLI v2 not found"}' >> "$ERRORS"
    printf '%s\n' 'verify-teardown: aws CLI v2 not found' >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    HARD_ERROR=1
    printf '%s\n' '{"scope":"preflight","message":"jq not found"}' >> "$ERRORS"
    printf '%s\n' 'verify-teardown: jq not found' >&2
    return 1
  fi

  if ! identity="$(aws_json preflight sts get-caller-identity --output json)"; then
    return 1
  fi
  ACCOUNT_ID="$(jq -r '.Account' <<< "$identity")"
  CALLER_ARN="$(jq -r '.Arn' <<< "$identity")"
  printf 'verify-teardown: account %s as %s\n' "$ACCOUNT_ID" "$CALLER_ARN"
  return 0
}

load_allowlist() {
  local allow_text
  local item

  if [[ ! -f "$ALLOWLIST" ]]; then
    fail_hard preflight "allowlist not found: $ALLOWLIST"
    return 1
  fi

  allow_text="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$ALLOWLIST" | grep -v '^$' || true)"
  ALLOW=("")
  ALLOWLIST_COUNT=0
  while IFS= read -r item; do
    if [[ -n "$item" ]]; then
      ALLOW[${#ALLOW[@]}]="$item"
      ALLOWLIST_COUNT=$((ALLOWLIST_COUNT + 1))
    fi
  done <<< "$allow_text"
  return 0
}

is_allowlisted() {
  local needle="$1"
  local allowed
  for allowed in "${ALLOW[@]}"; do
    [[ "$needle" == "$allowed" ]] && return 0
  done
  return 1
}

is_immortal() {
  local id="$1"
  local arn="$2"
  local tags="$3"

  is_allowlisted "$id" && return 0
  is_allowlisted "$arn" && return 0
  jq -e --arg key "$IMMORTAL_TAG_KEY" --arg value "$IMMORTAL_TAG_VALUE" \
    'any(.[]?; .Key == $key and .Value == $value)' <<< "${tags:-[]}" >/dev/null 2>&1
}

check_ebs_volumes() {
  local region="$1"
  local response
  local volume
  local id
  local size
  local volume_type
  local arn
  local raw_tags
  local tags
  local reason

  if ! response="$(aws_json "ebs_volumes:$region" ec2 describe-volumes \
    --region "$region" --filters 'Name=status,Values=available' \
    --query 'Volumes[].{id:VolumeId,size:Size,type:VolumeType,status:State,az:AvailabilityZone,created:CreateTime,tags:Tags}' \
    --output json)"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r volume; do
    [[ -n "$volume" ]] || continue
    id="$(jq -r '.id // .VolumeId // empty' <<< "$volume")"
    size="$(jq -r '.size // .Size // 0' <<< "$volume")"
    volume_type="$(jq -r '.type // .VolumeType // "unknown"' <<< "$volume")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$volume")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:volume/${id}"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="available (detached) ${volume_type} volume, ${size} GiB"
    record ebs_volumes "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .Volumes[]? end) | select((.status // .State) == "available")' <<< "$response")
}

check_ec2_instances() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local instance
  local id
  local state
  local instance_type
  local raw_tags
  local tags
  local arn
  local reason

  if ! response="$(aws_json "${scope_prefix}ec2_instances:$region" ec2 describe-instances \
    --region "$region" --filters 'Name=instance-state-name,Values=pending,running,stopping,stopped' \
    --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name,tags:Tags}' \
    --output json)"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r instance; do
    [[ -n "$instance" ]] || continue
    id="$(jq -r '.id // .InstanceId // empty' <<< "$instance")"
    state="$(jq -r '.state // .State.Name // empty' <<< "$instance")"
    instance_type="$(jq -r '.type // .InstanceType // "unknown"' <<< "$instance")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$instance")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:instance/${id}"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    if [[ "$state" == "stopped" ]]; then
      reason="stopped instance; root EBS volume continues billing"
    else
      reason="${state} EC2 instance (${instance_type})"
    fi
    record ec2_instances "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '
    (if type == "array" then .[] else .Reservations[]?.Instances[]? end)
    | select((.state // .State.Name // "") as $state
      | (["pending", "running", "stopping", "stopped"] | index($state)) != null)
  ' <<< "$response")
}

check_snapshots() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local images_response
  local image_snapshot_ids
  local snapshot
  local id
  local description
  local size
  local raw_tags
  local tags
  local arn
  local reason

  # --owner-ids self is load-bearing: without it, this call enumerates every public snapshot on AWS.
  if ! response="$(aws_json "${scope_prefix}snapshots:$region" ec2 describe-snapshots \
    --region "$region" --owner-ids self --output json \
    --query 'Snapshots[].{id:SnapshotId,size:VolumeSize,desc:Description,tags:Tags}')"; then
    HARD_ERROR=1
    return 1
  fi
  if ! images_response="$(aws_json "${scope_prefix}snapshot_images:$region" ec2 describe-images \
    --region "$region" --owners self --output json \
    --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId')"; then
    HARD_ERROR=1
    return 1
  fi
  image_snapshot_ids="$(jq -c '[ (if type == "array" then .[] else .Images[]?.BlockDeviceMappings[]?.Ebs.SnapshotId? end) | select(type == "string") ] | unique' <<< "$images_response")"

  while IFS= read -r snapshot; do
    [[ -n "$snapshot" ]] || continue
    id="$(jq -r '.id // .SnapshotId // empty' <<< "$snapshot")"
    description="$(jq -r '.desc // .Description // empty' <<< "$snapshot")"
    size="$(jq -r '.size // .VolumeSize // 0' <<< "$snapshot")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$snapshot")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:snapshot/${id}"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    if [[ "$description" == "Created by CreateImage("* ]] \
      && jq -e --arg id "$id" 'index($id) != null' <<< "$image_snapshot_ids" >/dev/null; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="manual EBS snapshot (${size} GiB): ${description}"
    record snapshots "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .Snapshots[]? end)' <<< "$response")
}
write_report() {
  local exit_code="$1"
  local verdict
  local class_json
  local findings_json
  local errors_json

  case "$exit_code" in
    "$EXIT_CLEAN") verdict=clean ;;
    "$EXIT_ORPHANS") verdict=orphans ;;
    *) verdict=error ;;
  esac

  class_json="$(printf '%s\n' "$CLASS_KEYS" | jq -R 'select(length > 0)' | jq -s '.')"
  findings_json="$(jq -s '.' "$FINDINGS")"
  errors_json="$(jq -s '.' "$ERRORS")"

  jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg account_id "$ACCOUNT_ID" --arg caller_arn "$CALLER_ARN" \
    --arg home_region "$HOME_REGION" --arg allowlist_file "$ALLOWLIST" \
    --argjson allowlist_entries "$ALLOWLIST_COUNT" --argjson exit_code "$exit_code" \
    --arg verdict "$verdict" --argjson classes "$class_json" \
    --argjson findings "$findings_json" --argjson errors "$errors_json" '
      {
        schema_version: 1,
        generated_at: $generated_at,
        account_id: $account_id,
        caller_arn: $caller_arn,
        home_region: $home_region,
        regions_scanned: {full: [$home_region], global: [], tier3: []},
        allowlist_file: $allowlist_file,
        allowlist_entries: $allowlist_entries,
        exit_code: $exit_code,
        verdict: $verdict,
        summary: {
          total_orphans: ($findings | length),
          by_class: (reduce $classes[] as $class ({};
            .[$class] = ([$findings[] | select(.class == $class)] | length))),
          by_region: (reduce ($findings | group_by(.region))[] as $group ({};
            .[$group[0].region] = ($group | length)))
        },
        orphans: (reduce $classes[] as $class ({};
          .[$class] = [$findings[] | select(.class == $class)])),
        errors: $errors
      }
    ' > "$REPORT"
}

print_table() {
  local class
  local rows
  local region
  local id
  local reason
  local total

  total="$(jq -r '.summary.total_orphans' "$REPORT")"
  if [[ "$total" -eq 0 ]]; then
    printf '\nverify-teardown: no orphans found in the wired classes.\n'
  else
    printf '\nORPHANS (%s)\n' "$total"
    while IFS= read -r class; do
      [[ -n "$class" ]] || continue
      rows="$(jq -r --arg class "$class" '.orphans[$class][]? | [.region,.id,.reason] | @tsv' "$REPORT")"
      [[ -n "$rows" ]] || continue
      printf '\n  %s (usual cause: detached resource retained after parent teardown)\n' "$class"
      while IFS=$'\t' read -r region id reason; do
        printf '    %-12s %-32s %s\n' "$region" "$id" "$reason"
      done <<< "$rows"
    done <<< "$CLASS_KEYS"
  fi
}

main() {
  local exit_code

  if ! preflight; then
    if command -v jq >/dev/null 2>&1; then
      write_report "$EXIT_ERROR"
      print_table
    fi
    exit "$EXIT_ERROR"
  fi

  if ! load_allowlist; then
    write_report "$EXIT_ERROR"
    print_table
    exit "$EXIT_ERROR"
  fi

  if ! check_ebs_volumes "$HOME_REGION"; then
    HARD_ERROR=1
  fi
  if ! check_ec2_instances "$HOME_REGION"; then
    HARD_ERROR=1
  fi
  if ! check_snapshots "$HOME_REGION"; then
    HARD_ERROR=1
  fi

  if (( HARD_ERROR )); then
    exit_code="$EXIT_ERROR"
  elif [[ -s "$FINDINGS" ]]; then
    exit_code="$EXIT_ORPHANS"
  else
    exit_code="$EXIT_CLEAN"
  fi

  write_report "$exit_code"
  print_table

  if [[ "$exit_code" -eq "$EXIT_ERROR" ]]; then
    printf 'verify-teardown: RESULT UNKNOWN - %s check(s) failed; do NOT assume clean.\n' \
      "$(wc -l < "$ERRORS" | tr -d ' ')" >&2
  elif [[ "$exit_code" -eq "$EXIT_ORPHANS" ]]; then
    printf 'verify-teardown: %s orphan(s) found; account is DIRTY.\n' \
      "$(wc -l < "$FINDINGS" | tr -d ' ')" >&2
  else
    printf 'verify-teardown: account is CLEAN for the wired classes.\n'
  fi
  exit "$exit_code"
}

main "$@"
