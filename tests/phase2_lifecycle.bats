#!/usr/bin/env bats

load 'helpers/load'

setup() {
  unset STUB_AWS_SEQUENCE_SCENARIO STUB_AWS_SEQUENCE_FIXTURE
  real_make="$(command -v make)"
  test_bin="$BATS_TEST_TMPDIR/bin"
  test_root="$BATS_TEST_TMPDIR/repo"
  call_log="$BATS_TEST_TMPDIR/calls.log"
  backend_hcl="$BATS_TEST_TMPDIR/backend.hcl"
  timeout_log="$BATS_TEST_TMPDIR/timeout.log"
  mkdir -p "$test_bin" "$test_root/sh" "$test_root/layers/10-infra"
  cp "$BATS_TEST_DIRNAME/../Makefile" "$test_root/Makefile"
  cp "$BATS_TEST_DIRNAME/../sh/down.sh" "$test_root/sh/down.sh" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../sh/up.sh" "$test_root/sh/up.sh" 2>/dev/null || true
  printf '%s\n' 'bucket = "test-state-bucket"' > "$backend_hcl"
  : > "$call_log"
  : > "$timeout_log"

  cat > "$test_bin/timeout" <<'TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_TIMEOUT_LOG"
printf 'timeout:%s\n' "$*" >> "$TEST_CALL_LOG"
[[ "$1" == '--signal=TERM' && "$2" == '--kill-after=5s' && "$3" == '900s' ]]
shift 3
exec "$@"
TIMEOUT
  chmod +x "$test_bin/timeout"

  cat > "$test_bin/gtimeout" <<'GTIMEOUT'
#!/usr/bin/env bash
exit 0
GTIMEOUT
  chmod +x "$test_bin/gtimeout"

  cat > "$test_bin/make" <<'MAKE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$TEST_CALL_LOG"
target=""
layer=""
for argument in "$@"; do
  case "$argument" in
    doctor|_layer-state|_init-layer|_apply-layer|_destroy-layer|verify-teardown) target="$argument" ;;
    LAYER=*) layer="${argument#LAYER=}" ;;
  esac
done
case "$target" in
    doctor)
      ;;
  _init-layer)
    [[ "$layer" == 10-infra ]] || exit 2
    ;;
  _apply-layer)
    [[ "$layer" == 10-infra ]] || exit 2
    if [[ "${TEST_APPLY_EXIT:-0}" -ne 0 ]]; then
      printf '%s\n' 'test apply failure' >&2
      exit "$TEST_APPLY_EXIT"
    fi
    ;;
  _layer-state)
    if [[ "${TEST_BLOCK_STATE:-false}" == true && "$layer" == 10-infra ]]; then
      : > "$TEST_ENTERED"
      while [[ ! -e "$TEST_RELEASE" ]]; do :; done
    fi
    variable="TEST_STATE_${layer//-/_}"
    state="${!variable:-absent}"
    if [[ "${TEST_TERMINATE_PARENT:-false}" == true && "$layer" == 10-infra ]]; then
      kill -TERM "$DOWN_PID"
      exit 0
    fi
    if [[ "$state" == unknown ]]; then
      printf '%s\n' 'state lookup failed' >&2
      exit 2
    fi
    printf '%s\n' "$state"
    ;;
  _destroy-layer)
    printf 'destroy:%s\n' "$layer" >> "$TEST_CALL_LOG"
    ;;
  verify-teardown)
    printf '%s\n' 'test verifier output'
    exit "${TEST_VERIFY_EXIT:-0}"
    ;;
  *)
    printf 'unexpected make invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
MAKE
  chmod +x "$test_bin/make"

  cat > "$test_bin/aws" <<'AWS'
