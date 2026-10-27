---
phase: 02-ephemeral-infrastructure-drain-scripts
verified: 2026-10-26T10:00:37Z
status: passed
score: 4/5 roadmap success criteria verified; SC4 accepted by operator on static evidence (2026-10-26)
covered_files:
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-01-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-01-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-02-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-02-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-03-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-03-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-04-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-04-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-05-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-05-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-06-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-06-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-07-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-07-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-08-PLAN.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-08-SUMMARY.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-CONTEXT.md
  - .planning/phases/02-ephemeral-infrastructure-drain-scripts/02-VALIDATION.md
  - COSTS.md
  - Makefile
  - VERSIONS.md
  - layers/10-infra/README.md
  - layers/10-infra/eks.tf
  - layers/10-infra/karpenter.tf
  - layers/10-infra/nat.tf
  - layers/10-infra/outputs.tf
  - layers/10-infra/variables.tf
  - layers/10-infra/versions.tf
  - layers/10-infra/vpc.tf
  - sh/cloud-nuke-project.yml
  - sh/doctor.sh
  - sh/down.sh
  - sh/drain-ingress.sh
  - sh/drain-nodes.sh
  - sh/drain-pvcs.sh
  - sh/lifecycle-common.sh
  - sh/nuke-project.sh
  - sh/up.sh
  - sh/verify-teardown.sh
  - tests/fixtures/aws/phase2-lifecycle-sequences.json
  - tests/helpers/stub-aws.bash
  - tests/phase2_lifecycle.bats
  - tests/static_contracts.bats
  - tests/verify_teardown_exclusions.bats
covered_digest: "v1:sha256:f719f68d51cb923118aeff1c2ff050759ef604b451f25e4968f76e3146fbfa7e"
behavior_unverified: 1
overrides_applied: 4
behavior_unverified_items:
  - truth: "SC4 — a pod receives an IP from a /20 private subnet, data-store subnets have no default route, and egress traverses the fck-nat ENI, surviving instance replacement"
    test: "After make up, schedule a pod (tolerating CriticalAddonsOnly) and read its IP; inspect intra route tables; terminate the fck-nat instance, wait for the ASG replacement, and re-run an egress check from a pod"
    expected: "Pod IP in 10.42.16.0/20 or 10.42.32.0/20; intra route tables have only the local route; the private 0.0.0.0/0 routes still target the same ENI and egress works after replacement"
    why_human: "Pod IP assignment and routing across instance replacement are runtime behavior; the 2026-10-26 run did not exercise them and no test can observe them offline"
human_verification:
  - test: "Live network checks for SC4 / NET-01 / NET-02 / NET-03 (see behavior_unverified_items)"
    expected: "Pod IP from a /20 private subnet; no intra default route; fck-nat egress survives instance replacement"
    why_human: "Requires a live cluster and an instance replacement; not exercised in the single acceptance round-trip"
  - test: "Accept or revert the fck-nat instance type: nat.tf uses t4g.micro, while ROADMAP SC4, NET-03 and the COSTS.md leakage table say t4g.nano"
    expected: "Either an override/requirement text update accepting t4g.micro (and repricing COSTS.md, open review WR-02) or nat.tf reverted to t4g.nano"
    why_human: "Intentional deviation (the operator chose t4g.micro); only the operator can accept the contract change"
  - test: "Accept or revert the kubectl pin: v1.37.1 is three minors ahead of the EKS 1.34 API server, outside the Kubernetes skew policy; Plan 02-04 requires a client compatible with EKS 1.34"
    expected: "Override recorded for Plan 02-04's kubectl truth, or the pin moved to a v1.34/v1.35 client"
    why_human: "Documented as an operator choice in VERSIONS.md and the L1 README; the live drains worked with it, but supported compatibility is a policy decision"
  - test: "Acknowledge the Plan 02-08 prohibition 'No live Phase 2 AWS operation may begin unless Phase 1 verification status is passed'"
    expected: "Operator confirms the 2026-10-14/15 live mutations were explicitly authorized while Phase 1 was human_needed (Phase 1 is now passed after the 2026-10-26 scope change)"
    why_human: "Judgment-tier prohibition; the record shows it was knowingly bypassed under user authorization, so it cannot be auto-passed"
  - test: "(Optional, non-gating) Live ALB-kill demonstration for SC3: create a standalone internal ALB in the L1 VPC, run make down, and watch stage 2 keep polling until the ARN is absent"
    expected: "Stage 2 does not complete while the ALB exists; it completes only after describe-load-balancers stops returning it, or fails before any destroy"
    why_human: "The polling invariant is proven by a passing fixture test; the live demonstration named in the criterion was not run"
