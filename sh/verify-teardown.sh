#!/usr/bin/env bash
# Phase 1 sweep. Route 53, ACM, and ECR are intentionally out of scope.
set -euo pipefail

readonly EXIT_CLEAN=0
readonly EXIT_ORPHANS=1
readonly EXIT_ERROR=2
readonly IMMORTAL_TAG_KEY="Layer"
readonly IMMORTAL_TAG_VALUE="00-bootstrap"
readonly GLOBAL_REGION="us-east-1"
readonly PROJECT_TAG_KEY="Project"
readonly MAX_TIER3_WORKERS=4
readonly ALLOWLIST="${ALLOWLIST:-sh/teardown-allowlist.txt}"
readonly REPORT="${REPORT:-.teardown-report.json}"
readonly HOME_REGION="${AWS_REGION:-us-east-1}"
export AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-8}"
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

readonly CHECK_REGISTRY='ebs_volumes check_ebs_volumes
security_groups check_security_groups
load_balancers check_load_balancers
target_groups check_target_groups
ec2_instances check_ec2_instances
snapshots check_snapshots
elastic_ips check_elastic_ips
enis check_enis
log_groups check_log_groups
eks_clusters check_eks_clusters
rds_instances check_rds_instances
iam check_iam
cloudfront check_cloudfront
s3_buckets check_s3_buckets
tagged tag_layer_scan'

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
FULL_SCANNED=("$HOME_REGION")
GLOBAL_SCANNED=("$GLOBAL_REGION")
TIER3_SCANNED=()
TIER3_PIDS=()
TIER3_BATCH_REGIONS=()
CHECK_PIDS=()
CHECK_DIRS=()

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
  if [[ "$scope" == s3_bucket_tags:* && "$message" == *NoSuchTagSet* ]]; then
    printf '{"TagSet":[]}'
    return 0
  fi
  case "$message" in
    *PaginationTokenExpired*|*ExpiredNextToken*)
      fail_hard "$scope" "pagination token expired: $message"
      return 1
      ;;
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
check_elastic_ips() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local address
  local id
  local public_ip
  local raw_tags
  local tags
  local arn
  local reason

  if ! response="$(aws_json "${scope_prefix}elastic_ips:$region" ec2 describe-addresses \
    --region "$region" --output json \
    --query 'Addresses[].{id:AllocationId,ip:PublicIp,assoc:AssociationId,instance:InstanceId,eni:NetworkInterfaceId,tags:Tags}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r address; do
    [[ -n "$address" ]] || continue
    id="$(jq -r '.id // .AllocationId // empty' <<< "$address")"
    public_ip="$(jq -r '.ip // .PublicIp // empty' <<< "$address")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$address")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:elastic-ip/${id}"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="public IPv4 address bills hourly whether attached or idle; unassociated Elastic IP (${public_ip})"
    record elastic_ips "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .Addresses[]? end) | select((.assoc // .AssociationId // null) == null)' <<< "$response")
}

check_enis() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local interface
  local id
  local interface_type
  local requester_managed
  local description
  local raw_tags
  local tags
  local arn
  local reason

  if ! response="$(aws_json "${scope_prefix}enis:$region" ec2 describe-network-interfaces \
    --region "$region" --filters 'Name=status,Values=available' \
    --query 'NetworkInterfaces[].{id:NetworkInterfaceId,type:InterfaceType,managed:RequesterManaged,requester:RequesterId,desc:Description,tags:TagSet}' \
    --output json)"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r interface; do
    [[ -n "$interface" ]] || continue
    id="$(jq -r '.id // .NetworkInterfaceId // empty' <<< "$interface")"
    interface_type="$(jq -r '.type // .InterfaceType // "unknown"' <<< "$interface")"
    requester_managed="$(jq -r '(.managed // .RequesterManaged // false) == true' <<< "$interface")"
    description="$(jq -r '.desc // .Description // "no description"' <<< "$interface")"
    raw_tags="$(jq -c '.tags // .TagSet // []' <<< "$interface")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:network-interface/${id}"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    # Detached service-managed interfaces must be removed with their parent, not directly.
    if [[ "$requester_managed" == "true" || "$interface_type" != "interface" ]]; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="detached ENI (${description})"
    record enis "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .NetworkInterfaces[]? end)' <<< "$response")
}