#!/usr/bin/env bash
set -u
  printf '%s\n' "$*" >> "$TEST_CALL_LOG"
  if [[ "${1:-}" == --version ]]; then
    printf '%s\n' 'aws-cli/2.37.0 Python/3.13'
    exit 0
  fi
  case "${1:-}:${2:-}" in
    sts:get-caller-identity)
      printf '%s\n' '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/test"}'
      exit 0
      ;;
    configure:get)
      printf '%s\n' 'us-east-1'
      exit 0
      ;;
    eks:describe-cluster)
      if [[ -n "${TEST_CLUSTER_ERROR:-}" ]]; then
        printf '%s\n' "$TEST_CLUSTER_ERROR" >&2
        exit 255
      fi
      printf '{"cluster":{"status":"%s","resourcesVpcConfig":{"vpcId":"%s"}}}\n' \
        "${TEST_CLUSTER_STATUS:-ACTIVE}" "${TEST_VPC_ID:-vpc-12345678}"
      exit 0
      ;;
    eks:describe-nodegroup)
      printf '{"nodegroup":{"status":"%s","scalingConfig":{"desiredSize":2},"health":{"issues":[]}}}\n' "${TEST_NODEGROUP_STATUS:-ACTIVE}"
      exit 0
      ;;
    eks:describe-addon)
      printf '{"addon":{"status":"%s"}}\n' "${TEST_ADDON_STATUS:-ACTIVE}"
      exit 0
      ;;
    elbv2:describe-load-balancers)
      call_number="$(grep -c '^elbv2 describe-load-balancers ' "$TEST_CALL_LOG" || true)"
      response_name="TEST_LB_RESPONSE_${call_number}"
      response="${!response_name:-${TEST_LB_RESPONSE:-}}"
      [[ -n "$response" ]] || response='{"LoadBalancers":[]}'
      if [[ "${TEST_LB_TRANSIENT_ALWAYS:-false}" == true ]]; then
        printf '%s\n' 'An error occurred (ThrottlingException): test transient limit' >&2
        exit 255
      fi
      if [[ "${TEST_LB_TRANSIENT_ONCE:-false}" == true && "$call_number" -eq 1 ]]; then
        printf '%s\n' 'An error occurred (ThrottlingException): test transient limit' >&2
        exit 255
      fi
      if [[ -n "${TEST_LB_ERROR:-}" ]]; then
        printf '%s\n' "$TEST_LB_ERROR" >&2
        exit 255
      fi
      printf '%s\n' "$response"
      exit 0
      ;;
    elbv2:describe-target-groups)
      call_number="$(grep -c '^elbv2 describe-target-groups ' "$TEST_CALL_LOG" || true)"
      response_name="TEST_TG_RESPONSE_${call_number}"
      response="${!response_name:-${TEST_TG_RESPONSE:-}}"
      [[ -n "$response" ]] || response='{"TargetGroups":[]}'
      printf '%s\n' "$response"
      exit 0
      ;;
    ec2:describe-instances)
      call_number="$(grep -c '^ec2 describe-instances ' "$TEST_CALL_LOG" || true)"
      response_name="TEST_INSTANCE_RESPONSE_${call_number}"
      response="${!response_name:-${TEST_INSTANCE_RESPONSE:-}}"
      [[ -n "$response" ]] || response='{"Reservations":[]}'
      if [[ -n "${TEST_INSTANCE_ERROR:-}" ]]; then
        printf '%s\n' "$TEST_INSTANCE_ERROR" >&2
        exit 255
      fi
      printf '%s\n' "$response"
      exit 0
      ;;
    ec2:describe-volumes)
      call_number="$(grep -c '^ec2 describe-volumes ' "$TEST_CALL_LOG" || true)"
      response_name="TEST_VOLUME_RESPONSE_${call_number}"
      response="${!response_name:-${TEST_VOLUME_RESPONSE:-}}"
      [[ -n "$response" ]] || response='{"Volumes":[]}'
      if [[ -n "${TEST_VOLUME_ERROR:-}" ]]; then
        printf '%s\n' "$TEST_VOLUME_ERROR" >&2
        exit 255
      fi
      printf '%s\n' "$response"
      exit 0
      ;;
  esac
if [[ "${TEST_AWS_EXIT:-0}" -ne 0 ]]; then
  printf '%s\n' 'AccessDenied: test state lookup failure' >&2
  exit "$TEST_AWS_EXIT"
fi
printf '%s\n' "${TEST_AWS_RESPONSE:-}"
AWS
  chmod +x "$test_bin/aws"

  cat > "$test_bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "${TEST_PUBLIC_IP:-203.0.113.10}"
CURL
  chmod +x "$test_bin/curl"

  cat > "$test_bin/terraform" <<'TERRAFORM'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$TEST_CALL_LOG"
case "$*" in
    *'version -json'*) printf '%s\n' '{"terraform_version":"1.16.4"}' ;;
  *'output -raw vpc_id'*) printf '%s\n' 'vpc-12345678' ;;
  *'output -raw cluster_name'*) printf '%s\n' 'microservices-demo' ;;
  *'output -raw system_node_group_name'*) printf '%s\n' 'microservices-demo-system' ;;
  *' init '*) exit 0 ;;
  *' apply '*) exit "${TEST_APPLY_EXIT:-0}" ;;
  *) printf 'unexpected terraform invocation: %s\n' "$*" >&2; exit 64 ;;
esac
TERRAFORM
  chmod +x "$test_bin/terraform"

  cat > "$test_bin/cloud-nuke" <<'CLOUDNUKE'
#!/usr/bin/env bash
printf 'cloud-nuke %s\n' "$*" >> "$TEST_CALL_LOG"
CLOUDNUKE
  chmod +x "$test_bin/cloud-nuke"

  cat > "$test_bin/kubectl" <<'KUBECTL'
