#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOCK_DIR="$ROOT/.down.lock"
STARTED_SECONDS=$SECONDS
LC_STARTED_SECONDS=$STARTED_SECONDS
export LC_STARTED_SECONDS
CURRENT_STAGE="preflight"
LOCK_HELD=false
STAGE_STARTED_SECONDS=()
STAGE_ELAPSED_SECONDS=()

elapsed() {
  printf '%ss' "$((SECONDS - STARTED_SECONDS))"
}

# shellcheck disable=SC2329
cleanup() {
  if [[ "$LOCK_HELD" == true ]]; then
    rm -rf "$LOCK_DIR"
    LOCK_HELD=false
  fi
}

# shellcheck disable=SC2329
on_signal() {
  local signal="$1"
  printf 'ERROR: teardown interrupted by %s during %s after %s.\n' \
    "$signal" "$CURRENT_STAGE" "$(elapsed)" >&2
  printf '%s\n' 'Safe next step: inspect the reported stage, resolve the blocking condition, then rerun make down from step one.' >&2
  exit 124
}

fail_stage() {
  local message="$1"
  printf 'ERROR: %s failed during %s after %s: %s\n' \
    "$CURRENT_STAGE" "$CURRENT_STAGE" "$(elapsed)" "$message" >&2
  printf '%s\n' 'Resolve the reported condition, then retry make down from stage one.' >&2
}

stage() {
  local number="$1"
  CURRENT_STAGE="$2"
  STAGE_STARTED_SECONDS[number]=$SECONDS
  printf '==> [%s/8] %s\n' "$number" "$2"
}

finish_stage() {
  local number="$1"
  STAGE_ELAPSED_SECONDS[number]=$((SECONDS - STAGE_STARTED_SECONDS[number]))
}

report_successful_timing() {
  local number
  local stages=()
  for number in {1..8}; do
    stages+=("stage_${number}=${STAGE_ELAPSED_SECONDS[$number]}s")
  done
  printf 'Successful teardown timing: total=%s verifier_exit=0 %s\n' \
    "$(elapsed)" "${stages[*]}"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf 'ERROR: another teardown holds %s; no lifecycle action was started.\n' "$LOCK_DIR" >&2
  exit 1
fi
LOCK_HELD=true
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

if make -s doctor; then
  :
else
  doctor_rc=$?
  printf 'ERROR: teardown preflight failed after %s; no lifecycle action was started.\n' "$(elapsed)" >&2
  exit "$doctor_rc"
fi

INFRA_STATE=""
GITOPS_STATE=""
for layer in 10-infra 20-data 30-gitops; do
  if ! state="$(DOWN_PID=$$ make -s _layer-state "LAYER=$layer")"; then
    printf 'ERROR: state for %s is unknown; refusing teardown before any lifecycle action.\n' "$layer" >&2
    exit 2
  fi
  case "$state" in
    present|absent)
      case "$layer" in
        10-infra) INFRA_STATE="$state" ;;
        20-data) : ;;
        30-gitops) GITOPS_STATE="$state" ;;
      esac
      ;;
    *) printf 'ERROR: state for %s returned unexpected value %q; refusing teardown.\n' "$layer" "$state" >&2; exit 2 ;;
  esac
done

stage 1 'disable Argo auto-sync'
if [[ "$GITOPS_STATE" == present ]]; then
  if ! command -v argocd >/dev/null 2>&1; then
    fail_stage 'argocd CLI is unavailable'
    exit 1
  fi
  if app_json="$(argocd app get root --output json 2>&1)"; then
    if ! jq -e 'type == "object" and .metadata.name == "root"' <<< "$app_json" >/dev/null 2>&1; then
      fail_stage "argocd returned malformed root application data: $app_json"
      exit 1
    fi
  else
    argocd_error="$app_json"
    if [[ "$argocd_error" == *NotFound* && "$argocd_error" == *root* ]]; then
      printf '%s\n' '    skipped: root application is confirmed absent'
      app_json=""
    else
      fail_stage "could not determine whether root application exists: $argocd_error"
      exit 1
    fi
  fi
  if [[ -n "$app_json" ]]; then
    if ! argocd app set root --sync-policy none; then
      fail_stage 'could not disable root application auto-sync'
      exit 1
    fi
  fi
else
  printf '%s\n' '    skipped: 30-gitops state is confirmed absent'
fi
finish_stage 1

for item in \
  '2|drain Ingresses|sh/drain-ingress.sh' \
  '3|drain Karpenter NodePools|sh/drain-nodes.sh' \
  '4|drain PVCs|sh/drain-pvcs.sh'; do
  IFS='|' read -r number name script <<< "$item"
  stage "$number" "$name"
  if [[ "$INFRA_STATE" == present || "$GITOPS_STATE" == present ]]; then
    if [[ ! -f "$script" ]]; then
      fail_stage 'no verified cluster drain is available for this present or uncertain cluster; no Terraform destroy was attempted'
      exit 1
    fi
    # shellcheck disable=SC1090
    if ! ( source "$script" ); then
      fail_stage 'drain command did not prove its resource set absent; no Terraform destroy was attempted'
      exit 1
    fi
  else
    printf '%s\n' '    skipped: no cluster state is present'
  fi
  finish_stage "$number"
done

for item in '5|30-gitops' '6|20-data' '7|10-infra'; do
  IFS='|' read -r number layer <<< "$item"
  stage "$number" "destroy $layer"
  if ! make -s _destroy-layer "LAYER=$layer"; then
    fail_stage "Make could not safely destroy $layer"
    exit 2
  fi
  finish_stage "$number"
done

stage 8 verify
if make -s verify-teardown; then
  finish_stage 8
  report_successful_timing
  exit 0
else
  verify_rc=$?
  exit "$verify_rc"
fi