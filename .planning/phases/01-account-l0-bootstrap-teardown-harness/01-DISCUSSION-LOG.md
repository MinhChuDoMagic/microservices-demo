# Phase 1: Account, L0 Bootstrap & Teardown Harness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-24
**Phase:** 1-Account, L0 Bootstrap & Teardown Harness
**Areas discussed:** Account & region, Account isolation, CI apply role scope, `nuke.sh` timing,
CloudFront & L0 contents, Teardown sweep design, Repository layout & conventions

**Session note:** An earlier run of this command auto-decided all areas because the operator was
unavailable. This session is the operator's review of that output — six areas were reopened and
several auto-decisions were overturned. Where a choice reverses the earlier auto-decision, it is
marked **↺ OVERTURNED**.

---

## Account & Region

| Option | Description | Selected |
|--------|-------------|----------|
| `ap-southeast-1` (Singapore) | Latency; accept a full regional pricing re-verification | |
| `us-east-1` (N. Virginia) | Cheapest; all research pricing already denominated here, discharges the blocking research flag faster | ✓ |
| `ap-northeast-1` (Tokyo) | — | |
| `ap-southeast-2` (Sydney) | — | |

**Choice:** `us-east-1` — **↺ OVERTURNED** (auto-decision was `ap-southeast-1`).
**Notes:** The auto-decision weighted interactive-session latency; the operator weighted the
research flag and cost. Concrete benefit: `research/PITFALLS.md` §"1.1 The Silent-Accrual Inventory"
figures now apply directly instead of needing regional translation, materially shrinking Phase 1's
blocking pricing-verification task.

| Option | Description | Selected |
|--------|-------------|----------|
| Member account under an existing AWS Organization | Consolidated billing via a payer | |
| Brand-new standalone account | Own payment method | |
| New Organization with this as first member | Isolation plus consolidated billing | |
| Existing standalone personal account, not in an Organization | Already exists, own payment method | ✓ |

**Choice:** Existing standalone personal account, no Organization.
**Notes:** Free-text answer, not one of the offered options. This materially changed the phase —
see the next section. Planning consequence: the Cost Anomaly Detection monitor is a plain account
monitor rather than `LINKED_ACCOUNT`-dimensional, and no `aws_organizations_*` resources or data
sources appear anywhere.

**Alert email:** supplied, to be carried in gitignored tfvars only.

---

## Account Isolation (raised by the agent, not pre-planned)

**Why it was raised:** the operator's answer above conflicted with COST-08 ("dedicated AWS account,
isolating spend and making a blunt sweep script safe"). The conflict is load-bearing rather than
pedantic: the sweep's blind-spot layer enumerates ALBs, EC2 instances, available EBS volumes,
unassociated EIPs and log groups **account-wide**, because controller-created orphans do not carry
project tags. On an account holding unrelated resources, that produces false positives, weakens the
zero-spend Budget into a drifting "baseline + $5", makes the $1 anomaly threshold fire on normal
variance, and makes Phase 2's `nuke.sh` permanently unsafe to run.

| Option | Description | Selected |
|--------|-------------|----------|
| Create a new dedicated account | Keeps COST-08 intact literally | |
| Create an Organization, personal account as payer | Isolation plus consolidated billing | |
| Reuse the personal account — it's effectively empty | Account-wide blunt sweep stays safe | ✓ |
| Reuse and accept a tag/VPC-filtered sweep | Amend COST-08, document reduced confidence | |

**Choice:** Reuse; account confirmed **effectively empty** (nothing running, near-zero bill).
**Notes:** This satisfies COST-08's *intent* — the blunt sweep remains safe — without a literal new
account. The filtered-sweep option was the dangerous one and was correctly avoided: filtering
reintroduces exactly the blind spots the two-layer sweep exists to eliminate.
**Mitigation added to CONTEXT.md (D-04):** planning must run the sweep as a pre-flight baseline
inventory *before* provisioning anything, with anything pre-existing going onto the allowlist — and
must escalate rather than silently widen the allowlist if the inventory turns up more than expected.

---

## CI Apply Role Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Broad now + Phase 10 task to generate a real policy from CloudTrail via IAM Access Analyzer | Empirical, not guessed | ✓ |
| Broad now, tighten by hand in Phase 10 | The original auto-decision | |
| Least-privilege from day one | Accept debugging cost as part of the learning | |
| Service-scoped (ec2/eks/iam/s3/logs) but broad within each | Middle ground | |

