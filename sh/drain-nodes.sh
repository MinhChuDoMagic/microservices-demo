#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/sh/lifecycle-common.sh"

readonly REMEDIATION='restore EKS API access and drain the named NodePool/instances, or inspect the listed tagged instances and any known untagged Karpenter instances before explicit operator cleanup.'

lc_init 'drain Karpenter NodePools' 'Karpenter EC2 instances'

instance_snapshot() {
  local response
  if ! lc_aws_json ec2 describe-instances --filters \
    "Name=tag:karpenter.sh/discovery,Values=$LC_CLUSTER_NAME" \
    'Name=tag:karpenter.sh/nodepool,Values=*'; then
    LC_LAST_AWS_STATE='EC2 describe-instances error'
    return 1
  fi
  response="$LC_AWS_OUTPUT"
  if ! jq -e 'type == "object" and (.Reservations | type == "array") and all(.Reservations[]; (.Instances | type == "array") and all(.Instances[]; (.InstanceId | type == "string") and (.State.Name | type == "string")))' \
    <<< "$response" >/dev/null 2>&1; then
    LC_AWS_ERROR="malformed EC2 describe-instances response: ${response}"
    LC_LAST_AWS_STATE='malformed EC2 instance response'
    return 1
  fi
  LC_RESIDUAL_IDS="$(jq -r '[.Reservations[].Instances[] | "\(.InstanceId) [\(.State.Name)]"] | .[]' <<< "$response")"
  LC_LAST_AWS_STATE="Karpenter instances=$(printf '%s' "$LC_RESIDUAL_IDS" | grep -c . || true)"
  return 0
}

if ! instance_snapshot; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if [[ "$LC_CLUSTER_STATE" == UNKNOWN ]]; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if lc_aws_only_state; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf 'drain Karpenter NodePools complete: AWS confirms no tagged project Karpenter instances (EKS %s).\n' "$LC_CLUSTER_STATE"
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_CLUSTER_ERROR"
  exit 1
fi

if ! lc_probe_kubernetes_api; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf '%s\n' 'drain Karpenter NodePools complete: AWS confirms no tagged project Karpenter instances; Kubernetes API unavailable but no residuals remain.'
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_KUBE_ERROR"
  exit 1
fi

DELETE_ERROR=""
if ! lc_kubectl delete nodepools.karpenter.sh --all --ignore-not-found --wait=false --request-timeout=20s; then
  DELETE_ERROR="$LC_KUBE_ERROR"
fi
if [[ -n "$DELETE_ERROR" ]]; then
  if ! instance_snapshot; then
    lc_fail "$REMEDIATION" "$LC_AWS_ERROR; ${DELETE_ERROR}"
    exit 1
  fi
  if [[ -n "$LC_RESIDUAL_IDS" ]]; then
    lc_fail "$REMEDIATION" "$DELETE_ERROR"
    exit 1
  fi
  printf '%s\n' 'drain Karpenter NodePools complete: AWS confirms no tagged project Karpenter instances.'
  exit 0
fi

for ((attempt = 1; attempt <= LC_POLL_ATTEMPTS; attempt++)); do
  if ! instance_snapshot; then
    lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
    exit 1
  fi
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf '%s\n' 'drain Karpenter NodePools complete: AWS confirms no tagged project Karpenter instances.'
    exit 0
  fi
  if ((attempt < LC_POLL_ATTEMPTS)); then
    sleep "$LC_POLL_INTERVAL"
  fi
done

lc_fail "$REMEDIATION"
exit 1