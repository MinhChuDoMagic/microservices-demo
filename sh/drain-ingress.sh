#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/sh/lifecycle-common.sh"

readonly REMEDIATION='restore EKS API access and complete Ingress/controller cleanup, or inspect the listed ELBv2 resources and explicitly handle untagged resources before retrying.'

lc_init 'drain Ingresses' 'ELBv2 load balancers and target groups'
if ! lc_require_vpc_id; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

ingress_snapshot() {
  local load_balancers
  local target_groups

  if ! lc_aws_json elbv2 describe-load-balancers; then
    LC_LAST_AWS_STATE='ELBv2 describe-load-balancers error'
    return 1
  fi
  load_balancers="$LC_AWS_OUTPUT"
  if ! jq -e 'type == "object" and (.LoadBalancers | type == "array") and all(.LoadBalancers[]; (.LoadBalancerArn | type == "string") and (.VpcId | type == "string"))' \
    <<< "$load_balancers" >/dev/null 2>&1; then
    LC_AWS_ERROR="malformed ELBv2 load balancer response: ${load_balancers}"
    LC_LAST_AWS_STATE='malformed ELBv2 load balancer response'
    return 1
  fi
  if ! lc_aws_json elbv2 describe-target-groups; then
    LC_LAST_AWS_STATE='ELBv2 describe-target-groups error'
    return 1
  fi
  target_groups="$LC_AWS_OUTPUT"
  if ! jq -e 'type == "object" and (.TargetGroups | type == "array") and all(.TargetGroups[]; (.TargetGroupArn | type == "string"))' \
    <<< "$target_groups" >/dev/null 2>&1; then
    LC_AWS_ERROR="malformed ELBv2 target group response: ${target_groups}"
    LC_LAST_AWS_STATE='malformed ELBv2 target group response'
    return 1
  fi

  LC_RESIDUAL_IDS="$(jq -r --arg vpc "$LC_VPC_ID" \
    '[.LoadBalancers[] | select(.VpcId == $vpc) | "load-balancer:\(.LoadBalancerArn) [\(.State.Code // "unknown")]"] | .[]' \
    <<< "$load_balancers")"
  local target_group_ids
  target_group_ids="$(jq -r --arg vpc "$LC_VPC_ID" \
    '[.TargetGroups[] | select(.VpcId == $vpc) | "target-group:\(.TargetGroupArn)"] | .[]' \
    <<< "$target_groups")"
  if [[ -n "$target_group_ids" ]]; then
    LC_RESIDUAL_IDS="$(printf '%s\n%s' "$LC_RESIDUAL_IDS" "$target_group_ids" | sed '/^$/d')"
  fi
  LC_LAST_AWS_STATE="load_balancers=$(printf '%s' "$LC_RESIDUAL_IDS" | grep -c '^load-balancer:' || true), target_groups=$(printf '%s' "$LC_RESIDUAL_IDS" | grep -c '^target-group:' || true) in $LC_VPC_ID"
  return 0
}

if ! ingress_snapshot; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if [[ "$LC_CLUSTER_STATE" == UNKNOWN ]]; then
  lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
  exit 1
fi

if lc_aws_only_state; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf 'drain Ingresses complete: AWS confirms no load balancers or target groups in %s (EKS %s).\n' \
      "$LC_VPC_ID" "$LC_CLUSTER_STATE"
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_CLUSTER_ERROR"
  exit 1
fi

if ! lc_probe_kubernetes_api; then
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf 'drain Ingresses complete: AWS confirms no load balancers or target groups in %s; Kubernetes API unavailable but no residuals remain.\n' "$LC_VPC_ID"
    exit 0
  fi
  lc_fail "$REMEDIATION" "$LC_KUBE_ERROR"
  exit 1
fi

DELETE_ERROR=""
if ! lc_kubectl delete ingress --all --all-namespaces --ignore-not-found --wait=false --request-timeout=20s; then
  DELETE_ERROR="$LC_KUBE_ERROR"
  if ! ingress_snapshot; then
    lc_fail "$REMEDIATION" "$LC_AWS_ERROR; ${DELETE_ERROR}"
    exit 1
  fi
  if [[ -n "$LC_RESIDUAL_IDS" ]]; then
    lc_fail "$REMEDIATION" "$DELETE_ERROR"
    exit 1
  fi
fi
if ! lc_kubectl delete service --all --all-namespaces --field-selector spec.type=LoadBalancer \
  --ignore-not-found --wait=false --request-timeout=20s; then
  if [[ -n "$DELETE_ERROR" ]]; then
    DELETE_ERROR="${DELETE_ERROR}; ${LC_KUBE_ERROR}"
  else
    DELETE_ERROR="$LC_KUBE_ERROR"
  fi
fi

for ((attempt = 1; attempt <= LC_POLL_ATTEMPTS; attempt++)); do
  if ! ingress_snapshot; then
    if [[ -n "$DELETE_ERROR" ]]; then
      lc_fail "$REMEDIATION" "${LC_AWS_ERROR}; ${DELETE_ERROR}"
    else
      lc_fail "$REMEDIATION" "$LC_AWS_ERROR"
    fi
    exit 1
  fi
  if [[ -z "$LC_RESIDUAL_IDS" ]]; then
    printf 'drain Ingresses complete: AWS confirms no load balancers or target groups in %s.\n' "$LC_VPC_ID"
    exit 0
  fi
  if [[ -n "$DELETE_ERROR" ]]; then
    lc_fail "$REMEDIATION" "$DELETE_ERROR"
    exit 1
  fi
  if ((attempt < LC_POLL_ATTEMPTS)); then
    sleep "$LC_POLL_INTERVAL"
  fi
done

lc_fail "$REMEDIATION" "$DELETE_ERROR"
exit 1