#!/usr/bin/env bash
  printf '%s\n' "$*" >> "$TEST_CALL_LOG"
  if [[ "${1:-}" == version ]]; then
    printf '{"clientVersion":{"gitVersion":"%s"}}\n' "${TEST_KUBECTL_VERSION:-v1.34.12}"
    exit 0
  fi
  if [[ "${TEST_KUBECTL_API_EXIT:-0}" -ne 0 ]]; then
    printf '%s\n' "${TEST_KUBECTL_ERROR:-The Kubernetes API is unreachable}" >&2
    exit "$TEST_KUBECTL_API_EXIT"
  fi
  if [[ "${1:-}" == delete && "${2:-}" == ingress && "${TEST_KUBECTL_INGRESS_DELETE_EXIT:-0}" -ne 0 ]]; then
    printf '%s\n' "${TEST_KUBECTL_INGRESS_DELETE_ERROR:-Forbidden: ingress deletion denied}" >&2
    exit "$TEST_KUBECTL_INGRESS_DELETE_EXIT"
  fi
  printf '%s\n' 'ok'
KUBECTL
  chmod +x "$test_bin/kubectl"

  cat > "$test_bin/argocd" <<'ARGOCD'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$TEST_CALL_LOG"
case "${1:-}:${2:-}" in
  app:get)
    if [[ "${TEST_ARGOCD_GET_EXIT:-0}" -ne 0 ]]; then
      printf '%s\n' "${TEST_ARGOCD_GET_ERROR:-test Argo CD error}" >&2
      exit "$TEST_ARGOCD_GET_EXIT"
    fi
    printf '%s\n' '{"metadata":{"name":"root"}}'
    ;;
  app:set)
    if [[ "${TEST_ARGOCD_SET_EXIT:-0}" -ne 0 ]]; then
      printf '%s\n' "${TEST_ARGOCD_SET_ERROR:-test Argo CD set error}" >&2
      exit "$TEST_ARGOCD_SET_EXIT"
    fi
    ;;
  *) exit 64 ;;
esac
ARGOCD
  chmod +x "$test_bin/argocd"

  export TEST_CALL_LOG="$call_log"
  export TEST_TIMEOUT_LOG="$timeout_log"
  export TEST_REAL_MAKE="$real_make"
  export TEST_BACKEND_HCL="$backend_hcl"
  export TEST_ENTERED="$BATS_TEST_TMPDIR/state-entered"
  export TEST_RELEASE="$BATS_TEST_TMPDIR/release-state"
  export TEST_STATE_10_infra=absent
  export TEST_STATE_20_data=absent
  export TEST_STATE_30_gitops=absent
  export TEST_PUBLIC_IP=203.0.113.10
  export PATH="$test_bin:$PATH"
}

teardown() {
  if [[ -n "${STUB_AWS_DIR:-}" ]]; then
    stub_aws_stop
  fi
}

run_layer_state() {
  run "$TEST_REAL_MAKE" -s "BACKEND_HCL=$TEST_BACKEND_HCL" \
    _layer-state LAYER=10-infra
}

prepare_doctor_root() {
  mkdir -p "$test_root/layers/00-bootstrap" "$test_root/layers/10-infra" \
    "$test_root/layers/20-data" "$test_root/layers/30-gitops"
  cp "$BATS_TEST_DIRNAME/../sh/doctor.sh" "$test_root/sh/doctor.sh"
  chmod +x "$test_root/sh/doctor.sh"
  printf '%s\n' '1.16.4' > "$test_root/.terraform-version"
  printf '%s\n' '123456789012' > "$test_root/.aws-account-id"
  printf '%s\n' \
    'alert_email = "test@example.com"' \
    'github_owner = "test-owner"' \
    'github_repo = "test-repo"' > "$test_root/layers/00-bootstrap/terraform.tfvars"
  for layer in 00-bootstrap 10-infra 20-data 30-gitops; do
    printf '%s\n' 'terraform {' '  required_version = "= 1.16.4"' '}' \
      > "$test_root/layers/$layer/versions.tf"
  done
  printf '%s\n' \
    'backend.hcl' \
    '.aws-account-id' \
    'terraform.tfstate' \
    '.teardown-report.json' \
    'layers/00-bootstrap/terraform.tfvars' > "$test_root/.gitignore"
  git -C "$test_root" init -q
  export AWS_REGION=us-east-1
}

prepare_doctor_path() {
  local deadline_tool="${1:-}"
  local doctor_path="$BATS_TEST_TMPDIR/doctor-path"
  local command_name
  mkdir -p "$doctor_path"
  for command_name in env bash dirname basename cut grep head sed sort tr wc git jq rm; do
    ln -s "$(command -v "$command_name")" "$doctor_path/$command_name"
  done
  for command_name in aws kubectl terraform; do
    ln -s "$test_bin/$command_name" "$doctor_path/$command_name"
  done
  if [[ -n "$deadline_tool" ]]; then
    ln -s "$test_bin/$deadline_tool" "$doctor_path/$deadline_tool"
  fi
  PATH="$doctor_path"
  export PATH
}

install_drain_scripts() {
  for script in lifecycle-common.sh drain-ingress.sh drain-nodes.sh drain-pvcs.sh; do
    cp "$BATS_TEST_DIRNAME/../sh/$script" "$test_root/sh/$script"
  done
  chmod +x "$test_root/sh/drain-ingress.sh" "$test_root/sh/drain-nodes.sh" "$test_root/sh/drain-pvcs.sh"
}