check_load_balancers() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local load_balancer
  local id
  local arn
  local state
  local type
  local dns
  local vpc
  local reason
  local classic_result_dir
  local classic_response_file
  local classic_pid

  classic_result_dir="$WORK_DIR/classic-load-balancers"
  classic_response_file="$classic_result_dir/response.json"
  mkdir -p "$classic_result_dir/work"
  (
    WORK_DIR="$classic_result_dir/work"
    AWS_CALL_COUNT=0
    aws_json "${scope_prefix}classic_load_balancers:$region" elb describe-load-balancers \
      --region "$region" --output json \
      --query 'LoadBalancerDescriptions[].{id:LoadBalancerName,dns:DNSName,vpc:VPCId}' \
      > "$classic_response_file"
  ) &
  classic_pid="$!"

  if ! response="$(aws_json "${scope_prefix}load_balancers:$region" elbv2 describe-load-balancers \
    --region "$region" --output json \
    --query 'LoadBalancers[].{id:LoadBalancerName,arn:LoadBalancerArn,state:State.Code,type:Type,vpc:VpcId}')"; then
    HARD_ERROR=1
    if ! wait "$classic_pid"; then HARD_ERROR=1; fi
    return 1
  else
    while IFS= read -r load_balancer; do
      [[ -n "$load_balancer" ]] || continue
      id="$(jq -r '.id // .LoadBalancerName // empty' <<< "$load_balancer")"
      arn="$(jq -r '.arn // .LoadBalancerArn // empty' <<< "$load_balancer")"
      state="$(jq -r '.state // .State.Code // "unknown"' <<< "$load_balancer")"
      type="$(jq -r '.type // .Type // "unknown"' <<< "$load_balancer")"
      [[ -n "$id" ]] || continue
      if is_immortal "$id" "$arn" '[]'; then
        continue
      fi
      reason="${type} load balancer in ${state} state"
      record load_balancers "$region" "$id" "$arn" "$reason" '{}' blind-spot
    done < <(jq -c '(if type == "array" then .[] else .LoadBalancers[]? end)' <<< "$response")
  fi

  # Classic ELBs are a deliberate extension: their hourly cost warrants one extra enumeration call.
  if ! wait "$classic_pid"; then
    HARD_ERROR=1
    return 1
  fi
  response="$(cat "$classic_response_file")"

  while IFS= read -r load_balancer; do
    [[ -n "$load_balancer" ]] || continue
    id="$(jq -r '.id // .LoadBalancerName // empty' <<< "$load_balancer")"
    dns="$(jq -r '.dns // .DNSName // empty' <<< "$load_balancer")"
    vpc="$(jq -r '.vpc // .VPCId // empty' <<< "$load_balancer")"
    [[ -n "$id" ]] || continue
    arn="arn:aws:elasticloadbalancing:${region}:${ACCOUNT_ID}:loadbalancer/${id}"
    if is_immortal "$id" "$arn" '[]'; then
      continue
    fi
    reason="classic load balancer (${dns}; VPC ${vpc})"
    record load_balancers "$region" "$id" "$arn" "$reason" '{}' blind-spot
  done < <(jq -c '(if type == "array" then .[] else .LoadBalancerDescriptions[]? end)' <<< "$response")
}

check_target_groups() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local target_group
  local id
  local arn
  local raw_tags
  local tags
  local load_balancer_arns
  local reason

  if ! response="$(aws_json "${scope_prefix}target_groups:$region" elbv2 describe-target-groups \
    --region "$region" --output json \
    --query 'TargetGroups[].{id:TargetGroupName,arn:TargetGroupArn,protocol:Protocol,vpc:VpcId,lbs:LoadBalancerArns}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r target_group; do
    [[ -n "$target_group" ]] || continue
    id="$(jq -r '.id // .TargetGroupName // empty' <<< "$target_group")"
    arn="$(jq -r '.arn // .TargetGroupArn // empty' <<< "$target_group")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$target_group")"
    load_balancer_arns="$(jq -c '.lbs // .LoadBalancerArns // []' <<< "$target_group")"
    [[ -n "$id" ]] || continue
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    if jq -e 'type == "array" and length > 0' <<< "$load_balancer_arns" >/dev/null; then
      reason="target group attached to live LB ($(jq -r 'join(", ")' <<< "$load_balancer_arns"))"
    else
      reason="orphan target group with no load balancer attached"
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    record target_groups "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .TargetGroups[]? end)' <<< "$response")
}

