#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
LAYER_DIR="$ROOT/layers/10-infra"
readonly LAYER_DIR
READY_TIMEOUT_SECONDS="${EKS_READY_TIMEOUT_SECONDS:-3600}"
POLL_INTERVAL_SECONDS="${EKS_POLL_INTERVAL_SECONDS:-30}"

fail() {
  local exit_code="$1"
  local stage="$2"
  local next_step="$3"
  printf 'ERROR: %s failed. %s\nNext: %s\n' "$stage" "$4" "$next_step" >&2
  exit "$exit_code"
}

if [[ -z "${OPERATOR_CIDR:-}" ]]; then
  fail 2 'operator CIDR preflight' 'OPERATOR_CIDR is required.' 'Set OPERATOR_CIDR to the trusted public IPv4 CIDR for this workstation, then rerun make up.'
fi

if ! command -v curl >/dev/null 2>&1; then
  fail 2 'operator CIDR preflight' 'curl is required to determine the current public IPv4 address.' 'Install curl and rerun make up.'
fi

if ! PUBLIC_IP="$(curl --fail --silent --show-error https://checkip.amazonaws.com)"; then
  fail 2 'operator CIDR preflight' 'Could not determine the current public IPv4 address.' 'Restore network access to checkip.amazonaws.com and rerun make up.'
fi

if ! python3 -c 'import ipaddress, sys; network = ipaddress.ip_network(sys.argv[1], strict=False); address = ipaddress.ip_address(sys.argv[2]); sys.exit(0 if network.version == 4 and address.version == 4 and network.prefixlen != 0 and address in network else 1)' "$OPERATOR_CIDR" "$PUBLIC_IP"; then
  fail 2 'operator CIDR preflight' "${OPERATOR_CIDR} is invalid, world-open, or does not contain the current public IP ${PUBLIC_IP}." 'Set OPERATOR_CIDR to the current trusted public IPv4 CIDR, then rerun make up.'
fi

cd "$ROOT" || fail 2 'repository setup' 'Could not enter the repository root.' 'Rerun make up from a valid checkout.'

if make --no-print-directory -s _init-layer LAYER=10-infra; then
  :
else
  rc=$?
  fail "$rc" 'L1 Terraform init' 'Backend initialization failed; no apply was attempted.' 'Inspect the Terraform/backend error, correct it, then rerun make up.'
fi

if make --no-print-directory -s _apply-layer LAYER=10-infra OPERATOR_CIDR="$OPERATOR_CIDR"; then
  :
else
  rc=$?
  fail "$rc" 'L1 Terraform apply' 'Partial resources and state are preserved; no retry or destroy was attempted.' 'Inspect the Terraform error and partial state, remediate it, then explicitly rerun make up.'
fi

if CLUSTER_NAME="$(terraform -chdir="$LAYER_DIR" output -raw cluster_name)"; then
  :
else
  rc=$?
  fail "$rc" 'EKS readiness setup' 'Terraform did not return the cluster name.' 'Inspect the L1 Terraform outputs and state before rerunning make up.'
fi

if NODE_GROUP_NAME="$(terraform -chdir="$LAYER_DIR" output -raw system_node_group_name)"; then
  :
else
  rc=$?
  fail "$rc" 'EKS readiness setup' 'Terraform did not return the system node group name.' 'Inspect the L1 Terraform outputs and state before rerunning make up.'
fi

wait_for_active() {
  local kind="$1"
  local resource="$2"
  local started="$SECONDS"
  local response status issues

  while :; do
    case "$kind" in
      cluster)
        if response="$(aws eks describe-cluster --name "$CLUSTER_NAME" --output json)"; then
          status="$(jq -r '.cluster.status // empty' <<< "$response")"
          issues="$(jq -r '(.cluster.health.issues // []) | length' <<< "$response")"
        else
          return 2
        fi
        ;;
      nodegroup)
        if response="$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODE_GROUP_NAME" --output json)"; then
          status="$(jq -r '.nodegroup.status // empty' <<< "$response")"
          issues="$(jq -r '(.nodegroup.health.issues // []) | length' <<< "$response")"
        else
          return 2
        fi
        ;;
      addon)
        if response="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$resource" --output json)"; then
          status="$(jq -r '.addon.status // empty' <<< "$response")"
          issues="$(jq -r '(.addon.health.issues // []) | length' <<< "$response")"
        else
          return 2
        fi
        ;;
      *) return 2 ;;
    esac

    if [[ "$status" == ACTIVE ]]; then
      if [[ "$issues" != 0 ]]; then
        printf '%s has %s reported health issue(s).\n' "$kind $resource" "$issues" >&2
        return 1
      fi
      printf '[ready] %s %s\n' "$kind" "$resource"
      return 0
    fi

    case "$status" in
      FAILED|DEGRADED|CREATE_FAILED|DELETE_FAILED|UPDATE_FAILED|DELETING)
        printf '%s entered terminal status %s.\n' "$kind $resource" "${status:-unknown}" >&2
        return 1
        ;;
    esac

    if (( SECONDS - started >= READY_TIMEOUT_SECONDS )); then
      printf '%s did not reach ACTIVE before the %s-second readiness limit (last status: %s).\n' \
        "$kind $resource" "$READY_TIMEOUT_SECONDS" "${status:-unknown}" >&2
      return 1
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
}

STARTED_SECONDS="$SECONDS"
if wait_for_active cluster "$CLUSTER_NAME"; then
  :
else
  rc=$?
  fail "$rc" 'EKS cluster readiness' 'Cluster status or health did not reach ACTIVE.' 'Inspect the EKS cluster status and events; remediate the cause, then explicitly rerun make up.'
fi

if wait_for_active nodegroup "$NODE_GROUP_NAME"; then
  :
else
  rc=$?
  fail "$rc" 'EKS system node group readiness' 'Node group status or health did not reach ACTIVE.' 'Inspect the EKS node group status, health issues, and EC2 capacity; remediate the cause, then explicitly rerun make up.'
fi

for ADDON in vpc-cni kube-proxy coredns eks-pod-identity-agent; do
  if wait_for_active addon "$ADDON"; then
    :
  else
    rc=$?
    fail "$rc" "EKS add-on readiness ($ADDON)" 'Add-on status or health did not reach ACTIVE.' 'Inspect the add-on status and health issues; remediate the cause, then explicitly rerun make up.'
  fi
done

ELAPSED_SECONDS=$((SECONDS - STARTED_SECONDS))
printf 'make up complete: cluster %s and its system node group and four required add-ons are healthy (%ss).\n' \
  "$CLUSTER_NAME" "$ELAPSED_SECONDS"