**Choice:** Broad now, with an explicit CloudTrail-driven generation task in Phase 10 — **↺ refined**
(auto-decision was broad-then-tighten-by-hand).
**Notes:** Least-privilege-from-day-one was the option most aligned with the project's learning-first
constraint, and it was genuinely on the table. It lost on failure mode: a hand-guessed policy for
EKS + Karpenter + ALB controller fails at minute 18 of a 20-minute `make up` on a missing
`iam:PassRole`, which burns a practice session rather than teaching anything. Generating the policy
from observed CloudTrail activity converts a guessing exercise into a measurement — arguably more
instructive than either extreme. The deferral is now a committed task rather than an intention.

---

## `nuke.sh` Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 2, alongside `make down` | Verifier first, remediation second | ✓ |
| Phase 1, minimal tag/VPC-scoped force-delete | Written right after the verifier passes | |
| Phase 1, adopt cloud-nuke/aws-nuke | Don't hand-roll it | |

**Choice:** Phase 2 — confirms the auto-decision.
**Notes:** Reopened because the confirmed-empty account made a force-delete script safe to own
earlier than originally assumed. The operator held the line on sequencing discipline. Accepted cost,
recorded in CONTEXT.md D-14: a wedged first `make up` in Phase 2 has no nuke available yet.

---

## CloudFront & L0 Contents

| Option | Description | Selected |
|--------|-------------|----------|
| Write the L0 module now, gate behind `var.enable_spa` defaulting false | Layer placement honoured, no dangling resource | |
| Create now with a placeholder origin | The original auto-decision; literal reading of the ROADMAP note | |
| Defer the code entirely to Phase 11, document that it belongs in L0 | — | ✓ |

**Choice:** Defer to Phase 11 — **↺ OVERTURNED** (auto-decision created it in Phase 1).

| Option | Description | Selected |
|--------|-------------|----------|
| All six ECR repos now via `for_each` | Ready for Phase 3 | |
| Module now, empty services list by default | — | |
| Defer to Phase 3 entirely | — | ✓ |

**Choice:** Defer to Phase 3 — **↺ OVERTURNED**.

| Option | Description | Selected |
|--------|-------------|----------|
| Observability bucket now, 30-day expiry | Empty until Phase 5 | |
| Defer to Phase 5 | — | ✓ |

**Choice:** Defer to Phase 5 — **↺ OVERTURNED**.