---

# Phase 2: Ephemeral Infrastructure & Drain Scripts Verification Report

**Phase Goal:** The operator can stand up and completely destroy the full ephemeral infrastructure layer within the wall-clock budget, with zero orphans — before a single line of application code exists.
**Verified:** 2026-10-26T10:00:37Z
**Status:** human_needed
**Re-verification:** No — initial verification

Authoritative operator decisions applied (2026-10-26): the hard gate is **one** clean round-trip (was two); the `make down` limit is **25 minutes / 1500s** (was 15 min / 900s); Plan 02-07 Cloud Nuke recovery is accepted as **report-only**. Plan truths in 02-06 and 02-08 that still say 900s, 15 minutes, or "two consecutive" are read as superseded by these decisions.

## Operator Acceptance (2026-10-26)

The operator accepted the human-verification items and directed Phase 2 to close:

1. SC4 live network behavior (pod IP from a `/20` subnet, routing surviving fck-nat replacement) is accepted on static and log evidence without live observation.
2. Instance-type mismatch resolved by reverting `layers/10-infra/nat.tf` to `t4g.nano`, matching NET-03, SC4 and `COSTS.md`.
3. kubectl v1.37.1 (three minors ahead of EKS 1.34) is accepted; it worked in the live round-trip and is documented in `VERSIONS.md`.
4. Live AWS operations on 2026-10-14/15 that ran while Phase 1 was `human_needed` are acknowledged as user-authorized.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | `make up` reaches a healthy EKS 1.34 cluster in ≤20 min; `make down` reaches a verified-empty account in ≤25 min; both times logged in `COSTS.md` | ✓ VERIFIED | `/tmp/r1-up.log`: `Apply complete! Resources: 88 added`, then `[ready]` for cluster, node group, vpc-cni, kube-proxy, coredns, eks-pod-identity-agent. `/tmp/r1-down.log`: `Successful teardown timing: total=1162s verifier_exit=0`. `COSTS.md` records up 908s (≤1200) and down 1162s (≤1500). `kubernetes_version = "1.34"` in [eks.tf](../../../layers/10-infra/eks.tf). Deadline wired: Makefile `timeout --signal=TERM --kill-after=5s 1500s bash sh/down.sh`; `LC_DEADLINE_SECONDS=1500`. Note: the 908s is an external operator measurement — `up.sh` prints only readiness time (`11s`), not total wall-clock. |
| 2 | One `make up` → `make down` round-trip on an empty cluster ends with `verify-teardown.sh` exit 0 | ✓ VERIFIED | Down log ends `verify-teardown: account is CLEAN for the wired classes.` / `clean` / `verifier_exit=0`. 30-gitops and 20-data were confirmed absent (empty cluster). The verifier's new stale-tag-index skip is fail-closed: it skips an ARN only if the service API returns NotFound/terminated/Deleted, and test `tag scan ignores an ARN only when its service API reports it gone` covers live, gone, and AccessDenied cases. |
| 3 | `make down` runs the named ordered steps, each drain polling to an AWS-confirmed terminal state (ALB-kill demonstration) | ✓ VERIFIED | Live log shows `[1/8]`…`[8/8]` in the required order (Argo → Ingress → NodePools → PVCs → destroy 30 → 20 → 10 → verify). The README reconciles the roadmap's "seven" steps with eight actions (Argo preparation is action 1). The polling invariant is proven by passing tests `Ingress drain waits for ELBv2 load balancers and target groups to disappear` (pending → absent, 2 polls), `NodePool drain waits…`, and the first-failed-drain tests (`a failed NodePool/PVC drain stops make down before Terraform destroy`, `a permanent ELBv2 error…prevents destroy`). The live ALB-kill demonstration was not run; it is listed as an optional human item. |
| 4 | Pod IP from a `/20` private subnet; data-store subnets have no default route; egress via the fck-nat `t4g.nano` ENI, surviving instance replacement | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Static: private subnets `10.42.16.0/20`, `10.42.32.0/20`; VPC CNI uses node subnets (no custom networking). Intra subnets have no route; the static test asserts no `intra_route_table_ids` wiring. The up log creates only `aws_route.public_internet_gateway[0]` and `module.fck_nat.aws_route.main["az_a"/"az_b"]`, so no intra default route was created. fck-nat module routes use `network_interface_id = aws_network_interface.main.id` (persistent ENI, `ha_mode = true`). **Mismatch:** [nat.tf](../../../layers/10-infra/nat.tf) uses `instance_type = "t4g.micro"` (asserted by static_contracts), not `t4g.nano`. Pod IP and survival across replacement were not observed live. |
| 5 | `grep -r 'provider "kubernetes"\|provider "helm"' layers/` finds nothing outside `30-gitops` | ✓ VERIFIED | Zero matches in layer source (`--exclude-dir=.terraform` → exit 1). The literal command does match four files under gitignored `layers/10-infra/.terraform/modules/*/examples/` (vendored upstream examples, not loaded by the layer). `versions.tf` declares no kubernetes/helm provider. |

