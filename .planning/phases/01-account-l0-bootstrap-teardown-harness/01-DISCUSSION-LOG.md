# Phase 1: Account, L0 Bootstrap & Teardown Harness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-24
**Phase:** 1-Account, L0 Bootstrap & Teardown Harness
**Areas discussed:** Account & region, Teardown sweep design, Terraform state bootstrap, L0 layer
boundary, Cost guardrails & OIDC scoping, Repository layout & conventions

**Mode note:** The operator was unavailable when the gray-area selection form was presented. Per
autopilot rules the agent auto-selected all six areas and chose the recommended option for every
question, grounding each choice in `.planning/research/`. The "Selected" column below therefore
records the *agent's* choice, not the operator's. Items marked ⚠ in CONTEXT.md still need operator
confirmation.

---

## Account & Region

| Option | Description | Selected |
|--------|-------------|----------|
| Manual account prerequisite, documented in a runbook | Terraform assumes it is already in the dedicated account; a human runbook covers creation, MFA, billing opt-in | ✓ |
| Terraform-managed via `aws_organizations_account` | Account vended from a payer account as code | |
| Reuse an existing shared account with tag-scoping | Cheapest to start, no new account | |

**Choice:** Manual prerequisite (D-01).
**Notes:** Account creation is slow and one-way, and it bootstraps the very credentials Terraform
needs. Reusing a shared account was rejected outright — COST-08 exists specifically so a blunt
sweep is safe, and `research/PITFALLS.md` calls the dedicated account "the single highest-leverage
structural decision for teardown confidence".

| Option | Description | Selected |
|--------|-------------|----------|
| `ap-southeast-1` (Singapore) | Matches the worked backend example in `research/ARCHITECTURE.md`; low latency from operator location | ✓ |
| `us-east-1` | All `research/PITFALLS.md` pricing figures are already in this region; cheapest rates | |
| Operator's nearest other region | — | |

**Choice:** `ap-southeast-1`, flagged ⚠ CONFIRM (D-02).
**Notes:** `us-east-1` was a genuine contender — every price in the research is already denominated
there, so choosing it would partly discharge the blocking pricing-verification flag for free. It
lost on latency, which affects every interactive session. Consequence accepted: all pricing must be
re-verified for `ap-southeast-1` in this phase (D-03), and the region is `costly` to reverse because
the state bucket name embeds it.

---

## Teardown Sweep Design

| Option | Description | Selected |
|--------|-------------|----------|
| Bash + AWS CLI v2 + `jq` | Zero runtime to pin; research supplies a working skeleton; identical invocation from `make down` and CI | ✓ |
| Python + boto3 | Better structure, real error handling, testable with pytest | |
| Go binary | Single static artifact, fastest | |

**Choice:** Bash + AWS CLI v2 + `jq` (D-05).
**Notes:** Python/boto3 was tempting for the exit-code and table-formatting logic, but it adds a
runtime and a dependency-pinning problem to the one script that must never fail to run.

| Option | Description | Selected |
|--------|-------------|----------|
| Two-layer: tag sweep + explicit per-service enumeration | Covers the `resourcegroupstaggingapi` blind spots and controller-created resources | ✓ |
| Tag sweep only | Simplest; relies on `default_tags` + controller tag propagation | |
| Per-service enumeration only | No dependence on tagging discipline | |

**Choice:** Two-layer (D-06).
**Notes:** `research/PITFALLS.md` is explicit that `resourcegroupstaggingapi` does not cover every
service and that ALB/Karpenter resources only carry project tags if propagation was configured. A
tag-only sweep is precisely the unverifiable teardown this phase exists to prevent.

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit allowlist file + `Layer=00-bootstrap` tag | Adding an immortal resource must consciously edit the allowlist | ✓ |
| Pattern-based ignore (e.g. skip anything named `tfstate-*`) | Less maintenance | |
| Hardcoded exclusion list inside the script | Fewer files | |

**Choice:** Explicit allowlist (D-07).
**Notes:** A pattern-based ignore silently grows blind spots as L0 grows — exactly the failure mode
in Pitfall 3.

| Option | Description | Selected |
|--------|-------------|----------|
| Three-way exit: 0 clean / 1 orphans / 2 script error | `make down` can distinguish dirty from broken | ✓ |
| Binary exit: 0 / non-zero | Simplest, satisfies LIFE-05 literally | |

**Choice:** Three-way (D-08).
**Notes:** LIFE-05 only requires non-zero on orphans, but collapsing "verifier is broken" into the
same code makes a broken verifier indistinguishable from a dirty account — and a silently broken
verifier is worse than none.

| Option | Description | Selected |
|--------|-------------|----------|
| Committed `test-verify-teardown.sh` that creates and deletes a real EBS volume | Repeatable on every future change to the sweep | ✓ |
| One-time manual demonstration, recorded in the phase verification | Matches the wording of success criterion 1 exactly | |

**Choice:** Committed test (D-09).
**Notes:** Success criterion 1 describes a manual demonstration; codifying it costs little and makes
the hard-gate evidence re-runnable.

---

## Terraform State Bootstrap (chicken-and-egg)

| Option | Description | Selected |
|--------|-------------|----------|
| Local backend first apply, then `init -migrate-state` | Bucket is codified; nothing created outside Terraform | ✓ |
| Create the bucket with `aws s3api` before any Terraform | Simplest; no migration step | |
| Separate throwaway `layers/-1-tfstate` with committed local state | Keeps `00-bootstrap` clean | |

**Choice:** Local-then-migrate (D-12).
**Notes:** The CLI-created option leaves one snowflake resource outside code, which LIFE-10
("a rebuild weeks later produces an identical stack") does not tolerate. Committing local state was
rejected — state in Git is a credential-leak vector.

