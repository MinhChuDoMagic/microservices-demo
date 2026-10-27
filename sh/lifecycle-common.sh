#!/usr/bin/env bash

LC_AWS_OUTPUT=""
LC_AWS_ERROR=""
readonly LC_AWS_ATTEMPTS=3
readonly LC_POLL_ATTEMPTS=12
readonly LC_POLL_INTERVAL=2
readonly LC_DEADLINE_SECONDS=1500
export LC_POLL_ATTEMPTS LC_POLL_INTERVAL
LC_STAGE=""
LC_RESOURCE_TYPE=""
LC_REGION=""
LC_CLUSTER_NAME="microservices-demo"
LC_CLUSTER_STATE="UNKNOWN"
LC_CLUSTER_ERROR=""
LC_CLUSTER_JSON=""
LC_VPC_ID=""
export LC_KUBE_ERROR=""
LC_LAST_AWS_STATE="not queried"
LC_RESIDUAL_IDS=""
LC_STARTED_SECONDS="${LC_STARTED_SECONDS:-$SECONDS}"

lc_monotonic_seconds() {
  printf '%s\n' "$SECONDS"
}

lc_elapsed() {
  local now
  now="$(lc_monotonic_seconds)"
  printf '%ss' "$((now - LC_STARTED_SECONDS))"
}

lc_deadline_expired() {
  local now
  now="$(lc_monotonic_seconds)"
  ((now - LC_STARTED_SECONDS >= LC_DEADLINE_SECONDS))
}

lc_retryable_aws_error() {
  case "$1" in
    *Throttl*|*RequestLimitExceeded*|*ServiceUnavailable*|*InternalError*|\
    *InternalFailure*|*EndpointConnectionError*|*ConnectionTimedOut*|\
    *ReadTimeout*|*PriorRequestNotComplete*|*"Could not connect to the endpoint URL"*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

lc_aws_json() {
  local attempt
  local exit_code
  local output
  local service="$1"
  local operation="$2"
  shift 2

  for ((attempt = 1; attempt <= LC_AWS_ATTEMPTS; attempt++)); do
    if lc_deadline_expired; then
      LC_AWS_ERROR="shared ${LC_DEADLINE_SECONDS}-second teardown deadline reached before aws ${service} ${operation}"
      return 1
    fi
    if output="$(AWS_MAX_ATTEMPTS=1 aws "$service" "$operation" "$@" \
      --region "$LC_REGION" --output json --cli-connect-timeout 5 --cli-read-timeout 15 2>&1)"; then
      LC_AWS_OUTPUT="$output"
      LC_AWS_ERROR=""
      return 0
    else
      exit_code=$?
      LC_AWS_ERROR="$output"
      LC_AWS_OUTPUT=""
    fi

    if ((attempt < LC_AWS_ATTEMPTS)) && lc_retryable_aws_error "$LC_AWS_ERROR"; then
      if lc_deadline_expired; then
        LC_AWS_ERROR="shared ${LC_DEADLINE_SECONDS}-second teardown deadline reached while retrying aws ${service} ${operation}"
        return 1
      fi
      printf 'retrying transient AWS error (%s/%s): %s\n' \
        "$attempt" "$LC_AWS_ATTEMPTS" "$LC_AWS_ERROR" >&2
      sleep 1
    else
      LC_AWS_ERROR="aws ${service} ${operation} failed (exit ${exit_code}): ${LC_AWS_ERROR}"
      return 1
    fi
  done
  return 1
}

lc_init() {
  LC_STAGE="$1"
  LC_RESOURCE_TYPE="$2"
  LC_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

  if ! lc_aws_json eks describe-cluster --name "$LC_CLUSTER_NAME"; then
    if [[ "$LC_AWS_ERROR" == *ResourceNotFoundException* ]]; then
      LC_CLUSTER_STATE="ABSENT"
      LC_CLUSTER_ERROR=""
      LC_CLUSTER_JSON=""
    else
      LC_CLUSTER_STATE="UNKNOWN"
      LC_CLUSTER_ERROR="$LC_AWS_ERROR"
    fi
    return 0
  fi

  LC_CLUSTER_JSON="$LC_AWS_OUTPUT"
  if ! jq -e 'type == "object" and (.cluster | type == "object") and (.cluster.status | type == "string")' \
    <<< "$LC_CLUSTER_JSON" >/dev/null 2>&1; then
    LC_CLUSTER_STATE="UNKNOWN"
    LC_CLUSTER_ERROR="malformed aws eks describe-cluster response: ${LC_CLUSTER_JSON}"
    return 0
  fi

  case "$(jq -r '.cluster.status' <<< "$LC_CLUSTER_JSON")" in
    CREATING) LC_CLUSTER_STATE="CREATING" ;;
    FAILED) LC_CLUSTER_STATE="FAILED" ;;
    ACTIVE) LC_CLUSTER_STATE="ACTIVE" ;;
    DEGRADED|DELETING|PENDING|UPDATING) LC_CLUSTER_STATE="DEGRADED" ;;
    *)
      LC_CLUSTER_STATE="UNKNOWN"
      LC_CLUSTER_ERROR="unsupported EKS cluster status: $(jq -r '.cluster.status' <<< "$LC_CLUSTER_JSON")"
      ;;
  esac
  LC_VPC_ID="$(jq -r '.cluster.resourcesVpcConfig.vpcId // empty' <<< "$LC_CLUSTER_JSON")"
}

lc_require_vpc_id() {
  if [[ -n "$LC_VPC_ID" ]]; then
    return 0
  fi
  if LC_VPC_ID="$(terraform -chdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../layers/10-infra" && pwd)" output -raw vpc_id 2>&1)" \
    && [[ "$LC_VPC_ID" =~ ^vpc-[[:alnum:]]+$ ]]; then
    return 0
  fi
  LC_AWS_ERROR="could not determine the L1 VPC ID from EKS or Terraform output: ${LC_VPC_ID}"
  LC_VPC_ID=""
  return 1
}

lc_kubectl() {
  local output
  if output="$(kubectl "$@" 2>&1)"; then
    LC_KUBE_ERROR=""
    return 0
  fi
  LC_KUBE_ERROR="$output"
  return 1
}

lc_probe_kubernetes_api() {
  if lc_kubectl get --raw=/readyz --request-timeout=10s; then
    return 0
  fi
  return 1
}

lc_fail() {
  local remediation="$1"
  local origin="${2:-}"
  printf 'ERROR: stage=%s EKS_state=%s resource_type=%s residual_ids=%s last_observed=%s elapsed=%s\n' \
    "$LC_STAGE" "$LC_CLUSTER_STATE" "$LC_RESOURCE_TYPE" \
    "${LC_RESIDUAL_IDS:-none}" "$LC_LAST_AWS_STATE" "$(lc_elapsed)" >&2
  if [[ -n "$origin" ]]; then
    printf 'Originating error: %s\n' "$origin" >&2
  fi
  if [[ -n "$LC_CLUSTER_ERROR" ]]; then
    printf 'EKS state error: %s\n' "$LC_CLUSTER_ERROR" >&2
  fi
  printf 'Safe next step: %s\n' "$remediation" >&2
  printf '%s\n' 'No Terraform destroy was attempted. After remediation, rerun make down from step one.' >&2
}

lc_aws_only_state() {
  case "$LC_CLUSTER_STATE" in
    ABSENT|CREATING|FAILED) return 0 ;;
    *) return 1 ;;
  esac
}