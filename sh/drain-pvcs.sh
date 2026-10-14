#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/sh/lifecycle-common.sh"

readonly REMEDIATION='restore EKS API access and delete the PVC first, then inspect each listed volume attachment/consumer state before any explicit operator cleanup.'
readonly PVC_NAME_TAG='kubernetes.io/created-for/pvc/name'
readonly PVC_NAMESPACE_TAG='kubernetes.io/created-for/pvc/namespace'

lc_init 'drain PVCs' 'PVC-owned EBS volumes'

volume_snapshot() {
  local response
  local cluster_tag="kubernetes.io/cluster/${LC_CLUSTER_NAME}"
  if ! lc_aws_json ec2 describe-volumes --filters \
    "Name=tag:$cluster_tag,Values=owned" \
    "Name=tag-key,Values=$PVC_NAME_TAG" \
    "Name=tag-key,Values=$PVC_NAMESPACE_TAG"; then
    LC_LAST_AWS_STATE='EC2 describe-volumes error'
    return 1
  fi
  response="$LC_AWS_OUTPUT"
  if ! jq -e --arg cluster_tag "$cluster_tag" --arg name_tag "$PVC_NAME_TAG" \
    --arg namespace_tag "$PVC_NAMESPACE_TAG" \
    'type == "object" and (.Volumes | type == "array") and all(.Volumes[]; (.VolumeId | type == "string") and (.State | type == "string") and (.Tags | type == "array") and any(.Tags[]; .Key == $cluster_tag and .Value == "owned") and any(.Tags[]; .Key == $name_tag and (.Value | type == "string")) and any(.Tags[]; .Key == $namespace_tag and (.Value | type == "string")) and ((.Attachments // []) | type == "array"))' \
    <<< "$response" >/dev/null 2>&1; then
    LC_AWS_ERROR="malformed or unowned PVC volume response: ${response}"
    LC_LAST_AWS_STATE='malformed EC2 volume response'
    return 1
  fi
  LC_RESIDUAL_IDS="$(jq -r '[.Volumes[] | "\(.VolumeId) [\(.State); attachments=\([.Attachments[]?.InstanceId] | join(","))]"] | .[]' <<< "$response")"
  LC_LAST_AWS_STATE="PVC-owned volumes=$(printf '%s' "$LC_RESIDUAL_IDS" | grep -c . || true)"
  return 0
}

if ! volume_snapshot; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if [[ "$LC_CLUSTER_STATE" == UNKNOWN ]]; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if lc_aws_only_state; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf 'drain PVCs complete: AWS confirms no tagged project PVC volumes (EKS %s).\n' "$LC_CLUSTER_STATE"
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_CLUSTER_ERROR"
  exit 1
fi

if ! lc_probe_kubernetes_api; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf '%s\n' 'drain PVCs complete: AWS confirms no tagged project PVC volumes; Kubernetes API unavailable but no residuals remain.'
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_KUBE_ERROR"
  exit 1
fi

DELETE_ERROR=""
if ! lc_kubectl delete pvc --all --all-namespaces --ignore-not-found --wait=false --request-timeout=20s; then
  DELETE_ERROR="$LC_KUBE_ERROR"
fi
if [[ -n "$DELETE_ERROR" ]]; then
  if ! volume_snapshot; then
    lc_fail "$REMEDIATION" "$LC_AWS_ERROR; ${DELETE_ERROR}"
    exit 1
  fi
  if [[ -n "$LC_RESIDUAL_IDS" ]]; then
    lc_fail "$REMEDIATION" "$DELETE_ERROR"
    exit 1
  fi
  printf '%s\n' 'drain PVCs complete: AWS confirms no tagged project PVC volumes.'
  exit 0
fi

for ((attempt = 1; attempt <= LC_POLL_ATTEMPTS; attempt++)); do
  if ! volume_snapshot; then
    lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
    exit 1
  fi
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf '%s\n' 'drain PVCs complete: AWS confirms no tagged project PVC volumes.'
    exit 0
  fi
  if ((attempt < LC_POLL_ATTEMPTS)); then
    sleep "$LC_POLL_INTERVAL"
  fi
done

lc_fail "$REMEDIATION"
exit 1