use_sequence_fixture() {
  stub_aws_start
  STUB_AWS_SEQUENCE_FIXTURE="$BATS_TEST_DIRNAME/fixtures/aws/phase2-lifecycle-sequences.json"
  STUB_AWS_SEQUENCE_SCENARIO="$1"
  export STUB_AWS_SEQUENCE_FIXTURE STUB_AWS_SEQUENCE_SCENARIO
}

@test "make down is wired to the teardown spine" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"

  grep -Eq '^down:' "$makefile"
  grep -Fq '900s' "$makefile"
  grep -Fq 'sh/down.sh' "$makefile"
  [ -x "$down_script" ]
}

@test "make down runs through the deadline runner without AWS side effects" {
  run bash -c 'cd "$1" && "$2" -o doctor -s down' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$(wc -l < "$timeout_log" | tr -d ' ')" -eq 1 ]
  [[ "$(<"$timeout_log")" == *'--signal=TERM --kill-after=5s 900s bash sh/down.sh'* ]]
  timeout_line="$(grep -n '^timeout:' "$call_log" | cut -d: -f1)"
  doctor_line="$(grep -nF -- '-s doctor' "$call_log" | cut -d: -f1)"
  [ "$timeout_line" -lt "$doctor_line" ]
  [ "$status" -eq 0 ]
  [[ "$output" == *'[1/8] disable Argo auto-sync'* ]]
  [[ "$output" == *'[8/8] verify'* ]]
  [[ "$(<"$call_log")" == *'verify-teardown'* ]]
  [ ! -e "$test_root/.down.lock" ]
}

@test "a confirmed missing Argo application is a no-op before teardown continues" {
  install_drain_scripts
  export TEST_STATE_30_gitops=present
  export TEST_ARGOCD_GET_EXIT=3
  export TEST_ARGOCD_GET_ERROR='rpc error: code = NotFound desc = application root not found'

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'root application is confirmed absent'* ]]
  [[ "$(<"$call_log")" == *'app get root'* ]]
  [[ "$(<"$call_log")" != *'app set root'* ]]
  [[ "$(<"$call_log")" == *'_destroy-layer LAYER=30-gitops'* ]]
}

@test "an existing Argo application has auto-sync disabled" {
  install_drain_scripts
  export TEST_STATE_30_gitops=present

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 0 ]
  [[ "$(<"$call_log")" == *'app get root --output json'* ]]
  [[ "$(<"$call_log")" == *'app set root --sync-policy none'* ]]
}

@test "a non-NotFound Argo error stops before Terraform destroy" {
  install_drain_scripts
  export TEST_STATE_30_gitops=present
  export TEST_ARGOCD_GET_EXIT=1
  export TEST_ARGOCD_GET_ERROR='rpc error: code = PermissionDenied desc = denied'

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'PermissionDenied'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "Make L1 helpers use the generated backend and exact state key" {
  run bash -c 'cd "$1" && "$2" -s BACKEND_HCL="$3" _init-layer LAYER=10-infra' _ \
    "$test_root" "$TEST_REAL_MAKE" "$backend_hcl"

  [ "$status" -eq 0 ]
  [[ "$(<"$call_log")" == *"-backend-config=$backend_hcl"* ]]
  [[ "$(<"$call_log")" == *'-backend-config=key=infra/terraform.tfstate'* ]]

  : > "$call_log"
  run bash -c 'cd "$1" && "$2" -s _apply-layer LAYER=10-infra OPERATOR_CIDR=203.0.113.10/32' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -eq 0 ]
  [[ "$(<"$call_log")" == *'-var=operator_cidr=203.0.113.10/32'* ]]
}

@test "make up rejects an unreachable operator CIDR before init or apply" {
  run bash -c 'cd "$1" && OPERATOR_CIDR=203.0.113.20/32 "$2" -o doctor -s up' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -ne 0 ]
  [[ "$output" == *'does not contain the current public IP'* ]]
  [[ "$(<"$call_log")" != *'_init-layer'* ]]
  [[ "$(<"$call_log")" != *'_apply-layer'* ]]
}

@test "make up accepts and forwards multiple explicit operator CIDRs" {
  export TEST_PUBLIC_IP=198.51.100.20

  run bash -c 'cd "$1" && OPERATOR_CIDRS=203.0.113.10/32,198.51.100.20/32 "$2" -o doctor -s up' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'make up complete'* ]]
  [[ "$(<"$call_log")" == *'-var=operator_cidrs=["203.0.113.10/32","198.51.100.20/32"]'* ]]
}

