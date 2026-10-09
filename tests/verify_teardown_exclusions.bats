#!/usr/bin/env bats

load 'helpers/load'

setup() {
  stub_aws_start
  ALLOWLIST="$BATS_TEST_TMPDIR/allowlist.txt"
  REPORT="$BATS_TEST_TMPDIR/teardown-report.json"
  printf '%s\n' \
    'baseline-allowed-alb' \
    'baseline-allowed-classic' \
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

@test "reports active and provisioning load balancers and excludes the baseline one" {
  run_sweep
  assert_dirty_report
  assert_report_has load_balancers k8s-demo-ingress-1a2b3c4d
  assert_report_has load_balancers half-created-ingress
  assert_report_lacks load_balancers baseline-allowed-alb
}

@test "reports classic load balancers and excludes the baseline one" {
  run_sweep
  assert_dirty_report
  assert_report_has load_balancers legacy-manual-classic
  assert_report_lacks load_balancers baseline-allowed-classic
  grep -Fq -- 'elb describe-load-balancers' "$STUB_AWS_CALL_LOG"
}

@test "reports an orphan target group and excludes the baseline one" {
  run_sweep
  assert_dirty_report
  assert_report_has target_groups orphan-manual-target
  assert_report_has target_groups attached-manual-target
  assert_report_lacks target_groups baseline-allowed-target
  jq -e '.orphans.target_groups[] | select(.id == "orphan-manual-target") | .reason | contains("no load balancer attached")' "$REPORT" >/dev/null
  jq -e '.orphans.target_groups[] | select(.id == "attached-manual-target") | .reason | contains("attached to live LB")' "$REPORT" >/dev/null
}

@test "reports a controller-style security group and excludes default" {
  run_sweep
  assert_dirty_report
  assert_report_has security_groups sg-00000000000000002
  assert_report_has security_groups sg-00000000000000003
  assert_report_lacks security_groups sg-00000000000000001
  jq -e '.orphans.security_groups[] | select(.id == "sg-00000000000000002") | .reason | test("controller"; "i")' "$REPORT" >/dev/null
  grep -Fq -- 'GroupName!=`default`' "$STUB_AWS_CALL_LOG"
  default_exclusions="$(grep -v '^[[:space:]]*#' "$BATS_TEST_DIRNAME/../scripts/verify-teardown.sh" | grep -c 'default')"
  [ "$default_exclusions" -ge 2 ]
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

@test "summarizes wired classes and prints their usual causes" {
  run_sweep
  assert_dirty_report
  jq -e '.summary.by_class | .ebs_volumes == 1 and .ec2_instances == 2 and .snapshots == 1 and .elastic_ips == 1 and .enis == 1 and .security_groups == 2 and .load_balancers == 3 and .target_groups == 2 and .log_groups == 0 and .eks_clusters == 0 and .rds_instances == 0 and .iam == 0 and .cloudfront == 0 and .s3_buckets == 0 and .tagged == 0' "$REPORT" >/dev/null
  jq -e '[.orphans[] | .[]] | all(.[]; (.reason | length) > 0 and .discovered_by == "blind-spot")' "$REPORT" >/dev/null
  [[ "$output" == *"usual cause: node group deletion left detached EBS volumes"* ]]
  [[ "$output" == *"usual cause: stopped or unterminated EC2 instance"* ]]
  [[ "$output" == *"usual cause: manual or AMI-backed snapshots retained"* ]]
  [[ "$output" == *"usual cause: unassociated public IPv4 allocation retained"* ]]
  [[ "$output" == *"usual cause: parent teardown left a detached interface"* ]]
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