**Score:** 4/5 truths verified (1 present, behavior-unverified)

### Plan must-haves (additional)

| Plan | Truth | Status | Evidence |
|---|---|---|---|
| 02-01 | Down runs eight named actions and ends with the verifier; unknown cluster never reaches destroy; empty rerun idempotent | ✓ VERIFIED | Live log; Bats `a present infrastructure state fails closed…`, `an unknown state lookup fails closed…` pass |
| 02-02 | Single `make up` gates on cluster/node group/4 add-ons ACTIVE; EBS CSI excluded | ✓ VERIFIED | [up.sh](../../../sh/up.sh) `wait_for_active`; live `[ready]` lines; no EBS CSI add-on in eks.tf |
| 02-02 | Endpoint limited to operator CIDRs; failed apply preserved, no auto-retry | ✓ VERIFIED | `endpoint_public_access_cidrs = var.operator_cidrs` with validation rejecting `0.0.0.0/0`; Bats `make up preserves a failed apply without retry or destroy` |
| 02-03 | Karpenter IAM, node role, interruption queue, EventBridge rules in Terraform | ✓ VERIFIED | [karpenter.tf](../../../layers/10-infra/karpenter.tf); up log creates `aws_sqs_queue.this[0]`, five `aws_cloudwatch_event_rule`s, pod identity association |
| 02-04 | Drains report done only on AWS terminal absence; cluster state classified; API errors ≠ absence | ✓ VERIFIED | [lifecycle-common.sh](../../../sh/lifecycle-common.sh) `lc_init` maps only `ResourceNotFoundException` to ABSENT; fixture tests pass |
| 02-04 | kubectl pinned to a client compatible with EKS 1.34 | ? UNCERTAIN | Pin is v1.37.1 (doctor, VERSIONS.md), three minors ahead, outside skew policy; documented as an operator choice; live drains worked. Human decision requested. |
| 02-05 | Sequence-fixture harness; first-failed-drain tests | ✓ VERIFIED | `STUB_AWS_SEQUENCE_SCENARIO` fixtures; 122/122 Bats pass |
| 02-06 | Single fixed deadline, no override; timings only for successful runs | ✓ VERIFIED (1500s per decision) | Makefile + `LC_DEADLINE_SECONDS=1500` (readonly); Bats checks the exact `1500s` timeout invocation; `report_successful_timing` only on verifier exit 0 |
| 02-07 | Manual, report-only, Project-tag-scoped recovery never called from `make down` | ✓ VERIFIED (report-only accepted) | 02-07-SUMMARY: "accepted: 2026-10-26 … no type is deletable"; down.sh has no nuke call |
| 02-08 | One clean round-trip within 20/25 min, verifier 0 | ✓ VERIFIED | See SC1/SC2 |
| 02-08 | Standalone ALB live poll; live network/fck-nat replacement checks | ⚠️ not run live | Routed to human verification |
| 02-08 | No application code | ✓ VERIFIED | `git ls-files` has no `.java/.kt/.go/.py/.ts/.js`, `pom.xml`, or `src/main` outside tooling dirs |

