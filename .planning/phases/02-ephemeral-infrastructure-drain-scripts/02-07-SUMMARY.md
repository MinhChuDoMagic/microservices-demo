---
phase: 02-ephemeral-infrastructure-drain-scripts
plan: 07
subsystem: infra
tags: [cloud-nuke, bash, bats, teardown, aws]

requires:
  - phase: 02-06
    provides: Eight-action teardown sequence and verifier-backed orphan reporting
provides:
  - Separate manual make nuke-project entry point
  - Fixed positive Project tag policy and checksum-pinned Cloud Nuke v0.52.0
  - Report-only recovery scope until live per-type filtering/cascade proof is authorized
affects: [phase-02-acceptance, LIFE-02, LIFE-03]

actuals:
  tokens: 3454
  tasks: 2
  commits: 3
commits: 3
plan_head_before: cbfbb05d0f355f619f2f09410adbf369351f87b8

tech-stack:
  added: [Cloud Nuke v0.52.0 release pin; checksum-verified binary staged and used for isolated live proof]
  patterns: [fixed account/region preflight, shared preview/execution scope arguments, empty fail-closed deletion allowlist]

key-files:
  created: [sh/nuke-project.sh, sh/cloud-nuke-project.yml]
  modified: [Makefile, VERSIONS.md, tests/phase2_lifecycle.bats, tests/static_contracts.bats]

key-decisions:
  - "Keep all Cloud Nuke types report-only: the isolated EC2 test used an extra unique marker, did not validate the committed Project-only wrapper scope, and did not establish every cascade behavior."

requirements-completed: []
coverage:
  - id: D1
    description: "Separate report-only recovery command, positive Project tag contract, and down-path isolation"
    requirement: LIFE-03
    verification:
      - kind: unit
        ref: "bats tests/phase2_lifecycle.bats tests/static_contracts.bats"
        status: pass
    human_judgment: false
  - id: D2
    description: "Live tagged-target and same-type untagged-control filtering/cascade proof for any deletable type"
    requirement: LIFE-03
    verification:
      - kind: manual_procedural
        ref: "Authorized isolated EC2 fixture test; unique marker added to Project tag filter"
        status: partial
    human_judgment: true
    rationale: "Real Cloud Nuke selected and deleted one tagged EC2 fixture while preserving an untagged control, but the committed Project-only scope would also select live infrastructure and the full filter/cascade acceptance is not established."

duration: not-measured
completed: 2026-10-14
status: halted
---

# Phase 02-07: Scoped Project Recovery Summary

**A separate Cloud Nuke v0.52.0 recovery entry point is pinned and report-only; an isolated EC2 filter proof passed, but no resource type is enabled for deletion.**

## Performance

- **Duration:** Not reliably measured; the start timestamp was not captured.
- **Completed:** 2026-10-14T08:49:01Z
- **Tasks:** 2 local implementation/test tasks; live acceptance remains blocked.
- **Files modified:** 6 plan-scoped implementation and test files.

## Accomplishments

- Added a standalone `make nuke-project` target, unreachable from `make down`.
- Added fixed `us-east-1` and expected-account preflight, plus v0.52.0 version and SHA-256 checks before any future Cloud Nuke preview or execution.
- Added a positive `Project: microservices-demo` EC2 policy template. The only candidate type, `ec2`, remains report-only; the deletable list is empty and VPC is excluded.
- Encoded identical region/config/type argument vectors for preview and execution. The contract-only test performs no AWS discovery and invokes no Cloud Nuke binary.
- Preserved uncovered-resource reporting through the existing teardown verifier. Successful teardown and failed NodePool drain tests both assert that Cloud Nuke is not launched.

## Task Commits

1. **Task 1 RED: specify recovery scope contracts** - `4cc635d` (test)
2. **Task 1 GREEN: add report-only scoped recovery entry point** - `1a4a6fd` (feat)
3. **Task 2: verify recovery scope and teardown isolation** - `7f3b6dc` (test)

No plan metadata commit is included here; the user prohibited STATE/ROADMAP updates, so this summary is committed separately by itself.

## Files Created/Modified

- `Makefile` - Adds the isolated manual recovery target and help entry.
- `sh/nuke-project.sh` - Account/region and binary gates, parity contract, report-only path, and future preview/execute calls sharing one scope array.
- `sh/cloud-nuke-project.yml` - Positive Project tag filter for the report-only EC2 candidate.
- `VERSIONS.md` - Pins the official macOS arm64 v0.52.0 release checksum.
- `tests/phase2_lifecycle.bats` - Contract parity and no-invocation assertions for successful/failed teardown.
- `tests/static_contracts.bats` - Positive tag, empty deletion allowlist, checksum, and no-VPC/down-path contracts.

## Official Source Facts

