#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOCK_DIR="$ROOT/.down.lock"
STARTED_SECONDS=$SECONDS
CURRENT_STAGE="preflight"
LOCK_HELD=false

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
  exit 124
}

fail_stage() {
  local message="$1"
  printf 'ERROR: %s failed during %s after %s: %s\n' \
    "$CURRENT_STAGE" "$CURRENT_STAGE" "$(elapsed)" "$message" >&2
  printf '%s\n' 'Resolve the reported condition, then retry make down from stage one.' >&2
}

stage() {
  CURRENT_STAGE="$2"
  printf '==> [%s/8] %s\n' "$1" "$2"
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
  if ! argocd app set root --sync-policy none; then
    fail_stage 'could not disable root application auto-sync'
    exit 1
  fi
else
  printf '%s\n' '    skipped: 30-gitops state is confirmed absent'
fi

for item in \
  '2|drain Ingresses|sh/drain-ingress.sh' \
  '3|drain Karpenter NodePools|sh/drain-nodes.sh' \
  '4|drain PVCs|sh/drain-pvcs.sh'; do
  IFS='|' read -r number name script <<< "$item"
  stage "$number" "$name"
  if [[ "$INFRA_STATE" == present || "$GITOPS_STATE" == present ]]; then
    if [[ ! -x "$script" ]]; then
      fail_stage 'no verified cluster drain is available for this present or uncertain cluster; no Terraform destroy was attempted'
      exit 1
    fi
    if ! bash "$script"; then
      fail_stage 'drain command did not prove its resource set absent; no Terraform destroy was attempted'
      exit 1
    fi
  else
    printf '%s\n' '    skipped: no cluster state is present'
  fi
done

for item in '5|30-gitops' '6|20-data' '7|10-infra'; do
  IFS='|' read -r number layer <<< "$item"
  stage "$number" "destroy $layer"
  if ! make -s _destroy-layer "LAYER=$layer"; then
    fail_stage "Make could not safely destroy $layer"
    exit 2
  fi
done

stage 8 verify
if make -s verify-teardown; then
  exit 0
else
  exit "$?"
fi