### Prohibitions

| Plan | Prohibition | Tier | Disposition |
|---|---|---|---|
| 02-01/04/06 | No Terraform destroy after failed/unknown drain or deadline | test | Enforced; destroy-call-log assertions pass |
| 02-01 | Daily teardown never destroys 00-bootstrap | test | Enforced; `_destroy-layer` allowlist is `10-infra\|20-data\|30-gitops` |
| 02-06 | No per-run deadline override | test | Enforced; fixed `1500s` literal, readonly constant |
| 02-07 | Recovery never auto-invoked, never deletes untagged | test | Enforced; report-only, no deletable types |
| 02-08 | No live Phase 2 AWS op unless Phase 1 passed | judgment | **Flagged — human review.** Live mutations ran 2026-10-14/15 under explicit user authorization while Phase 1 was `human_needed`; Phase 1 is now `passed` after the 2026-10-26 scope change |
| 02-08 | No app source before the clean round-trip | judgment | Holds — no application source exists |

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `layers/10-infra/vpc.tf` | 2-AZ VPC, /20 private, intra, gateway + opt-in interface endpoints | ✓ VERIFIED | Pinned vpc v6.7.3; `enable_interface_endpoints` default `false` |
| `layers/10-infra/nat.tf` | fck-nat ENI egress | ✓ VERIFIED (type mismatch) | fck-nat v1.6.1, `ha_mode`, ENI routes; `t4g.micro` ≠ spec `t4g.nano` |
| `layers/10-infra/eks.tf` | EKS 1.34, tainted on-demand system group, pinned add-ons | ✓ VERIFIED | eks v21.26.0; `CriticalAddonsOnly` NO_SCHEDULE; 4 add-ons with exact `addon_version`, `most_recent = false` |
| `layers/10-infra/karpenter.tf` | AWS-side Karpenter | ✓ VERIFIED | Live-created queue and rules |
| `sh/up.sh` | Single-attempt up with health gate | ✓ VERIFIED | Writes kubeconfig on success |
| `sh/down.sh` + `sh/lifecycle-common.sh` | Ordered, fail-closed, deadline-bound teardown | ✓ VERIFIED | Live run exit 0 |
| `sh/drain-{ingress,nodes,pvcs}.sh` | AWS-terminal-state polling drains | ✓ VERIFIED | ELBv2 / EC2 / EBS predicates; fixture-tested |
| `COSTS.md` | Measured timings | ✓ VERIFIED (formatting defect) | Values present; the `make down` data row is joined onto the separator row (`…\|---\|\| 2026-10-26 \|…`), so it does not render as a table row |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Makefile:down` | `sh/down.sh` | GNU timeout 1500s | WIRED | Live and Bats |
| `sh/down.sh` | `sh/verify-teardown.sh` | `make -s verify-teardown`, exit preserved | WIRED | Live `verifier_exit=0` |
| `sh/down.sh` | `_destroy-layer` | Make-owned init, S3 state probe, `-refresh=false` destroy | WIRED | Live 773s destroy of 10-infra |
| `Makefile:up` | `sh/up.sh` → `_init-layer`/`_apply-layer` | `infra/terraform.tfstate` | WIRED | Live 88 resources |
| `nat.tf` | private route tables | `route_tables_ids` → `aws_route.main` on ENI | WIRED | Live route creation |
| `drain-ingress.sh` | ELBv2 APIs | `describe-load-balancers`/`describe-target-groups` filtered by VPC | WIRED | Live stage 2: "AWS confirms no load balancers or target groups in vpc-042f238b451295ce2" |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| Drains | Residual IDs | Live AWS describe calls via `lc_aws_json` | Yes | FLOWING (live) |
| Verifier | Findings | AWS service APIs + tagging API, gone-check per ARN | Yes | FLOWING (live clean) |
| Timing | Stage seconds | Bash `SECONDS` in down.sh | Yes | FLOWING; stages sum to 854s of 1162s — ~308s of preflight (doctor + three S3 state probes) is not itemized in COSTS.md |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full test suite | `bats tests` | 122 passed, 0 failed, 0 skipped | ✓ PASS |
| Shell lint | `shellcheck sh/*.sh` | exit 0 | ✓ PASS |
| L1 Terraform | `terraform -chdir=layers/10-infra validate` | valid, exit 0 | ✓ PASS |
| Formatting | `terraform fmt -recursive -check layers` | exit 0 | ✓ PASS |
| SC5 grep (source only) | `grep -rln … layers/ --exclude-dir=.terraform` | no matches | ✓ PASS |
| Live up/down | operator logs `/tmp/r1-up.log`, `/tmp/r1-down.log` (read only) | 88 added, all ACTIVE; down 1162s, verifier clean | ✓ PASS (operator-run) |

No `make up`/`make down`, Terraform apply/destroy/plan, or AWS-mutating command was run during this verification.

### Probe Execution

No phase-declared `probe-*.sh` files. Skipped, not applicable.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| LIFE-01 | 02-02, 02-08 | ✓ SATISFIED | up 908s ≤ 1200s |
| LIFE-02 | 02-01, 02-06, 02-07, 02-08 | ✓ SATISFIED | down 1162s ≤ 1500s |
| LIFE-03 | 02-01, 02-04–02-08 | ✓ SATISFIED | Ordered eight actions, live |
| LIFE-04 | 02-01, 02-04, 02-05, 02-06, 02-08 | ✓ SATISFIED | Terminal-state polling; fixture-proven; live drains confirmed absence |
| LIFE-06 | 02-01, 02-06, 02-08 | ✓ SATISFIED | One clean round-trip (gate reduced 2026-10-26) |
| NET-01 | 02-02, 02-03, 02-08 | ? NEEDS HUMAN | /20 subnets present; pod IP not observed |
| NET-02 | 02-02, 02-03, 02-08 | ✓ SATISFIED (static + apply log) | No intra route created |
| NET-03 | 02-02, 02-03, 02-08 | ? NEEDS HUMAN | ENI routing wired; `t4g.micro` vs `t4g.nano`; replacement not observed |
| NET-04 | 02-02, 02-03 | ✓ SATISFIED | S3 + DynamoDB gateway endpoints on private route tables |
| NET-05 | 02-02, 02-03 | ✓ SATISFIED | Default-off flag; interface endpoint rate in COSTS.md |
| NET-07 | 02-02, 02-03 | ✓ SATISFIED | Deterministic `cluster_name = var.project`; ELB and Karpenter discovery tags |
| EKS-01 | 02-02, 02-03 | ✓ SATISFIED | `1.34`, module v21.26.0 |
| EKS-02 | 02-02–02-04 | ✓ SATISFIED (Phase 2 scope) | On-demand, tainted system group; controller workloads come with GitOps in Phase 4 |
| EKS-04 | 02-03 | ✓ SATISFIED | Live queue + EventBridge rules |
| EKS-08 | 02-02, 02-03 | ✓ SATISFIED | 4 pinned add-ons incl. Pod Identity Agent |
| OWN-02 | 02-02–02-04 | ✓ SATISFIED | No kubernetes/helm provider in L1 |

All 16 Phase 2 requirement IDs are claimed by at least one plan; none orphaned.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `COSTS.md` | 227 | `make down` data row joined onto the separator line | ⚠️ Warning | Timing row does not render; data still present |
| `COSTS.md` | ~157 | Leakage table models NAT as `t4g.nano` ($3.07/mo) while nat.tf uses `t4g.micro` (open review WR-02) | ⚠️ Warning | NAT cost understated |
| `sh/doctor.sh` / `VERSIONS.md` | 5 / 24 | kubectl v1.37.1 vs EKS 1.34 (outside skew) | ⚠️ Warning | Documented operator choice |
| `sh/up.sh` | end | Prints readiness seconds only, not total `make up` wall-clock | ℹ️ Info | 908s depends on external timing |
| `Makefile` | `_destroy-layer` | Destroys with `-refresh=false` and placeholder `operator_cidrs` `192.0.2.1/32` | ℹ️ Info | Faster, but drift is caught only by the verifier (which ran clean) |
| `sh/lifecycle-common.sh` | — | Review WR-01 (cross-process `SECONDS` origin) | ℹ️ Info | Drains are sourced in `( … )` subshells, which keep `SECONDS`; the outer GNU timeout is authoritative |

No TBD/FIXME/XXX debt markers (only `mktemp` `XXXXXX` templates).

### Human Verification Required

#### 1. Live network checks (SC4, NET-01/02/03)

**Test:** After `make up`, run a pod tolerating `CriticalAddonsOnly` and read its IP; check intra route tables; terminate the fck-nat instance, wait for the ASG replacement, and re-check pod egress and the private route targets.
**Expected:** Pod IP inside `10.42.16.0/20` or `10.42.32.0/20`; intra tables have only `local`; `0.0.0.0/0` still targets the same ENI and egress works after replacement.
**Why human:** Runtime and replacement behavior; not exercised in the single acceptance round.

#### 2. fck-nat instance type mismatch

**Test:** Decide between `t4g.micro` (current nat.tf, chosen during acceptance) and `t4g.nano` (ROADMAP SC4, NET-03, COSTS.md).
**Expected:** Override plus text/cost update, or a revert.
**Why human:** Contract change.

#### 3. kubectl skew

**Test:** Accept v1.37.1 against EKS 1.34 or move to v1.34/v1.35.
**Expected:** Override for Plan 02-04's kubectl truth, or a pin change.
**Why human:** Policy decision; it worked live but is outside upstream support.

#### 4. Phase 1 precondition prohibition (Plan 02-08)

**Test:** Acknowledge that the live work on 2026-10-14/15 ran under explicit authorization before Phase 1 passed.
**Expected:** Recorded acknowledgement.
**Why human:** Judgment-tier prohibition that was knowingly bypassed.

#### 5. (Optional) Live ALB-kill demonstration (SC3)

**Test:** Create a standalone internal ALB in the L1 VPC and run `make down`.
**Expected:** Stage 2 keeps polling until the ARN is absent, or fails before any destroy.
**Why human:** The fixture test proves the invariant; the live demo was not run.

Suggested overrides if the deviations are accepted:

```yaml
overrides:
  - must_have: "egress traverses the fck-nat t4g.nano ENI"
    reason: "Operator chose t4g.micro; the persistent-ENI routing contract is unchanged"
    accepted_by: "<operator>"
    accepted_at: "<ISO timestamp>"
  - must_have: "kubectl is pinned to a client version compatible with EKS 1.34 before a drain command is used"
    reason: "Operator pinned v1.37.1; live drains succeeded; revert if lifecycle commands misbehave"
    accepted_by: "<operator>"
    accepted_at: "<ISO timestamp>"
```

### Gaps Summary

No blocking gaps. Under the 2026-10-26 operator decisions, the phase goal is met: one live round-trip finished within budget (up 908s, down 1162s), `make down` ran its ordered fail-closed sequence, the verifier returned clean, and no application code exists. The remaining items are a live-only network criterion (SC4), two intentional deviations needing sign-off (t4g.micro, kubectl skew), a flagged judgment-tier prohibition, and two documentation defects in `COSTS.md` (broken table row; stale `t4g.nano` pricing).

---

_Verified: 2026-10-26T10:00:37Z_
_Verifier: the agent (gsd-verifier)_
