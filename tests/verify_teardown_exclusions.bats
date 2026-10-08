#!/usr/bin/env bats

load 'helpers/load'

setup() {
  stub_aws_start
  ALLOWLIST="$BATS_TEST_TMPDIR/allowlist.txt"
  REPORT="$BATS_TEST_TMPDIR/teardown-report.json"
  printf '%s\n' \
    'baseline-allowed-alb' \
    'baseline-allowed-target' \
    '/practice/baseline-allowed' > "$ALLOWLIST"
  export ALLOWLIST REPORT
}

teardown() {
  stub_aws_stop
}

require_sweep_class() {
  local function_name="$1"
  local script="$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh"

  [[ -f "$script" ]] || skip 'MISSING — created in 01-04'
  grep -Eq "^[[:space:]]*${function_name}[[:space:]]*\(\)" "$script" \
    || skip 'MISSING — created in 01-04'
}

run_sweep() {
  run bash "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh"
}

assert_report_has() {
  local class="$1"
  local identifier="$2"
  jq -e --arg class "$class" --arg id "$identifier" \
    '.orphans[$class] | any(.[]?; .id == $id)' "$REPORT" >/dev/null
}

assert_report_lacks() {
  local class="$1"
  local identifier="$2"
  ! jq -e --arg class "$class" --arg id "$identifier" \
    '.orphans[$class] | any(.[]?; .id == $id)' "$REPORT" >/dev/null
}

assert_dirty_report() {
  [ "$status" -eq 1 ]
  [ -f "$REPORT" ]
}

@test "reports an unallowlisted load balancer and excludes the baseline one" {
  require_sweep_class check_load_balancers
  run_sweep
  assert_dirty_report
  assert_report_has load_balancers k8s-demo-ingress-1a2b3c4d
  assert_report_lacks load_balancers baseline-allowed-alb
}

@test "reports an orphan target group and excludes the baseline one" {
  require_sweep_class check_target_groups
  run_sweep
  assert_dirty_report
  assert_report_has target_groups orphan-manual-target
  assert_report_lacks target_groups baseline-allowed-target
}

@test "reports a controller-style security group and excludes default" {
  require_sweep_class check_security_groups
  run_sweep
  assert_dirty_report
  assert_report_has security_groups sg-00000000000000002
  assert_report_lacks security_groups sg-00000000000000001
}

@test "reports running and stopped instances but excludes terminated states" {
  run_sweep
  assert_dirty_report
  assert_report_has ec2_instances i-00000000000000003
  assert_report_has ec2_instances i-00000000000000004
  assert_report_lacks ec2_instances i-00000000000000001
  assert_report_lacks ec2_instances i-00000000000000002
  jq -e '.orphans.ec2_instances[] | select(.id == "i-00000000000000003") | .reason | test("^stopped instance; root EBS volume continues billing$"; "i")' "$REPORT" >/dev/null
  grep -Fq -- 'Name=instance-state-name,Values=pending,running,stopping,stopped' "$STUB_AWS_CALL_LOG"
}

@test "reports detached available volumes but excludes in-use volumes" {
  run_sweep
  assert_dirty_report
  assert_report_has ebs_volumes vol-00000000000000002
  assert_report_lacks ebs_volumes vol-00000000000000001
  grep -Fq -- 'Name=status,Values=available' "$STUB_AWS_CALL_LOG"
}

@test "reports manual snapshots but excludes image-backed snapshots" {
  run_sweep
  assert_dirty_report
  assert_report_has snapshots snap-00000000000000002
  assert_report_lacks snapshots snap-00000000000000001
  grep -Fq -- '--owner-ids self' "$STUB_AWS_CALL_LOG"
  grep -Fq -- '--owners self' "$STUB_AWS_CALL_LOG"
}

@test "reports unassociated addresses but excludes associated addresses" {
  run_sweep
  assert_dirty_report
  assert_report_has elastic_ips eipalloc-00000000000000002
  assert_report_lacks elastic_ips eipalloc-00000000000000001
  jq -e '.orphans.elastic_ips[] | select(.id == "eipalloc-00000000000000002") | .reason | test("^public IPv4 address bills hourly whether attached or idle"; "i")' "$REPORT" >/dev/null
}

@test "reports a plain detached interface and excludes managed interfaces" {
  run_sweep
  assert_dirty_report
  assert_report_has enis eni-00000000000000004
  assert_report_lacks enis eni-00000000000000001
  assert_report_lacks enis eni-00000000000000002
  assert_report_lacks enis eni-00000000000000003
  jq -e '.orphans.enis[] | select(.id == "eni-00000000000000004") | .reason | contains("manual untagged interface")' "$REPORT" >/dev/null
  grep -Fq -- 'Name=status,Values=available' "$STUB_AWS_CALL_LOG"
}

@test "reports non-allowlisted log groups and excludes the baseline group" {
  require_sweep_class check_log_groups
  run_sweep
  assert_dirty_report
  assert_report_has log_groups /aws/eks/demo/unexpected
  assert_report_has log_groups /practice/new-short-retention
  assert_report_lacks log_groups /practice/baseline-allowed
}

@test "reports ordinary IAM roles but excludes service-linked roles" {
  require_sweep_class check_iam
  run_sweep
  assert_dirty_report
  assert_report_has iam UnexpectedRole
  assert_report_lacks iam AWSServiceRoleForAmazonEKS
}

@test "normalizes the empty CloudFront distribution list" {
  require_sweep_class check_cloudfront
  run_sweep
  [ "$status" -ne 2 ]
  [ -f "$REPORT" ]
  jq -e '.orphans.cloudfront | length == 0' "$REPORT" >/dev/null
}