| Option | Description | Selected |
|--------|-------------|----------|
| No `make down` path to L0; separate `make nuke-bootstrap` with typed confirmation | L0 cannot be destroyed by muscle memory | ✓ |
| No teardown target at all for L0 | Even safer | |

**Choice:** Awkward-but-present nuke target (D-15).
**Notes:** Account decommissioning is a real eventual need; making it possible but deliberately
uncomfortable beats making it impossible.

---

## L0 Layer Boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Full L0 now: state bucket, OIDC, budgets, ECR, obs bucket, SPA bucket, CloudFront | Matches `research/ARCHITECTURE.md` L0 row and LIFE-09 | ✓ |
| Minimum viable L0: state bucket + OIDC + budgets only; add the rest when first needed | Smallest Phase 1 | |
| Full L0 but with everything behind default-off feature flags | Deferred cost, code present | |

**Choice:** Full L0 now (D-16, D-17, D-18, D-19).
**Notes:** The minimal option was genuinely attractive — the obs bucket sits empty until Phase 5 and
the SPA bucket until Phase 11. It was rejected because the ROADMAP Phase 11 note is unambiguous
("CloudFront must never enter the daily loop — it lives in L0 from Phase 1") and because CloudFront
is 5–15 min to deploy / 15–45 min to delete: discovering the placement late costs a whole session.
The remaining L0 resources are near-free at rest, so carrying them early costs almost nothing.

| Option | Description | Selected |
|--------|-------------|----------|
| SSM / Secrets Manager / Cognito excluded from Phase 1 | Deferred to Phase 10 / the `20-data` layer | ✓ |
| Create empty SSM parameter hierarchy now | Pre-wires Phase 10 | |

**Choice:** Excluded (D-20).

---

## Cost Guardrails & OIDC Scoping

| Option | Description | Selected |
|--------|-------------|----------|
| One SNS topic, email subscription from a required `var.alert_email` | No address in Git; Slack subscriber addable later without touching budgets | ✓ |
| Direct email subscriber on the Budget resource | One fewer resource | |
| SNS + AWS Chatbot to Slack now | Best ergonomics | |

**Choice:** SNS topic with gitignored email (D-22), flagged ⚠ CONFIRM.
**Notes:** Chatbot/Slack deferred — not needed to satisfy COST-04 and adds a Slack workspace
dependency.

| Option | Description | Selected |
|--------|-------------|----------|
| Two roles: `plan` on `pull_request`, `apply` on `refs/heads/main` | Pre-wires Phase 3's plan-on-PR / apply-on-merge criterion | ✓ |
| One role for both | Simpler trust policy | |

**Choice:** Two roles (D-25).

| Option | Description | Selected |
|--------|-------------|----------|
| Broad apply role now, tighten in Phase 10 | Avoids turning every phase into a permissions-debugging exercise | ✓ |
| Least-privilege from day one | Correct posture immediately | |

**Choice:** Broad-now (D-26) — explicitly flagged in CONTEXT.md as a conscious temporary posture
with a `Deny` on Organizations / account-closure / billing-configuration actions.
**Notes:** This is the single decision in this phase most likely to be overridden by the operator,
and it is the one where the "learning-first" constraint cuts both ways. Recorded loudly rather than
quietly.

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit `sub` values, no wildcard; no thumbprint rotation automation | Addresses Pitfall 36 | ✓ |
| Wildcard `repo:<owner>/*` | Works for future repos in the org | |

**Choice:** Explicit `sub` values (D-24, D-27).

---

## Repository Layout & Conventions

| Option | Description | Selected |
|--------|-------------|----------|
| `layers/` + `modules/` + `scripts/` + root `COSTS.md`/`VERSIONS.md`, stubs for 10/20/30 | Phase 2's "no kubernetes provider outside 30-gitops" grep-test needs the skeleton | ✓ |
| Create each layer directory only when its phase arrives | Nothing unused in the repo | |
| Docs under `docs/` including COSTS/VERSIONS | Tidier root | |

**Choice:** Full skeleton with root-level `COSTS.md`/`VERSIONS.md` (D-28, D-29).
**Notes:** REQUIREMENTS.md references both files by bare name with no path; root placement keeps
them where that wording implies.

| Option | Description | Selected |
|--------|-------------|----------|
| Exact version pins (`= 6.66.0`) mirrored into `VERSIONS.md` | LIFE-10 demands an identical rebuild weeks later | ✓ |
| Pessimistic constraints (`~> 6.66`) | Picks up patch fixes automatically | |

**Choice:** Exact pins (D-33).
**Notes:** `~>` silently defeats the "identical stack weeks later" requirement — the one constraint
in this project that only fails long after the mistake is made.

---

## The Agent's Discretion

Because the operator was unavailable, the whole discussion ran on agent judgment. The following in
particular are low-stakes and expected to be overridden freely: sweep output formatting, script file
names, Makefile target names, the ECR lifecycle-policy image count (10), and the observability
bucket expiry window (30 days).

Conversely, these need operator input before planning proceeds far: the region (D-02), whether the
account is standalone or an Organizations member (D-04), and the alert email (D-22).

## Deferred Ideas

- `scripts/nuke.sh` / `aws-nuke` / `cloud-nuke` evaluation → Phase 2, alongside `make down`
- Least-privilege CI apply policy → Phase 10
- SSM Parameter Store parameters + External Secrets Operator wiring → Phase 10
- Secrets Manager for ≤2 genuinely rotating credentials → Phase 10
- Slack / AWS Chatbot alert subscriber → any time; one resource on the existing SNS topic
- Interface VPC endpoint default-off flag → Phase 2, with the VPC
- Cost Explorer per-layer attribution dashboard → polish; criterion 4 only requires attribution be
  possible