check_security_groups() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local security_group
  local id
  local name
  local description
  local description_lower
  local arn
  local raw_tags
  local tags
  local reason

  # shellcheck disable=SC2016
  if ! response="$(aws_json "${scope_prefix}security_groups:$region" ec2 describe-security-groups \
    --region "$region" --output json \
    --query 'SecurityGroups[?GroupName!=`default`].{id:GroupId,name:GroupName,desc:Description,vpc:VpcId,tags:Tags}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r security_group; do
    [[ -n "$security_group" ]] || continue
    name="$(jq -r '.name // .GroupName // empty' <<< "$security_group")"
    # The fixture runner does not apply JMESPath, so repeat the default-group exclusion locally.
    [[ "$name" != "default" ]] || continue
    id="$(jq -r '.id // .GroupId // empty' <<< "$security_group")"
    description="$(jq -r '.desc // .Description // "no description"' <<< "$security_group")"
    raw_tags="$(jq -c '.tags // .Tags // []' <<< "$security_group")"
    arn="arn:aws:ec2:${region}:${ACCOUNT_ID}:security-group/${id}"
    [[ -n "$id" ]] || continue
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    description_lower="$(printf '%s' "$description" | tr '[:upper:]' '[:lower:]')"
    if jq -e 'any(.[]?; .Key == "elbv2.k8s.aws/cluster" or (.Key | startswith("kubernetes.io/cluster/")))' \
      <<< "$raw_tags" >/dev/null || [[ "$name" == k8s-* || "$description_lower" == *controller* ]]; then
      reason="likely controller-created security group (${name}): ${description}"
    else
      reason="non-default security group (${name}): ${description}"
    fi
    record security_groups "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .SecurityGroups[]? end) | select((.name // .GroupName) != "default")' <<< "$response")
}

check_log_groups() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local log_group
  local id
  local arn
  local tag_arn
  local retention
  local stored_bytes
  local tag_response
  local raw_tags
  local tags
  local reason

  # Never filter by /aws/: this namespace contains both project-owned and unrelated groups.
  if ! response="$(aws_json "${scope_prefix}log_groups:$region" logs describe-log-groups \
    --region "$region" --output json \
    --query 'logGroups[].{name:logGroupName,arn:arn,retention:retentionInDays,bytes:storedBytes}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r log_group; do
    [[ -n "$log_group" ]] || continue
    id="$(jq -r '.name // .logGroupName // empty' <<< "$log_group")"
    arn="$(jq -r '.arn // .arn // empty' <<< "$log_group")"
    retention="$(jq -r '.retention // .retentionInDays // "null"' <<< "$log_group")"
    stored_bytes="$(jq -r '.bytes // .storedBytes // 0' <<< "$log_group")"
    [[ -n "$id" ]] || continue

    if [[ "$retention" == "null" ]]; then
      reason="CloudWatch log group with NEVER-EXPIRE retention"
      printf 'verify-teardown: note [%s] %s has NEVER-EXPIRE retention\n' "$region" "$id" >&2
    else
      reason="CloudWatch log group (retention ${retention} days)"
    fi
    if [[ "$stored_bytes" == "0" ]]; then
      reason="${reason}; zero bytes stored"
    fi
    if is_allowlisted "$id" || is_allowlisted "$arn"; then
      continue
    fi

    # Tags are absent from describe-log-groups; resolve ownership only for non-allowlisted candidates.
    tag_arn="${arn%:*}"
    if ! tag_response="$(aws_json "${scope_prefix}log_group_tags:$id" logs list-tags-for-resource \
      --region "$region" --resource-arn "$tag_arn" --output json)"; then
      HARD_ERROR=1
      continue
    fi
    raw_tags="$(jq -c '(.tags // .Tags // {}) as $value | if ($value | type) == "array" then $value else [$value | to_entries[] | {Key:.key,Value:.value}] end' <<< "$tag_response")"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    record log_groups "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .logGroups[]? end)' <<< "$response")
}

