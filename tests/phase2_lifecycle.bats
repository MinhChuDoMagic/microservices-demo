#!/usr/bin/env bats

setup() {
  test_bin="$BATS_TEST_TMPDIR/bin"
  test_root="$BATS_TEST_TMPDIR/repo"
  call_log="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$test_bin" "$test_root/sh"
  cp "$BATS_TEST_DIRNAME/../sh/down.sh" "$test_root/sh/down.sh" 2>/dev/null || true
  : > "$call_log"

  cat > "$test_bin/make" <<'MAKE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$TEST_CALL_LOG"
target=""
layer=""
for argument in "$@"; do
  case "$argument" in
    _layer-state|_destroy-layer|verify-teardown) target="$argument" ;;
    LAYER=*) layer="${argument#LAYER=}" ;;
  esac
done
case "$target" in
  _layer-state)
    variable="TEST_STATE_${layer//-/_}"
    state="${!variable:-absent}"
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

  export TEST_CALL_LOG="$call_log"
  export TEST_STATE_10_infra=absent
  export TEST_STATE_20_data=absent
  export TEST_STATE_30_gitops=absent
  export PATH="$test_bin:$PATH"
}

@test "make down is wired to the teardown spine" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"

  grep -Eq '^down:' "$makefile"
  grep -Fq 'bash sh/down.sh' "$makefile"
  [ -x "$down_script" ]
}

@test "empty account runs the eight named stages and preserves verifier success" {
  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'[1/8] disable Argo auto-sync'* ]]
  [[ "$output" == *'[2/8] drain Ingresses'* ]]
  [[ "$output" == *'[3/8] drain Karpenter NodePools'* ]]
  [[ "$output" == *'[4/8] drain PVCs'* ]]
  [[ "$output" == *'[5/8] destroy 30-gitops'* ]]
  [[ "$output" == *'[6/8] destroy 20-data'* ]]
  [[ "$output" == *'[7/8] destroy 10-infra'* ]]
  [[ "$output" == *'[8/8] verify'* ]]
  [[ "$(<"$call_log")" == *'verify-teardown'* ]]
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

@test "an unknown state lookup fails closed before any destroy" {
  export TEST_STATE_20_data=unknown

  run bash "$test_root/sh/down.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *'No such file or directory'* ]]
  [[ "$output" == *'state lookup failed'* ]]
  [[ "$(<"$call_log")" != *'_destroy-layer'* ]]
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