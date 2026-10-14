#!/usr/bin/env bats

setup() {
  real_make="$(command -v make)"
  test_bin="$BATS_TEST_TMPDIR/bin"
  test_root="$BATS_TEST_TMPDIR/repo"
  call_log="$BATS_TEST_TMPDIR/calls.log"
  backend_hcl="$BATS_TEST_TMPDIR/backend.hcl"
  mkdir -p "$test_bin" "$test_root/sh" "$test_root/layers/10-infra"
  cp "$BATS_TEST_DIRNAME/../Makefile" "$test_root/Makefile"
  cp "$BATS_TEST_DIRNAME/../sh/down.sh" "$test_root/sh/down.sh" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../sh/up.sh" "$test_root/sh/up.sh" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../sh/run-down-with-deadline.py" "$test_root/sh/run-down-with-deadline.py"
  printf '%s\n' 'bucket = "test-state-bucket"' > "$backend_hcl"
  : > "$call_log"

  cat > "$test_bin/make" <<'MAKE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$TEST_CALL_LOG"
target=""
layer=""
for argument in "$@"; do
  case "$argument" in
    _layer-state|_init-layer|_apply-layer|_destroy-layer|verify-teardown) target="$argument" ;;
    LAYER=*) layer="${argument#LAYER=}" ;;
  esac
done
case "$target" in
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
  case "${1:-}:${2:-}" in
    eks:describe-cluster)
      printf '{"cluster":{"status":"%s"}}\n' "${TEST_CLUSTER_STATUS:-ACTIVE}"
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
  *'output -raw cluster_name'*) printf '%s\n' 'microservices-demo' ;;
  *'output -raw system_node_group_name'*) printf '%s\n' 'microservices-demo-system' ;;
  *' init '*) exit 0 ;;
  *' apply '*) exit "${TEST_APPLY_EXIT:-0}" ;;
  *) printf 'unexpected terraform invocation: %s\n' "$*" >&2; exit 64 ;;
esac
TERRAFORM
  chmod +x "$test_bin/terraform"

  export TEST_CALL_LOG="$call_log"
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

run_layer_state() {
  run "$TEST_REAL_MAKE" -s "BACKEND_HCL=$TEST_BACKEND_HCL" \
    _layer-state LAYER=10-infra
}

@test "make down is wired to the teardown spine" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"

  grep -Eq '^down:' "$makefile"
  grep -Fq 'python3 sh/run-down-with-deadline.py' "$makefile"
  grep -Fq '"sh/down.sh"' "$BATS_TEST_DIRNAME/../sh/run-down-with-deadline.py"
  [ -x "$down_script" ]
}

@test "deadline runner preserves the teardown command exit code" {
  deadline_runner="$BATS_TEST_DIRNAME/../sh/run-down-with-deadline.py"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "$test_root/sh/down.sh"

  run bash -c 'cd "$1" && python3 "$2"' _ "$test_root" "$deadline_runner"

  [ "$status" -eq 7 ]
}

@test "make down runs through the deadline runner without AWS side effects" {
  run bash -c 'cd "$1" && "$2" -o doctor -s down' _ \
    "$test_root" "$TEST_REAL_MAKE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'[1/8] disable Argo auto-sync'* ]]
  [[ "$output" == *'[8/8] verify'* ]]
  [[ "$(<"$call_log")" == *'verify-teardown'* ]]
  [ ! -e "$test_root/.down.lock" ]
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
  [[ "$(<"$call_log")" == *'verify-teardown'* ]]
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
}

@test "the verifier error result remains exit 2" {
  export TEST_VERIFY_EXIT=2

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *'test verifier output'* ]]
}