check_iam() {
  local region="$1"
  local response
  local role
  local id
  local arn
  local path
  local tag_response
  local raw_tags
  local tags
  local reason

  if ! response="$(aws_json iam:GLOBAL iam list-roles --region "$GLOBAL_REGION" --output json \
    --query 'Roles[].{id:RoleName,arn:Arn,path:Path,created:CreateDate}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r role; do
    [[ -n "$role" ]] || continue
    id="$(jq -r '.id // .RoleName // empty' <<< "$role")"
    arn="$(jq -r '.arn // .Arn // empty' <<< "$role")"
    path="$(jq -r '.path // .Path // "/"' <<< "$role")"
    [[ -n "$id" ]] || continue
    [[ "$path" == /aws-service-role/* ]] && continue
    if is_allowlisted "$id" || is_allowlisted "$arn"; then
      continue
    fi

    # Resolve tags only for surviving candidates; Layer is the durable rule, not a list of role names.
    if ! tag_response="$(aws_json "iam_role_tags:$id" iam list-role-tags --region "$GLOBAL_REGION" \
      --role-name "$id" --output json)"; then
      HARD_ERROR=1
      continue
    fi
    raw_tags="$(jq -c '.Tags // .tags // []' <<< "$tag_response")"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="IAM role at path ${path}"
    record iam GLOBAL "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .Roles[]? end)' <<< "$response")
}

check_cloudfront() {
  local region="$1"
  local response
  local distribution
  local id
  local arn
  local domain
  local status
  local raw_tags='[]'
  local reason

  if ! response="$(aws_json cloudfront:GLOBAL cloudfront list-distributions --region "$GLOBAL_REGION" \
    --output json --query 'DistributionList.Items[].{id:Id,arn:ARN,domain:DomainName,status:Status}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r distribution; do
    [[ -n "$distribution" ]] || continue
    id="$(jq -r '.id // .Id // empty' <<< "$distribution")"
    arn="$(jq -r '.arn // .ARN // empty' <<< "$distribution")"
    domain="$(jq -r '.domain // .DomainName // empty' <<< "$distribution")"
    status="$(jq -r '.status // .Status // "unknown"' <<< "$distribution")"
    [[ -n "$id" ]] || continue
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    reason="CloudFront distribution ${domain} (${status})"
    record cloudfront GLOBAL "$id" "$arn" "$reason" '{}' blind-spot
  done < <(jq -c '(if type == "array" then .[] else .DistributionList.Items[]? end)' <<< "$response")
}

check_s3_buckets() {
  local region="$1"
  local response
  local bucket
  local id
  local arn
  local location_response
  local bucket_region
  local tag_response
  local raw_tags
  local tags
  local created
  local reason

  if ! response="$(aws_json s3_buckets:GLOBAL s3api list-buckets --region "$GLOBAL_REGION" --output json \
    --query 'Buckets[].{id:Name,created:CreationDate}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r bucket; do
    [[ -n "$bucket" ]] || continue
    id="$(jq -r '.id // .Name // empty' <<< "$bucket")"
    created="$(jq -r '.created // .CreationDate // empty' <<< "$bucket")"
    [[ -n "$id" ]] || continue
    if ! location_response="$(aws_json "s3_bucket_location:$id" s3api get-bucket-location \
      --region "$GLOBAL_REGION" --bucket "$id" --output json)"; then
      HARD_ERROR=1
      continue
    fi
    bucket_region="$(jq -r 'if type == "object" then (.LocationConstraint // "us-east-1") else . end' <<< "$location_response")"
    case "$bucket_region" in
      None|null|"") bucket_region=us-east-1 ;;
      EU) bucket_region=eu-west-1 ;;
    esac
    arn="arn:aws:s3:::${id}"
    if ! tag_response="$(aws_json "s3_bucket_tags:$id" s3api get-bucket-tagging \
      --region "$bucket_region" --bucket "$id" --output json)"; then
      HARD_ERROR=1
      continue
    fi
    raw_tags="$(jq -c '.TagSet // .Tags // []' <<< "$tag_response")"
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="S3 bucket in ${bucket_region}"
    [[ -n "$created" ]] && reason="${reason}, created ${created}"
    record s3_buckets "$bucket_region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .Buckets[]? end)' <<< "$response")
}

tag_layer_scan() {
  local region="$1"
  local scope_prefix="${2:-}"
  local token=""
  local page
  local item
  local arn
  local id
  local raw_tags
  local tags
  local reason

  # This API omits untagged resources; blind-spot checks must still find them.
  while :; do
    if [[ -n "$token" ]]; then
      if ! page="$(aws_json "${scope_prefix}tag_layer:$region" resourcegroupstaggingapi get-resources \
        --region "$region" --tag-filters "Key=${PROJECT_TAG_KEY}" --resources-per-page 100 \
        --pagination-token "$token" --no-paginate --output json)"; then
        HARD_ERROR=1
        return 1
      fi
    else
      if ! page="$(aws_json "${scope_prefix}tag_layer:$region" resourcegroupstaggingapi get-resources \
        --region "$region" --tag-filters "Key=${PROJECT_TAG_KEY}" --resources-per-page 100 \
        --no-paginate --output json)"; then
        HARD_ERROR=1
        return 1
      fi
    fi

    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      arn="$(jq -r '.ResourceARN // .arn // empty' <<< "$item")"
      [[ -n "$arn" ]] || continue
      id="${arn##*/}"
      raw_tags="$(jq -c '.Tags // .tags // []' <<< "$item")"
      if is_immortal "$id" "$arn" "$raw_tags"; then
        continue
      fi
      tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
      reason="Project-tagged resource is not owned by the bootstrap layer"
      record tagged "$region" "$id" "$arn" "$reason" "$tags" tag
    done < <(jq -c '.ResourceTagMappingList[]?' <<< "$page")

    token="$(jq -r '.PaginationToken // .token // ""' <<< "$page")"
    [[ -n "$token" ]] || break
  done
}

check_eks_clusters() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local detail
  local cluster_name
  local cluster
  local arn
  local status
  local raw_tags
  local tags
  local reason

  if ! response="$(aws_json "${scope_prefix}eks_clusters:$region" eks list-clusters \
    --region "$region" --output json)"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r cluster_name; do
    [[ -n "$cluster_name" ]] || continue
    if ! detail="$(aws_json "${scope_prefix}eks_cluster_detail:$region" eks describe-cluster \
      --region "$region" --name "$cluster_name" --output json)"; then
      HARD_ERROR=1
      continue
    fi
    cluster="$(jq -c '.cluster // .' <<< "$detail")"
    arn="$(jq -r '.arn // .Arn // empty' <<< "$cluster")"
    status="$(jq -r '.status // .Status // "unknown"' <<< "$cluster")"
    raw_tags="$(jq -c '.tags // .Tags // {} | if type == "array" then . else [to_entries[] | {Key:.key,Value:.value}] end' <<< "$cluster")"
    if is_immortal "$cluster_name" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="EKS cluster in ${status} state"
    record eks_clusters "$region" "$cluster_name" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -r 'if type == "array" then .[] else .clusters[]? end | strings' <<< "$response")
}

