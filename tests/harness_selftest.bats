#!/usr/bin/env bats

load 'helpers/load'

setup() {
  unset STUB_AWS_SEQUENCE_SCENARIO STUB_AWS_SEQUENCE_FIXTURE
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

@test "sequence mode advances the response for repeated AWS operations" {
  STUB_AWS_SEQUENCE_FIXTURE="$BATS_TEST_TMPDIR/sequences.json"
  export STUB_AWS_SEQUENCE_FIXTURE STUB_AWS_SEQUENCE_SCENARIO=advance
  printf '%s\n' '{"advance":{"ec2:describe-volumes":[{"json":{"Volumes":[{"VolumeId":"vol-first"}]}},{"json":{"Volumes":[{"VolumeId":"vol-second"}]}}]}}' \
    > "$STUB_AWS_SEQUENCE_FIXTURE"

  run aws ec2 describe-volumes
  [ "$status" -eq 0 ]
  [ "$output" = '{"Volumes":[{"VolumeId":"vol-first"}]}' ]

  run aws ec2 describe-volumes
  [ "$status" -eq 0 ]
  [ "$output" = '{"Volumes":[{"VolumeId":"vol-second"}]}' ]
}

@test "sequence counters reset with a new per-test stub directory" {
  STUB_AWS_SEQUENCE_FIXTURE="$BATS_TEST_TMPDIR/sequences.json"
  export STUB_AWS_SEQUENCE_FIXTURE STUB_AWS_SEQUENCE_SCENARIO=reset
  printf '%s\n' '{"reset":{"ec2:describe-volumes":[{"json":{"Volumes":[{"VolumeId":"vol-first"}]}},{"json":{"Volumes":[{"VolumeId":"vol-second"}]}}]}}' \
    > "$STUB_AWS_SEQUENCE_FIXTURE"

  run aws ec2 describe-volumes
  [ "$output" = '{"Volumes":[{"VolumeId":"vol-first"}]}' ]
  stub_aws_start
  run aws ec2 describe-volumes
  [ "$status" -eq 0 ]
  [ "$output" = '{"Volumes":[{"VolumeId":"vol-first"}]}' ]
}

@test "sequence error responses preserve stderr and exit status" {
  STUB_AWS_SEQUENCE_FIXTURE="$BATS_TEST_TMPDIR/sequences.json"
  export STUB_AWS_SEQUENCE_FIXTURE STUB_AWS_SEQUENCE_SCENARIO=error
  printf '%s\n' '{"error":{"ec2:describe-volumes":[{"error":{"stderr":"AccessDeniedException: sequence fixture","exit":254}}]}}' \
    > "$STUB_AWS_SEQUENCE_FIXTURE"

  run aws ec2 describe-volumes

  [ "$status" -eq 254 ]
  [ "$output" = 'AccessDeniedException: sequence fixture' ]
}

@test "a missing scenario operation response fails closed" {
  STUB_AWS_SEQUENCE_FIXTURE="$BATS_TEST_TMPDIR/sequences.json"
  export STUB_AWS_SEQUENCE_FIXTURE STUB_AWS_SEQUENCE_SCENARIO=missing
  printf '%s\n' '{"missing":{"ec2:describe-volumes":[{"json":{"Volumes":[]}}]}}' \
    > "$STUB_AWS_SEQUENCE_FIXTURE"

  run aws ec2 describe-instances

  [ "$status" -eq 98 ]
  [[ "$output" == *'scenario=missing operation=ec2:describe-instances call=1'* ]]
  [[ "$output" == *'fail closed'* ]]
}