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
  [[ -f "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh" ]] \
    || skip 'MISSING — created in 01-04'
}

allow_all_reportable_fixtures() {
  printf '%s\n' \
    'k8s-demo-ingress-1a2b3c4d' \
    'baseline-allowed-alb' \
    'half-created-ingress' \
    'legacy-manual-classic' \
    'baseline-allowed-classic' \
    'orphan-manual-target' \
    'baseline-allowed-target' \
    'attached-manual-target' \
    'sg-00000000000000002' \
    'sg-00000000000000003' \
    'i-00000000000000003' \
    'i-00000000000000004' \
    'vol-00000000000000002' \
    'snap-00000000000000002' \
    'eipalloc-00000000000000002' \
    'eni-00000000000000004' \
    '/aws/eks/demo/unexpected' \
    '/practice/new-short-retention' \
    '/practice/baseline-allowed' \
    'i-tier3-00000000000000001' \
    'practice-stray-cluster' \
    'practice-stray-database' \
    'practice-unexpected-bucket' \
    'UnexpectedRole' > "$ALLOWLIST"
}

@test "clean fixture account exits 0" {
  require_sweep
  allow_all_reportable_fixtures

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

  [ "$status" -eq 0 ]
  jq -e '.verdict == "clean" and .exit_code == 0' "$REPORT" >/dev/null
}

@test "an unallowlisted orphan exits 1" {
  require_sweep

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

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
  printf 'An error occurred (ExpiredToken) when calling the DescribeSnapshots operation: The security token included in the request is expired\n' \
    > "$fixture_overlay/ec2-describe-snapshots.err"
  STUB_AWS_FIXTURE_DIR="$fixture_overlay"
  export STUB_AWS_FIXTURE_DIR

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *"account is CLEAN"* ]]
  jq -e '.verdict == "error" and .exit_code == 2 and (.errors | length > 0) and .summary.total_orphans > 0' \
    "$REPORT" >/dev/null
}

@test "an expired resource-tag pagination token exits 2" {
  require_sweep
  fixture_overlay="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$fixture_overlay"
  cp -R "$BATS_TEST_DIRNAME/fixtures/aws/." "$fixture_overlay/"
  printf '%s\n' '{"PaginationToken":"expired-page","ResourceTagMappingList":[]}' \
    > "$fixture_overlay/resourcegroupstaggingapi-get-resources.json"
  STUB_AWS_FIXTURE_DIR="$fixture_overlay"
  export STUB_AWS_FIXTURE_DIR

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

  [ "$status" -eq 2 ]
  jq -e '.verdict == "error" and .exit_code == 2 and any(.errors[]; .message | contains("pagination token expired"))' \
    "$REPORT" >/dev/null
}

@test "tier-three endpoint unavailability is skipped without masking other findings" {
  require_sweep
  fixture_overlay="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$fixture_overlay"
  cp -R "$BATS_TEST_DIRNAME/fixtures/aws/." "$fixture_overlay/"
  printf 'Could not connect to the endpoint URL: https://ec2.eu-west-1.amazonaws.com/\n' \
    > "$fixture_overlay/ec2-describe-instances-eu-west-1.err"
  STUB_AWS_FIXTURE_DIR="$fixture_overlay"
  export STUB_AWS_FIXTURE_DIR

  run bash "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh"

  [ "$status" -eq 1 ]
  jq -e '.verdict == "orphans" and .errors == [] and .regions_scanned.tier3 == ["eu-west-1"]' \
    "$REPORT" >/dev/null
  jq -e '.orphans.eks_clusters | any(.id == "practice-stray-cluster")' "$REPORT" >/dev/null
  jq -e '.orphans.rds_instances | any(.id == "practice-stray-database")' "$REPORT" >/dev/null
}

@test "a schema class without a registered check fails closed and names the class" {
  require_sweep
  modified_script="$BATS_TEST_TMPDIR/verify-teardown-missing-check.sh"
  awk '{ if ($0 == "tagged\047") print "coverage_probe"; print }' \
    "$BATS_TEST_DIRNAME/../sh/verify-teardown.sh" > "$modified_script"

  run bash "$modified_script"

  [ "$status" -eq 2 ]
  [[ "$output" == *"coverage_probe"* ]]
  jq -e '.verdict == "error" and .exit_code == 2 and any(.errors[]; .scope == "class_coverage" and (.message | contains("coverage_probe")))' \
    "$REPORT" >/dev/null
}