@test "make up applies once and waits for all required EKS components" {
  run bash -c 'cd "$1" && OPERATOR_CIDR=203.0.113.10/32 "$2" -o doctor -s up' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'make up complete'* ]]
  [ "$(grep -c '_init-layer LAYER=10-infra' "$call_log")" -eq 1 ]
  [ "$(grep -c '_apply-layer LAYER=10-infra' "$call_log")" -eq 1 ]
  [ "$(grep -c 'eks describe-addon' "$call_log")" -eq 4 ]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "make up preserves a failed apply without retry or destroy" {
  export TEST_APPLY_EXIT=42

  run bash -c 'cd "$1" && OPERATOR_CIDR=203.0.113.10/32 "$2" -o doctor -s up' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -ne 0 ]
  [[ "$output" == *'test apply failure'* ]]
  [ "$(grep -c '_apply-layer LAYER=10-infra' "$call_log")" -eq 1 ]
  [[ "$(<"$call_log")" != *'eks describe-'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "make up stops on an unhealthy node group without retry or destroy" {
  export TEST_NODEGROUP_STATUS=DEGRADED

  run bash -c 'cd "$1" && OPERATOR_CIDR=203.0.113.10/32 "$2" -o doctor -s up' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -ne 0 ]
  [[ "$output" == *'node group'* ]]
  [ "$(grep -c '_apply-layer LAYER=10-infra' "$call_log")" -eq 1 ]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "doctor accepts the pinned kubectl client minor" {
  prepare_doctor_root
  run "$test_root/sh/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl v1.34.12"* ]]
  [[ "$output" == *"GNU timeout"* ]]
}

@test "doctor accepts gtimeout when timeout is unavailable" {
  prepare_doctor_root
  prepare_doctor_path gtimeout
  run "$test_root/sh/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtimeout'* ]]
}

@test "doctor blocks teardown when neither timeout command exists" {
  prepare_doctor_root
  prepare_doctor_path
  run "$test_root/sh/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'GNU timeout or gtimeout'* ]]
  [[ "$output" == *'brew install coreutils'* ]]
}

@test "doctor rejects kubectl outside the EKS server skew window" {
  prepare_doctor_root
  export TEST_KUBECTL_VERSION=v1.37.0
  run "$test_root/sh/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kubectl v1.37.0"* ]]
  [[ "$output" == *"EKS Kubernetes 1.34"* ]]
}

@test "Ingress drain waits for ELBv2 load balancers and target groups to disappear" {
  use_sequence_fixture ingress-pending-to-absent

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^elbv2 describe-load-balancers ' "$STUB_AWS_CALL_LOG")" -eq 2 ]
  [ "$(grep -c '^elbv2 describe-target-groups ' "$STUB_AWS_CALL_LOG")" -eq 2 ]
  [ "$(grep -c '^eks describe-cluster ' "$STUB_AWS_CALL_LOG")" -eq 1 ]
  [[ "$(<"$call_log")" == *'delete ingress --all --all-namespaces'* ]]
  [[ "$output" == *'AWS confirms no load balancers or target groups'* ]]
}

@test "a fresh teardown retry replays the first pending AWS responses" {
  use_sequence_fixture ingress-pending-to-absent

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^elbv2 describe-load-balancers ' "$STUB_AWS_CALL_LOG")" -eq 2 ]

  stub_aws_start
  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^elbv2 describe-load-balancers ' "$STUB_AWS_CALL_LOG")" -eq 2 ]
  [[ "$output" == *'AWS confirms no load balancers or target groups'* ]]
}

@test "NodePool drain waits for tagged Karpenter instances to disappear" {
  use_sequence_fixture karpenter-pending-to-absent

  run bash "$BATS_TEST_DIRNAME/../sh/drain-nodes.sh"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^ec2 describe-instances ' "$STUB_AWS_CALL_LOG")" -eq 2 ]
  [[ "$(<"$STUB_AWS_CALL_LOG")" == *'Name=tag:karpenter.sh/discovery,Values=microservices-demo'* ]]
  [[ "$(<"$call_log")" == *'delete nodepools.karpenter.sh --all'* ]]
  [[ "$output" == *'AWS confirms no tagged project Karpenter instances'* ]]
}

@test "PVC drain waits for PVC-owned EBS volumes to disappear" {
  use_sequence_fixture pvc-pending-to-absent

  run bash "$BATS_TEST_DIRNAME/../sh/drain-pvcs.sh"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^ec2 describe-volumes ' "$STUB_AWS_CALL_LOG")" -eq 2 ]
  [[ "$(<"$STUB_AWS_CALL_LOG")" == *'kubernetes.io/created-for/pvc/name'* ]]
  [[ "$(<"$call_log")" == *'delete pvc --all --all-namespaces'* ]]
  [[ "$output" == *'AWS confirms no tagged project PVC volumes'* ]]
}

@test "Ingress drain retries a classified transient AWS error" {
  use_sequence_fixture transient-retry

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 0 ]
  [ "$(grep -c '^elbv2 describe-load-balancers ' "$STUB_AWS_CALL_LOG")" -eq 3 ]
  [[ "$output" == *'retrying transient AWS error'* ]]
  [[ "$output" == *'AWS confirms no load balancers or target groups'* ]]
}