check_rds_instances() {
  local region="$1"
  local scope_prefix="${2:-}"
  local response
  local instance
  local id
  local arn
  local status
  local raw_tags
  local tags
  local reason

  if ! response="$(aws_json "${scope_prefix}rds_instances:$region" rds describe-db-instances \
    --region "$region" --output json \
    --query 'DBInstances[].{id:DBInstanceIdentifier,arn:DBInstanceArn,status:DBInstanceStatus,tags:TagList}')"; then
    HARD_ERROR=1
    return 1
  fi

  while IFS= read -r instance; do
    [[ -n "$instance" ]] || continue
    id="$(jq -r '.id // .DBInstanceIdentifier // empty' <<< "$instance")"
    arn="$(jq -r '.arn // .DBInstanceArn // empty' <<< "$instance")"
    status="$(jq -r '.status // .DBInstanceStatus // "unknown"' <<< "$instance")"
    raw_tags="$(jq -c '.tags // .TagList // []' <<< "$instance")"
    [[ -n "$id" ]] || continue
    if is_immortal "$id" "$arn" "$raw_tags"; then
      continue
    fi
    tags="$(jq -c 'reduce (. // [])[] as $tag ({}; .[$tag.Key]=$tag.Value)' <<< "$raw_tags")"
    reason="RDS instance in ${status} state"
    record rds_instances "$region" "$id" "$arn" "$reason" "$tags" blind-spot
  done < <(jq -c '(if type == "array" then .[] else .DBInstances[]? end)' <<< "$response")
}