**Notes on all three:** The auto-decision read the ROADMAP Phase 11 note ("CloudFront must never
enter the daily loop — it lives in L0 from Phase 1") as an instruction about *timing*. The operator
read it as an instruction about *layer placement*, which is the better reading — LIFE-09's actual
requirement is that these resources never enter the daily loop, and living in L0 achieves that
regardless of which phase creates them. Net effect: Phase 1's L0 shrinks to state bucket + OIDC +
cost guardrails, which is a materially smaller and safer first phase, with fewer allowlist entries
in an account the sweep has not yet been proven against. Phases 3, 5, and 11 each extend the same
L0 layer rather than creating their own.

---

## Teardown Sweep Design

| Option | Description | Selected |
|--------|-------------|----------|
| Target region + global pass for IAM/CloudFront/S3 | Fast; the original auto-decision | |
| Target region + global + cheap all-regions check on expensive types only (EC2, EKS, ALB, RDS, EIP) | Catches stray-region orphans for a handful of API calls | ✓ |
| All enabled regions, everything | Thorough but slow on every teardown | |

**Choice:** Three-tier scope — **↺ refined**.
**Notes:** The full all-regions sweep was rejected on wall-clock grounds — `make down` has a
15-minute budget and the sweep is step 7. Tier 3 buys the cases that actually cost money.

| Option | Description | Selected |
|--------|-------------|----------|
| Human-readable table + JSON artifact on disk | Auditable | ✓ |
| Human-readable table only | Simplest; the original auto-decision | |
| JSON only, formatted by jq at the call site | — | |

**Choice:** Dual output — **↺ refined**.
**Notes:** Motivated by Phase 2's hard gate ("two consecutive zero-orphan round-trips") — a
machine-readable artifact makes that auditable rather than remembered.

| Option | Description | Selected |
|--------|-------------|----------|
| `make down` step 7 + manual `make verify-teardown` | As designed | |
| Also a scheduled GitHub Actions run alerting if the account is dirty | Catches the session you forgot to tear down | ✓ |

**Choice:** Add a scheduled CI sweep — **↺ NEW**, not in the auto-decision at all.
**Notes:** Addresses the single most expensive mistake available in this project — a session left
running overnight. Costs nothing extra in permissions: the read-only `gha-terraform-plan` role from
D-27 already suffices, so the scheduled workflow needs no new IAM.

**Unchanged from the auto-decision and not reopened:** bash + AWS CLI v2 + `jq` (D-06), the
two-layer tag + blind-spot structure (D-07), the explicit allowlist (D-09), the three-way exit
contract (D-10), and the committed `test-verify-teardown.sh` failure proof (D-13).

---

## Repository Layout & Conventions

| Option | Description | Selected |
|--------|-------------|----------|
| Create all four layer dirs now, 10/20/30 as `versions.tf` + backend only | Phase 2's grep-test has something to grep | ✓ |
| Create each layer dir when its phase arrives | Nothing unused in the repo | |

**Choice:** Stubs now — confirms the auto-decision.
**Notes:** Worth noting the tension with the L0 decision above — the operator deferred *resources*
but kept *structure*. That is a coherent line: structure is free and settles contracts (state keys,
the grep-test), whereas resources cost money, delete slowly, and need allowlist entries.

| Option | Description | Selected |
|--------|-------------|----------|
| Partial config — one shared `backend.hcl`, Makefile passes `-backend-config` | DRY; `init` needs the wrapper | ✓ |
| Full backend block per layer | Duplicated bucket/region; bare `terraform init` works | |

**Choice:** Partial config — **↺ NEW** (the auto-decision assumed a per-layer block).
**Wrinkle surfaced during discussion:** the bucket name is `tfstate-<account-id>-<region>`, derived
at apply time, so `backend.hcl` cannot be committed with a literal value. Resolved in CONTEXT.md
D-16: `make bootstrap` applies with a local backend, writes `backend.hcl` from the apply output,
then re-inits with `-migrate-state`. `backend.hcl` is gitignored with a committed `.example`.

| Option | Description | Selected |
|--------|-------------|----------|
| Gitignored tfvars + committed `.example` + a `make doctor` prerequisite check | Fails with an actionable message, not a Terraform stack trace | ✓ |
| Gitignored tfvars + committed `.example` | The original auto-decision | |
| `TF_VAR_` env vars from a gitignored `.envrc` | — | |

**Choice:** Add `make doctor` — **↺ refined**.
**Notes:** `make doctor` validates AWS CLI v2, credential validity **and the expected account ID**,
`jq`, Terraform version against `.terraform-version`, and required tfvars. The account-ID check is
the cheapest available guard against running this against the wrong account — which matters more
than usual given the account is a personal one being reused.

**Unchanged and not reopened:** root-level `COSTS.md`/`VERSIONS.md` (D-30), `default_tags` with a
load-bearing `Layer` key (D-34), Makefile as sole entry point (D-35), exact version pins mirrored
into `VERSIONS.md` (D-36).

---

## The Agent's Discretion

Left to the agent: sweep table formatting, the JSON artifact's schema and filename, script and
Makefile target names, the ECR lifecycle image count and observability bucket expiry when those
phases arrive, and the cron schedule for the scheduled sweep.

## Deferred Ideas

- `scripts/nuke.sh` / `cloud-nuke` evaluation → Phase 2, alongside `make down`
- ECR repositories → Phase 3, into the L0 layer
- Observability S3 bucket → Phase 5, into the L0 layer
- SPA bucket + CloudFront → Phase 11, into the L0 layer
- CloudTrail/IAM-Access-Analyzer-generated least-privilege CI apply policy → Phase 10
- SSM Parameter Store parameters + External Secrets Operator wiring → Phase 10
- Secrets Manager for ≤2 genuinely rotating credentials → Phase 10
- Slack / AWS Chatbot alert subscriber → any time; one resource on the existing SNS topic
- Interface VPC endpoint default-off flag → Phase 2, with the VPC
- Cost Explorer per-layer attribution dashboard → polish; criterion 4 only requires attribution be
  possible
