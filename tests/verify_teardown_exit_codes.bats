#!/usr/bin/env bats

load 'helpers/load'

setup() {
  stub_aws_start
  ALLOWLIST="$BATS_TEST_TMPDIR/allowlist.txt"
  REPORT="$BATS_TEST_TMPDIR/teardown-report.json"
  : > "$ALLOWLIST"
  export ALLOWLIST REPORT
}

teardown() {
  stub_aws_stop
}

require_sweep() {
  [[ -f "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh" ]] \
    || skip 'MISSING — created in 01-04'
}

allow_all_reportable_fixtures() {
  printf '%s\n' \
    'k8s-demo-ingress-1a2b3c4d' \
    'orphan-manual-target' \
    'sg-00000000000000002' \
    'i-00000000000000003' \
    'i-00000000000000004' \
    'vol-00000000000000002' \
    'snap-00000000000000002' \
    'eipalloc-00000000000000002' \
    'eni-00000000000000004' \
    '/aws/eks/demo/unexpected' \
    '/practice/new-short-retention' \
    'UnexpectedRole' > "$ALLOWLIST"
}

@test "clean fixture account exits 0" {
  require_sweep
  allow_all_reportable_fixtures

  run bash "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh"

  [ "$status" -eq 0 ]
  jq -e '.verdict == "clean" and .exit_code == 0' "$REPORT" >/dev/null
}

@test "an unallowlisted orphan exits 1" {
  require_sweep

  run bash "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh"

  [ "$status" -eq 1 ]
  jq -e '.verdict == "orphans" and .exit_code == 1 and .summary.total_orphans > 0' \
    "$REPORT" >/dev/null
}

@test "a mid-sweep credential failure exits 2 without a clean verdict" {
  require_sweep
  fixture_overlay="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$fixture_overlay"
  for fixture in "$BATS_TEST_DIRNAME"/fixtures/aws/*; do
    ln -s "$fixture" "$fixture_overlay/$(basename "$fixture")"
  done
  printf 'An error occurred (ExpiredToken) when calling the DescribeVolumes operation: The security token included in the request is expired\n' \
    > "$fixture_overlay/ec2-describe-volumes.err"
  STUB_AWS_FIXTURE_DIR="$fixture_overlay"
  export STUB_AWS_FIXTURE_DIR

  run bash "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *"account is CLEAN"* ]]
  jq -e '.verdict == "error" and .exit_code == 2 and (.errors | length > 0)' \
    "$REPORT" >/dev/null
}