- The official GitHub release is `v0.52.0`, published 2026-06-13. Its `cloud-nuke_darwin_arm64` asset reports SHA-256 `366d209ce427d25342542f4304bc1eb6987daa6561823e761336bc9edfdb710d`; this matches the release asset metadata. The checksum-verified binary was staged outside the repository for the isolated proof.
- The v0.52.0 CLI guide documents `cloud-nuke aws --dry-run` for preview and `--force` to skip confirmation. `--region`, `--resource-type`, and `--config` are accepted by `aws`; `inspect-aws` does not accept `--config`, so using `aws --dry-run` preserves the same config scope for preview and execution.
- The configuration guide documents per-resource `include.tags`; tag keys are case-sensitive and tag values are lowercased before regex matching. The `ec2` resource type is listed in the release's supported-resources matrix.
- The CLI guide documents VPC cleanup of dependent ENIs, VPC endpoints, subnets, route tables, network ACLs, and security groups. VPC is excluded.
- The tagged CLI source assigns its build-time `VERSION` to the CLI app version field, which supports the wrapper's version check.

## Deviations from Plan

None. The plan's empirical safety rule and the user's live-operations gate require all unproven types to remain report-only.

## Issues Encountered

- The GSD RED-evidence checker parses Node test summaries (`# tests`, `# pass`, `# fail`), not Bats summaries. The observed RED was an actual Bats assertion failure and is preserved as the `4cc635d` test commit; no synthetic evidence was supplied.
- The first local implementation check found Bash nounset incompatibility with empty arrays; the fixed empty string allowlist is constant and non-overridable, and the focused suites pass.

## TDD Gate Compliance

- **RED:** The targeted Bats test failed on the missing wrapper and missing Make target before implementation; commit `4cc635d`.
- **GREEN:** The implementation made the scope and isolation tests pass; commit `1a4a6fd`.
- **REFACTOR:** No separate refactor was needed.
- The SDK's automated RED classifier is not compatible with this repository's Bats output format; no claim of `RED_EVIDENCE_OK` is made.

## Verification

- `bats tests/phase2_lifecycle.bats tests/static_contracts.bats`: passed, 74 tests.
- `make test`: passed, 118 fixture/local-stub tests, including verifier tests that report unallowlisted orphan resources.
- `shellcheck sh/*.sh`: passed.
- `bash -n sh/nuke-project.sh` and contract-only scope JSON assertions: passed.
- Before the follow-up proof, no Cloud Nuke preview, AWS resource mutation, disposable resource creation, real `make nuke-project`, `make down`, `make up`, or Terraform apply/destroy was run.

## Authorized Isolated EC2 Proof (2026-10-15)

- Used checksum-verified Cloud Nuke v0.52.0 (`366d209ce427d25342542f4304bc1eb6987daa6561823e761336bc9edfdb710d`) with `--region us-east-1 --resource-type ec2 --newer-than 1h --include-tag 'Project=microservices-demo' --include-tag 'Phase2NukeProof=.+'` for both preview and execution.
- Preview listed exactly one disposable tagged target, `i-08ad82f3e1e6b80b5`; execution found one, deleted one, and reported zero failures. The untagged control, `i-040ea9890807affbd`, remained running after target deletion, then was terminated separately by exact ID as fixture cleanup.
- A fresh EC2 query confirmed both fixture instances terminated. The verifier still lists the tagged target ID in its `tagged` findings despite its terminated state; it is not among the three running EC2 findings. The reported attached EBS volume belongs to the pre-existing NAT instance, and the previously reported fixture volume ID returned `InvalidVolume.NotFound`.
- This proves the real CLI's EC2 tag selection with the unique marker and untagged control. It does **not** prove the repository's Project-only configuration is safe: the live NAT instance carries `Project=microservices-demo` and would be selected by that config. The two running EKS node-group instances do not show that Project tag in their observed tags. The proof also does not establish all EC2 cascade behavior. EC2 remains report-only and `DELETABLE_RESOURCE_TYPES` remains empty.
- Ran `AWS_PROFILE=microservices-demo AWS_REGION=us-east-1 AWS_PAGER='' make nuke-project`. The wrapper passed account/region preflight, stated it would invoke no Cloud Nuke preview or deletion, then returned verifier exit 1 for 63 findings; the tagged target's terminated instance ID is still listed in the verifier's `tagged` category. No broader infrastructure was changed.
- The EKS node group remains `CREATE_FAILED` (`NodeCreationFailure`). No `make up`, `make down`, Terraform apply/destroy, or cluster operation was run.

## Remaining Human-Gated Proof

Phase 1 remains `human_needed`; the user authorized only the isolated EC2 fixture test recorded above. No Cloud Nuke type is deletable and M3 remains unresolved. To enable a type, first establish that the committed Project-only configuration selects only intended disposable targets and same-type untagged controls remain excluded, then inspect cascade behavior and verify VPC remains excluded. The current Project-only EC2 filter would include the live NAT instance, so widening the deletion allowlist is unsafe. Local stubs/contracts establish argument construction only; they are not empirical proof. Until the scope is safe, run the existing verifier for uncovered-resource reports and handle findings explicitly.

`LIFE-02` and `LIFE-03` are not marked complete by this summary.

## Next Phase Readiness

Plan 02-07 is halted at the M3 empirical proof gate. Do not claim the recovery acceptance criteria passed or advance the dependent acceptance work as though a deletable type were proven.

## Self-Check: PASSED

The summary path and all three plan-scoped task commits were verified before commit. Protected dirty planning state/cache files remain untouched.

---
*Phase: 02-ephemeral-infrastructure-drain-scripts*
*Completed: 2026-10-14*