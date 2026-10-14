#!/usr/bin/env bats

@test "make down is wired to the teardown spine" {
  makefile="$BATS_TEST_DIRNAME/../Makefile"
  down_script="$BATS_TEST_DIRNAME/../sh/down.sh"

  grep -Eq '^down:' "$makefile"
  grep -Fq 'bash sh/down.sh' "$makefile"
  [ -x "$down_script" ]
}