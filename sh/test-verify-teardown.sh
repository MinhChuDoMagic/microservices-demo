#!/usr/bin/env bash
set -euo pipefail

readonly HOME_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT
readonly SWEEP="${ROOT}/sh/verify-teardown.sh"
readonly REPORT="${ROOT}/.teardown-report.json"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
readonly RUN_ID
readonly VOLUME_TAG_KEY="TeardownHardGateRun"
readonly VOLUME_TAG_VALUE="${RUN_ID}"
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-teardown-test.XXXXXX")"
readonly OUTPUT_DIR

VOLUME_ID=""
CLEANUP_DONE=0

cleanup() {
  local original_status=$?
  local candidate_ids
  local candidate_id
  local state
  local cleanup_failed=0

  trap - EXIT INT TERM HUP
  if (( CLEANUP_DONE )); then
    exit "$original_status"
  fi
  CLEANUP_DONE=1

  if [[ -n "$VOLUME_ID" ]]; then
    candidate_ids="$VOLUME_ID"
  else
    candidate_ids="$(aws ec2 describe-volumes \
      --filters "Name=tag:${VOLUME_TAG_KEY},Values=${VOLUME_TAG_VALUE}" \
      --query 'Volumes[].VolumeId' --output text 2>/dev/null || true)"
  fi

  for candidate_id in $candidate_ids; do
    [[ -n "$candidate_id" && "$candidate_id" != "None" ]] || continue
    if aws ec2 delete-volume --volume-id "$candidate_id" >/dev/null 2>&1; then
      if ! aws ec2 wait volume-deleted --volume-ids "$candidate_id" >/dev/null 2>&1; then
        cleanup_failed=1
      fi
    else
      state="$(aws ec2 describe-volumes --volume-ids "$candidate_id" \
        --query 'Volumes[0].State' --output text 2>/dev/null || true)"
      if [[ -n "$state" && "$state" != "None" && "$state" != "deleted" ]]; then
        cleanup_failed=1
      fi
    fi
  done

  rm -rf "$OUTPUT_DIR"
  if (( cleanup_failed )); then
    printf '%s\n' 'FAIL: cleanup could not confirm the test volume was deleted.' >&2
    (( original_status == 0 )) && original_status=12
  fi
  exit "$original_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

capture_sweep() {
  local output_file="$1"
  if "$SWEEP" > "$output_file" 2>&1; then
    return 0
  else
    return "$?"
  fi
}

report_contains_volume() {
  jq -e --arg id "$VOLUME_ID" \
    'any(.orphans.ebs_volumes[]?; .id == $id)' "$REPORT" >/dev/null
}

printf 'Hard-gate test account: %s\n' "$(aws sts get-caller-identity --query Account --output text)"

if capture_sweep "$OUTPUT_DIR/arm-1.log"; then
  printf '%s\n' 'PASS arm 1: clean baseline.'
else
  rc=$?
  cat "$OUTPUT_DIR/arm-1.log"
  printf 'FAIL: clean baseline returned %s; refusing to create a volume.\n' "$rc" >&2
  exit 10
fi

availability_zone="$(aws ec2 describe-availability-zones \
  --region "$HOME_REGION" --filters Name=state,Values=available \
  --query 'AvailabilityZones[0].ZoneName' --output text)"

# The trap is active before creation; its unique description recovers a volume if the ID
# assignment is interrupted after AWS has accepted the create request.
create_response="$(aws ec2 create-volume --region "$HOME_REGION" \
  --availability-zone "$availability_zone" --size 1 --volume-type gp3 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=${VOLUME_TAG_KEY},Value=${VOLUME_TAG_VALUE}}]" \
  --output json)"
VOLUME_ID="$(jq -r '.VolumeId // empty' <<< "$create_response")"
if [[ -z "$VOLUME_ID" ]]; then
  printf '%s\n' 'FAIL: create-volume returned no volume ID.' >&2
  exit 11
fi

aws ec2 wait volume-available --region "$HOME_REGION" --volume-ids "$VOLUME_ID"
aws ec2 delete-tags --region "$HOME_REGION" --resources "$VOLUME_ID" \
  --tags "Key=${VOLUME_TAG_KEY}"
if capture_sweep "$OUTPUT_DIR/arm-2.log"; then
  rc=0
else
  rc=$?
fi
cat "$OUTPUT_DIR/arm-2.log"
if (( rc != 1 )) || ! report_contains_volume; then
  printf 'FAIL: orphan arm returned %s or did not report volume %s.\n' "$rc" "$VOLUME_ID" >&2
  exit 11
fi
printf 'PASS arm 2: untagged volume %s was reported as an orphan.\n' "$VOLUME_ID"

if ! aws ec2 delete-volume --region "$HOME_REGION" --volume-id "$VOLUME_ID" >/dev/null; then
  printf 'FAIL: could not delete test volume %s.\n' "$VOLUME_ID" >&2
  exit 12
fi
aws ec2 wait volume-deleted --region "$HOME_REGION" --volume-ids "$VOLUME_ID"
VOLUME_ID=""

if capture_sweep "$OUTPUT_DIR/arm-2-clean.log"; then
  printf '%s\n' 'PASS arm 2 cleanup: sweep returned clean after volume deletion.'
else
  rc=$?
  cat "$OUTPUT_DIR/arm-2-clean.log"
  printf 'FAIL: clean-after-delete sweep returned %s.\n' "$rc" >&2
  exit 12
fi

if env -u AWS_PROFILE AWS_ACCESS_KEY_ID=invalid AWS_SECRET_ACCESS_KEY=invalid \
  AWS_SESSION_TOKEN=invalid AWS_REGION="$HOME_REGION" "$SWEEP" \
  > "$OUTPUT_DIR/arm-3.log" 2>&1; then
  rc=0
else
  rc=$?
fi
cat "$OUTPUT_DIR/arm-3.log"
if (( rc != 2 )) || grep -Fq 'account is CLEAN' "$OUTPUT_DIR/arm-3.log" \
  || ! jq -e '.verdict == "error" and .exit_code == 2' "$REPORT" >/dev/null; then
  printf 'FAIL: invalid-credential arm returned %s or emitted a clean verdict.\n' "$rc" >&2
  exit 13
fi
printf '%s\n' 'PASS arm 3: invalid credentials returned error, never clean.'
printf '%s\n' 'PASS: all three teardown-verifier arms completed and the test volume was removed.'