@test "Ingress drain bounds transient AWS retries" {
  use_sequence_fixture transient-retry-exhaustion

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 1 ]
  [ "$(grep -c '^elbv2 describe-load-balancers ' "$STUB_AWS_CALL_LOG")" -eq 3 ]
  [[ "$output" == *'ThrottlingException'* ]]
  [[ "$output" == *'last_observed=ELBv2 describe-load-balancers error'* ]]
  [[ "$(<"$call_log")" != *'kubectl delete'* ]]
}

@test "retry classification accepts transient AWS errors and rejects permanent or unknown errors" {
  common_file="$BATS_TEST_DIRNAME/../sh/lifecycle-common.sh"
  run bash -c '
    source "$1"
    for error in ThrottlingException RequestLimitExceeded ServiceUnavailableException InternalError EndpointConnectionError ReadTimeoutError; do
      lc_retryable_aws_error "$error" || exit 1
    done
    for error in AccessDeniedException ValidationException unknown-malformed-response; do
      if lc_retryable_aws_error "$error"; then exit 2; fi
    done
  ' _ "$common_file"
  [ "$status" -eq 0 ]
}

@test "shared deadline helper distinguishes before exact and after 900 seconds" {
  common_file="$BATS_TEST_DIRNAME/../sh/lifecycle-common.sh"
  run bash -c '
    source "$1"
    declare -F lc_deadline_expired >/dev/null || { printf "%s\n" "deadline helper is missing"; exit 1; }
    lc_monotonic_seconds() { printf "%s\n" "$FAKE_MONOTONIC_SECONDS"; }
    LC_STARTED_SECONDS=100
    FAKE_MONOTONIC_SECONDS=999
    if lc_deadline_expired; then exit 10; fi
    [[ "$(lc_elapsed)" == 899s ]] || exit 11
    FAKE_MONOTONIC_SECONDS=1000
    lc_deadline_expired || exit 12
    [[ "$(lc_elapsed)" == 900s ]] || exit 13
    FAKE_MONOTONIC_SECONDS=1001
    lc_deadline_expired || exit 14
    [[ "$(lc_elapsed)" == 901s ]] || exit 15
  ' _ "$common_file"
  [ "$status" -eq 0 ]
}

@test "Ingress delete failure with residual ELB resources stops before Service deletion" {
  use_sequence_fixture ingress-delete-fail-residual
  export TEST_KUBECTL_INGRESS_DELETE_EXIT=1
  export TEST_KUBECTL_INGRESS_DELETE_ERROR='Forbidden: ingress deletion denied'

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'Forbidden: ingress deletion denied'* ]]
  [[ "$output" == *'load-balancer:arn:aws:elasticloadbalancing'* ]]
  [[ "$(<"$call_log")" != *'delete service'* ]]
}