enabled_regions() {
  local response

  # The bare describe-regions call returns enabled regions; --all-regions includes opted-out regions.
  if ! response="$(aws_json "enabled_regions:$HOME_REGION" ec2 describe-regions \
    --region "$HOME_REGION" --output json)"; then
    return 1
  fi
  jq -r 'if type == "array" then .[] else .Regions[]?.RegionName end | strings' <<< "$response" | sort -u
}

run_tier3_region() {
  local region="$1"
  local result_dir="$2"

  WORK_DIR="${result_dir}/work"
  FINDINGS="${result_dir}/findings.ndjson"
  ERRORS="${result_dir}/errors.ndjson"
  mkdir -p "$WORK_DIR"
  : > "$FINDINGS"
  : > "$ERRORS"
  AWS_CALL_COUNT=0
  HARD_ERROR=0
  CHECK_PIDS=()
  CHECK_DIRS=()

  queue_check check_ec2_instances "$region" "tier3:"
  queue_check check_eks_clusters "$region" "tier3:"
  queue_check check_load_balancers "$region" "tier3:"
  queue_check check_rds_instances "$region" "tier3:"
  queue_check check_elastic_ips "$region" "tier3:"
  collect_checks

  (( HARD_ERROR == 0 ))
}

run_check_worker() {
  local check_function="$1"
  local region="$2"
  local result_dir="$3"
  local scope_prefix="${4:-}"

  WORK_DIR="${result_dir}/work"
  FINDINGS="${result_dir}/findings.ndjson"
  ERRORS="${result_dir}/errors.ndjson"
  mkdir -p "$WORK_DIR"
  : > "$FINDINGS"
  : > "$ERRORS"
  AWS_CALL_COUNT=0
  HARD_ERROR=0

  case "$check_function" in
    tag_layer_scan) tag_layer_scan "$region" || HARD_ERROR=1 ;;
    check_ebs_volumes) check_ebs_volumes "$region" || HARD_ERROR=1 ;;
    check_ec2_instances) check_ec2_instances "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_snapshots) check_snapshots "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_elastic_ips) check_elastic_ips "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_enis) check_enis "$region" || HARD_ERROR=1 ;;
    check_load_balancers) check_load_balancers "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_target_groups) check_target_groups "$region" || HARD_ERROR=1 ;;
    check_security_groups) check_security_groups "$region" || HARD_ERROR=1 ;;
    check_log_groups) check_log_groups "$region" || HARD_ERROR=1 ;;
    check_eks_clusters) check_eks_clusters "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_rds_instances) check_rds_instances "$region" "$scope_prefix" || HARD_ERROR=1 ;;
    check_iam) check_iam "$region" || HARD_ERROR=1 ;;
    check_cloudfront) check_cloudfront "$region" || HARD_ERROR=1 ;;
    check_s3_buckets) check_s3_buckets "$region" || HARD_ERROR=1 ;;
    *)
      fail_hard "check_worker:$check_function" "check is not registered for worker execution"
      HARD_ERROR=1
      ;;
  esac
  (( HARD_ERROR == 0 ))
}

queue_check() {
  local check_function="$1"
  local region="$2"
  local scope_prefix="${3:-}"
  local result_dir="$WORK_DIR/check-${check_function}"

  mkdir -p "$result_dir"
  (run_check_worker "$check_function" "$region" "$result_dir" "$scope_prefix") &
  CHECK_PIDS+=("$!")
  CHECK_DIRS+=("$result_dir")
}

