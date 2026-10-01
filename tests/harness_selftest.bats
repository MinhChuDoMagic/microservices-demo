#!/usr/bin/env bats

load 'helpers/load'

setup() {
  stub_aws_start
  STUB_AWS_FIXTURE_DIR="$BATS_TEST_TMPDIR/fixtures"
  export STUB_AWS_FIXTURE_DIR
  mkdir -p "$STUB_AWS_FIXTURE_DIR"
}

teardown() {
  stub_aws_stop
}

@test "replays a JSON fixture verbatim and records full argv including region" {
  printf '{"Volumes": []}\n' > "$STUB_AWS_FIXTURE_DIR/ec2-describe-volumes.json"

  run aws ec2 describe-volumes --region us-east-1

  [ "$status" -eq 0 ]
  [ "$output" = '{"Volumes": []}' ]
  grep -Fq -- '--region us-east-1' "$STUB_AWS_CALL_LOG"
}

@test "prefers an error fixture over a JSON fixture" {
  printf '{"Volumes": []}\n' > "$STUB_AWS_FIXTURE_DIR/ec2-describe-volumes.json"
  printf 'The security token included in the request is expired\n' > \
    "$STUB_AWS_FIXTURE_DIR/ec2-describe-volumes.err"

  run aws ec2 describe-volumes

  [ "$status" -eq 255 ]
  [ "$output" = 'The security token included in the request is expired' ]
}

@test "replays the repository volume fixture from the default fixture directory" {
  STUB_AWS_FIXTURE_DIR="$BATS_TEST_DIRNAME/fixtures/aws"
  export STUB_AWS_FIXTURE_DIR
  expected="$(cat "$STUB_AWS_FIXTURE_DIR/ec2-describe-volumes.json")"

  run aws ec2 describe-volumes --region us-east-1

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "returns 99 and names both searched paths for a missing fixture" {
  run aws ec2 describe-nonexistent-thing

  [ "$status" -eq 99 ]
  [[ "$output" == *"$STUB_AWS_FIXTURE_DIR/ec2-describe-nonexistent-thing.err"* ]]
  [[ "$output" == *"$STUB_AWS_FIXTURE_DIR/ec2-describe-nonexistent-thing.json"* ]]
}

@test "uses service and operation for lookup while logging every argument" {
  printf '{"CallerIdentity": true}\n' > "$STUB_AWS_FIXTURE_DIR/sts-get-caller-identity.json"

  run aws sts get-caller-identity --output json --region us-east-1

  [ "$status" -eq 0 ]
  [ "$output" = '{"CallerIdentity": true}' ]
  grep -Fq -- 'sts get-caller-identity --output json --region us-east-1' "$STUB_AWS_CALL_LOG"
}

@test "restores PATH and removes the temporary shim" {
  original_path="$STUB_AWS_ORIGINAL_PATH"
  shim_dir="$STUB_AWS_DIR"

  stub_aws_stop

  [ "$PATH" = "$original_path" ]
  [ ! -e "$shim_dir" ]
}