@test "a permanent ELBv2 error fails the drain and prevents destroy" {
  use_sequence_fixture elbv2-permanent-error
  install_drain_scripts
  export TEST_STATE_10_infra=present

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'AccessDeniedException'* ]]
  [[ "$output" == *'No Terraform destroy was attempted'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
  [[ "$(<"$STUB_AWS_CALL_LOG")" != *'_destroy-layer'* ]]
}

@test "a failed NodePool drain stops make down before Terraform destroy" {
  use_sequence_fixture active-node-api-unreachable
  install_drain_scripts
  export TEST_STATE_10_infra=present
  export TEST_KUBECTL_API_EXIT=1
  export TEST_KUBECTL_ERROR='The server could not be reached: test timeout'

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'drain Karpenter NodePools'* ]]
  [[ "$output" == *'i-0123456789abcdef0'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
  [[ "$(<"$STUB_AWS_CALL_LOG")" != *'_destroy-layer'* ]]
  [[ "$(<"$call_log")" != *'cloud-nuke'* ]]
}

@test "a failed PVC drain stops make down before Terraform destroy" {
  use_sequence_fixture active-pvc-api-unreachable
  install_drain_scripts
  export TEST_STATE_10_infra=present
  export TEST_KUBECTL_API_EXIT=1
  export TEST_KUBECTL_ERROR='The server could not be reached: test timeout'

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'drain PVCs'* ]]
  [[ "$output" == *'vol-0123456789abcdef0'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
  [[ "$(<"$STUB_AWS_CALL_LOG")" != *'_destroy-layer'* ]]
}

@test "an unreachable API with residual Karpenter instances reports IDs and stops" {
  export TEST_INSTANCE_RESPONSE_1='{"Reservations":[{"Instances":[{"InstanceId":"i-0123456789abcdef0","State":{"Name":"running"}}]}]}'
  export TEST_KUBECTL_API_EXIT=1
  export TEST_KUBECTL_ERROR='The server could not be reached: test timeout'

  run bash "$BATS_TEST_DIRNAME/../sh/drain-nodes.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=ACTIVE'* ]]
  [[ "$output" == *'i-0123456789abcdef0'* ]]
  [[ "$output" == *'The server could not be reached: test timeout'* ]]
  [[ "$output" == *'rerun make down from step one'* ]]
}

@test "an unknown EKS state with residual PVC volumes fails closed" {
  export TEST_CLUSTER_STATUS=UNRECOGNIZED
  export TEST_VOLUME_RESPONSE_1='{"Volumes":[{"VolumeId":"vol-0123456789abcdef0","State":"in-use","Tags":[{"Key":"kubernetes.io/cluster/microservices-demo","Value":"owned"},{"Key":"kubernetes.io/created-for/pvc/name","Value":"data"},{"Key":"kubernetes.io/created-for/pvc/namespace","Value":"default"}],"Attachments":[]}]}'

  run bash "$BATS_TEST_DIRNAME/../sh/drain-pvcs.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=UNKNOWN'* ]]
  [[ "$output" == *'vol-0123456789abcdef0'* ]]
  [[ "$output" == *'unsupported EKS cluster status: UNRECOGNIZED'* ]]
  [[ "$(<"$call_log")" != *'delete pvc'* ]]
}

@test "CREATING clusters use only AWS absence proof and report residual Ingress IDs" {
  use_sequence_fixture eks-creating-residual

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=CREATING'* ]]
  [[ "$output" == *'load-balancer:arn:aws:elasticloadbalancing'* ]]
  [[ "$output" == *'explicitly handle untagged resources'* ]]
  [[ "$output" == *'rerun make down from step one'* ]]
  [[ "$(<"$call_log")" != *'kubectl get'* ]]
}

@test "FAILED clusters stop on residual Karpenter instances without kubectl" {
  use_sequence_fixture eks-failed-residual

  run bash "$BATS_TEST_DIRNAME/../sh/drain-nodes.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=FAILED'* ]]
  [[ "$output" == *'i-0123456789abcdef0'* ]]
  [[ "$output" == *'drain the named NodePool/instances'* ]]
  [[ "$output" == *'rerun make down from step one'* ]]
  [[ "$(<"$call_log")" != *'kubectl get'* ]]
}

@test "DEGRADED clusters preserve Kubernetes errors and PVC attachment diagnostics" {
  use_sequence_fixture eks-degraded-residual
  export TEST_KUBECTL_API_EXIT=1
  export TEST_KUBECTL_ERROR='Forbidden: test cluster API denial'

  run bash "$BATS_TEST_DIRNAME/../sh/drain-pvcs.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=DEGRADED'* ]]
  [[ "$output" == *'vol-0123456789abcdef0'* ]]
  [[ "$output" == *'attachments=i-0123456789abcdef0'* ]]
  [[ "$output" == *'Forbidden: test cluster API denial'* ]]
  [[ "$output" == *'delete the PVC first'* ]]
  [[ "$output" == *'rerun make down from step one'* ]]
}

@test "only an EKS ResourceNotFound response classifies the cluster as ABSENT" {
  use_sequence_fixture eks-absent-terminal

  run bash "$BATS_TEST_DIRNAME/../sh/drain-ingress.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'(EKS ABSENT)'* ]]
  [[ "$(<"$call_log")" != *'kubectl get'* ]]
}

@test "an EKS authorization error is UNKNOWN rather than ABSENT" {
  use_sequence_fixture eks-authorization-error

  run bash "$BATS_TEST_DIRNAME/../sh/drain-nodes.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'EKS_state=UNKNOWN'* ]]
  [[ "$output" == *'AccessDeniedException'* ]]
  [[ "$(<"$call_log")" != *'kubectl get'* ]]
}

@test "malformed AWS volume data is never treated as an empty PVC set" {
  use_sequence_fixture malformed-volume-response

  run bash "$BATS_TEST_DIRNAME/../sh/drain-pvcs.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'malformed or unowned PVC volume response'* ]]
  [[ "$output" == *'last_observed=malformed EC2 volume response'* ]]
  [[ "$output" == *'rerun make down from step one'* ]]
}

@test "empty account runs the eight named stages and preserves verifier success" {
  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 0 ]
  expected_stages="$(printf '%s\n' \
    '==> [1/8] disable Argo auto-sync' \
    '==> [2/8] drain Ingresses' \
    '==> [3/8] drain Karpenter NodePools' \
    '==> [4/8] drain PVCs' \
    '==> [5/8] destroy 30-gitops' \
    '==> [6/8] destroy 20-data' \
    '==> [7/8] destroy 10-infra' \
    '==> [8/8] verify')"
  actual_stages="$(grep -E '^==> \[[1-8]/8\]' <<< "$output")"
  [ "$actual_stages" = "$expected_stages" ]
  destroy_order="$(grep '^destroy:' "$call_log")"
  expected_destroy_order="$(printf '%s\n' 'destroy:30-gitops' 'destroy:20-data' 'destroy:10-infra')"
  [ "$destroy_order" = "$expected_destroy_order" ]
  [[ "$(<"$call_log")" == *'verify-teardown'* ]]
  [[ "$(<"$call_log")" != *'cloud-nuke'* ]]
  [[ "$output" == *'Successful teardown timing: total='*'stage_8='*'verifier_exit=0'* ]]
  [ ! -e "$test_root/.down.lock" ]
}