collect_checks() {
  local index=0
  local result_dir

  while [[ -n "${CHECK_PIDS[$index]:-}" ]]; do
    result_dir="${CHECK_DIRS[$index]}"
    if ! wait "${CHECK_PIDS[$index]}"; then
      HARD_ERROR=1
    fi
    cat "$result_dir/findings.ndjson" >> "$FINDINGS"
    cat "$result_dir/errors.ndjson" >> "$ERRORS"
    index=$((index + 1))
  done
  CHECK_PIDS=()
  CHECK_DIRS=()
}

collect_tier3_batch() {
  local index
  local region
  local result_dir

  index=0
  while [[ -n "${TIER3_PIDS[$index]:-}" ]]; do
    region="${TIER3_BATCH_REGIONS[$index]}"
    result_dir="$WORK_DIR/tier3-${region}"
    if ! wait "${TIER3_PIDS[$index]}"; then
      HARD_ERROR=1
    fi
    cat "$result_dir/findings.ndjson" >> "$FINDINGS"
    cat "$result_dir/errors.ndjson" >> "$ERRORS"
    index=$((index + 1))
  done
  TIER3_PIDS=()
  TIER3_BATCH_REGIONS=()
}

assert_class_coverage() {
  local class
  local registered_class
  local registered_function
  local check_function
  local registered_count

  while IFS= read -r class; do
    [[ -n "$class" ]] || continue
    registered_count=0
    check_function=""
    while IFS=' ' read -r registered_class registered_function; do
      [[ -n "$registered_class" ]] || continue
      if [[ "$registered_class" == "$class" ]]; then
        registered_count=$((registered_count + 1))
        check_function="$registered_function"
      fi
    done <<< "$CHECK_REGISTRY"
    if (( registered_count != 1 )); then
      fail_hard class_coverage "report class '$class' has $registered_count registered checks"
      return 1
    fi
    if ! declare -F "$check_function" >/dev/null; then
      fail_hard class_coverage "report class '$class' references missing function '$check_function'"
      return 1
    fi
  done <<< "$CLASS_KEYS"

  while IFS=' ' read -r registered_class registered_function; do
    [[ -n "$registered_class" ]] || continue
    if ! printf '%s\n' "$CLASS_KEYS" | grep -Fxq "$registered_class"; then
      fail_hard class_coverage "registered check '$registered_class' is absent from the report schema"
      return 1
    fi
  done <<< "$CHECK_REGISTRY"
}

usual_cause() {
  case "$1" in
    ebs_volumes) printf '%s' 'node group deletion left detached EBS volumes' ;;
    ec2_instances) printf '%s' 'stopped or unterminated EC2 instance' ;;
    snapshots) printf '%s' 'manual or AMI-backed snapshots retained' ;;
    elastic_ips) printf '%s' 'unassociated public IPv4 allocation retained' ;;
    enis) printf '%s' 'parent teardown left a detached interface' ;;
    eks_clusters) printf '%s' 'stray cluster remains billable by hour' ;;
    rds_instances) printf '%s' 'database instance remains billable after teardown' ;;
    tagged) printf '%s' 'Project-tagged resource lacks bootstrap ownership' ;;
    *) printf '%s' 'resource retained after parent teardown' ;;
  esac
}