@test "a present infrastructure state fails closed before any destroy" {
  export TEST_STATE_10_infra=present

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" != *'No such file or directory'* ]]
  [[ "$output" == *'drain Ingresses'* ]]
  [[ "$output" == *'retry make down'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "an existing lock rejects a second run before state lookup" {
  mkdir "$test_root/.down.lock"

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'another teardown holds'* ]]
  [ ! -s "$call_log" ]
}

@test "overlapping teardown is rejected before a second lifecycle action" {
  export TEST_BLOCK_STATE=true
  bash -c 'set +e; bash "$1"; rc=$?; printf "EXIT_CODE=%s\n" "$rc"; exit 0' _ \
    "$test_root/sh/down.sh" > "$BATS_TEST_TMPDIR/first-run.out" 2>&1 &
  first_pid=$!
  while [[ ! -e "$TEST_ENTERED" ]]; do :; done

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'another teardown holds'* ]]
  [ "$(grep -c '_layer-state LAYER=10-infra' "$call_log")" -eq 1 ]
  : > "$TEST_RELEASE"
  wait "$first_pid"
  grep -Fq 'EXIT_CODE=0' "$BATS_TEST_TMPDIR/first-run.out"
}

@test "a handled termination reports its stage and releases the lock" {
  export TEST_TERMINATE_PARENT=true

  run bash -c 'set +e; bash "$1"; rc=$?; printf "\nEXIT_CODE=%s\n" "$rc"' _ \
    "$test_root/sh/down.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'EXIT_CODE=124'* ]]
  [[ "$output" == *'interrupted by INT'* || "$output" == *'interrupted by TERM'* ]]
  [[ "$output" == *'preflight'* ]]
  [ ! -e "$test_root/.down.lock" ]
}

@test "an empty teardown can be safely rerun from stage one" {
  run bash "$test_root/sh/down.sh"
  [ "$status" -eq 0 ]

  run bash "$test_root/sh/down.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'verify-teardown' "$call_log")" -eq 2 ]
}

@test "an unknown state lookup fails closed before any destroy" {
  export TEST_STATE_20_data=unknown

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *'No such file or directory'* ]]
  [[ "$output" == *'state lookup failed'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
}

@test "a valid empty S3 listing confirms an absent state" {
  export TEST_AWS_RESPONSE='{"KeyCount":0}'

  run_layer_state

  [ "$status" -eq 0 ]
  [ "$output" = absent ]
}

@test "a valid exact S3 state key is reported present" {
  export TEST_AWS_RESPONSE='{"KeyCount":1,"Contents":[{"Key":"infra/terraform.tfstate"}]}'

  run_layer_state

  [ "$status" -eq 0 ]
  [ "$output" = present ]
}

@test "an AWS state lookup error is never treated as an absent state" {
  export TEST_AWS_EXIT=254

  run_layer_state

  [ "$status" -eq 2 ]
  [[ "$output" == *'could not determine state'* ]]
  [[ "$output" != absent ]]
}

@test "a malformed S3 state listing is never treated as an absent state" {
  export TEST_AWS_RESPONSE='{"KeyCount":1,"Contents":"malformed"}'

  run_layer_state

  [ "$status" -eq 2 ]
  [[ "$output" == *'malformed S3 state listing'* ]]
  [[ "$output" != absent ]]
}

@test "the verifier orphan result remains exit 1" {
  export TEST_VERIFY_EXIT=1

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *'test verifier output'* ]]
  [[ "$output" != *'Successful teardown timing'* ]]
}

@test "the verifier error result remains exit 2" {
  export TEST_VERIFY_EXIT=2

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *'test verifier output'* ]]
  [[ "$output" != *'Successful teardown timing'* ]]
}

@test "Cloud Nuke contract reports identical scopes without enabling unproven types" {
  wrapper="$BATS_TEST_DIRNAME/../sh/nuke-project.sh"
  [ -x "$wrapper" ]

  run bash "$wrapper" --print-scope-contract

  [ "$status" -eq 0 ]
  jq -e '.contract_only and (.invocation_allowed == false) and (.preview_scope == .execution_scope) and (.deletable_resource_types == []) and (.preview_argv[1] == "--dry-run") and (.execution_argv[1] == "--force")' <<< "$output" >/dev/null
  jq -e '.tag_filter == {"Project":"microservices-demo"} and (.untagged_control_eligible == false) and (.report_only_resource_types == ["ec2"]) and (.vpc_included == false)' <<< "$output" >/dev/null
  jq -e 'any(.preview_scope[]; . == "--region") and any(.preview_scope[]; . == "--config") and any(.preview_scope[]; . == "--resource-type") and any(.preview_scope[]; . == "ec2")' <<< "$output" >/dev/null
  [[ "$(<"$call_log")" != *'cloud-nuke'* ]]
}