write_report() {
  local exit_code="$1"
  local verdict
  local class_json
  local findings_json
  local errors_json
  local full_regions_json
  local global_regions_json
  local tier3_regions_json

  case "$exit_code" in
    "$EXIT_CLEAN") verdict=clean ;;
    "$EXIT_ORPHANS") verdict=orphans ;;
    *) verdict=error ;;
  esac

  class_json="$(printf '%s\n' "$CLASS_KEYS" | jq -R 'select(length > 0)' | jq -s '.')"
  findings_json="$(jq -s '.' "$FINDINGS")"
  errors_json="$(jq -s '.' "$ERRORS")"
  full_regions_json="$(printf '%s\n' "${FULL_SCANNED[@]-}" | jq -R 'select(length > 0)' | jq -s '.')"
  global_regions_json="$(printf '%s\n' "${GLOBAL_SCANNED[@]-}" | jq -R 'select(length > 0)' | jq -s '.')"
  tier3_regions_json="$(printf '%s\n' "${TIER3_SCANNED[@]-}" | jq -R 'select(length > 0)' | jq -s '.')"

  jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg account_id "$ACCOUNT_ID" --arg caller_arn "$CALLER_ARN" \
    --arg home_region "$HOME_REGION" --arg allowlist_file "$ALLOWLIST" \
    --argjson allowlist_entries "$ALLOWLIST_COUNT" --argjson exit_code "$exit_code" \
    --arg verdict "$verdict" --argjson classes "$class_json" \
    --argjson findings "$findings_json" --argjson errors "$errors_json" \
    --argjson full_regions "$full_regions_json" --argjson global_regions "$global_regions_json" \
    --argjson tier3_regions "$tier3_regions_json" '
      {
        schema_version: 1,
        generated_at: $generated_at,
        account_id: $account_id,
        caller_arn: $caller_arn,
        home_region: $home_region,
        regions_scanned: {full: $full_regions, global: $global_regions, tier3: $tier3_regions},
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
  local class_count
  local cause

  total="$(jq -r '.summary.total_orphans' "$REPORT")"
  if [[ "$total" -eq 0 ]]; then
    printf '\nverify-teardown: no orphans found in the wired classes.\n'
  else
    printf '\nORPHANS (%s)\n' "$total"
    while IFS= read -r class; do
      [[ -n "$class" ]] || continue
      rows="$(jq -r --arg class "$class" '.orphans[$class][]? | [.region,.id,.reason] | @tsv' "$REPORT")"
      [[ -n "$rows" ]] || continue
      class_count="$(jq -r --arg class "$class" '.summary.by_class[$class]' "$REPORT")"
      cause="$(usual_cause "$class")"
      printf '\n  %s (%s)  usual cause: %s\n' "$class" "$class_count" "$cause"
      while IFS=$'\t' read -r region id reason; do
        printf '    %-12s %-32s %s\n' "$region" "$id" "$reason"
      done <<< "$rows"
    done <<< "$CLASS_KEYS"
  fi
}

main() {
  local exit_code
  local region_list
  local region
  local result_dir
  local region_list_file
  local region_pid
  local regions_enabled=0

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

  if ! assert_class_coverage; then
    write_report "$EXIT_ERROR"
    print_table
    exit "$EXIT_ERROR"
  fi

  queue_check tag_layer_scan "$HOME_REGION"
  queue_check check_ebs_volumes "$HOME_REGION"
  queue_check check_ec2_instances "$HOME_REGION"
  queue_check check_snapshots "$HOME_REGION"
  queue_check check_elastic_ips "$HOME_REGION"
  queue_check check_enis "$HOME_REGION"
  queue_check check_load_balancers "$HOME_REGION"
  queue_check check_target_groups "$HOME_REGION"
  queue_check check_security_groups "$HOME_REGION"
  queue_check check_log_groups "$HOME_REGION"
  queue_check check_eks_clusters "$HOME_REGION"
  queue_check check_rds_instances "$HOME_REGION"
  queue_check check_iam "$GLOBAL_REGION"
  queue_check check_cloudfront "$GLOBAL_REGION"
  queue_check check_s3_buckets "$GLOBAL_REGION"

  region_list_file="$WORK_DIR/enabled-regions.txt"
  (enabled_regions > "$region_list_file") &
  region_pid="$!"
  if wait "$region_pid"; then
    region_list="$(cat "$region_list_file")"
    regions_enabled=1
  fi

  if (( regions_enabled )); then
    while IFS= read -r region; do
      [[ -n "$region" ]] || continue
      [[ "$region" == "$HOME_REGION" ]] && continue
      TIER3_SCANNED+=("$region")
      result_dir="$WORK_DIR/tier3-${region}"
      mkdir -p "$result_dir"
      (run_tier3_region "$region" "$result_dir") &
      TIER3_PIDS+=("$!")
      TIER3_BATCH_REGIONS+=("$region")
      if (( ${#TIER3_PIDS[@]} >= MAX_TIER3_WORKERS )); then
        collect_tier3_batch
      fi
    done <<< "$region_list"
    collect_tier3_batch
  else
    HARD_ERROR=1
  fi
  collect_checks

  # Errors outrank findings: after mid-sweep credential expiry, counts are only a lower bound.
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
