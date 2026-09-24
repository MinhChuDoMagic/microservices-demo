# Phase 1: Account, L0 Bootstrap & Teardown Harness - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Mode:** Auto-decided — the operator was unavailable during discussion. Every decision below was
selected by the agent from the recommended option, grounded in `.planning/research/`. Decisions
marked **⚠ CONFIRM** depend on facts only the operator holds (AWS account topology, region, email)
and must be validated before or during planning.

<domain>
## Phase Boundary

This phase delivers an isolated, cost-guardrailed AWS account containing exactly one Terraform
layer — `layers/00-bootstrap`, the immortal layer — plus a teardown verifier that is proven able to
fail before anything exists to tear down.

**In scope:** dedicated AWS account prerequisites, S3 remote state with native `use_lockfile`
locking, the four-layer directory skeleton, `default_tags` cost attribution, zero-spend Budget +
Cost Anomaly Detection, GitHub Actions OIDC federation with branch-scoped trust, near-free/
slow-to-delete L0 resources (ECR, S3 buckets, CloudFront), and `scripts/verify-teardown.sh` with a
committed test that proves it exits non-zero on a real orphan.

**Out of scope (later phases):** VPC, EKS, node groups, drain scripts, `make up`/`make down`
(Phase 2); service code and CI build pipelines (Phase 3); SSM parameters and least-privilege
tightening (Phase 10); the SPA itself (Phase 11).

**Hard gate:** `verify-teardown.sh` must exist and be demonstrably capable of failing before
Phase 2 provisions anything.

</domain>

<decisions>
## Implementation Decisions

### Account & Region

- **D-01:** The practice account is a **manual prerequisite, never Terraform-managed**. No
  `aws_organizations_account` resource, no account vending. Terraform assumes it is already running
  inside the dedicated account. A short `docs/RUNBOOK-account-setup.md` records the manual steps
  (account creation, root MFA, IAM Identity Center or admin user, billing/Cost Explorer opt-in,
  cost-allocation tag activation) so the account itself is reproducible by a human, not by code.
  Rationale: account creation is slow, one-way, and bootstraps the very credentials Terraform needs.
  — **Reversibility:** one-way — the account is the trust anchor for every role, bucket name, and
  budget; moving to a different account means re-bootstrapping L0 from scratch.
- **D-02:** ⚠ CONFIRM — Region is **`ap-southeast-1` (Singapore)**, single region, declared once as
  `var.region` with that default in every layer's `variables.tf`. Chosen to match the worked example
  in `research/ARCHITECTURE.md` Decision 2 and for latency from the operator's location.
  — **Reversibility:** costly — the state bucket name embeds the region, the entire pricing model
  (`COSTS.md`) is region-specific and would need re-verification, and existing state would need a
  cross-region migration.
- **D-03:** The blocking research flag is discharged **in this phase**: all AWS unit pricing is
  verified against the chosen region's published rates and recorded in `COSTS.md` before the budget
  numbers are committed. Prices that could not be authoritatively sourced are recorded as estimates
  with that label, not silently averaged.
- **D-04:** ⚠ CONFIRM — Cost Explorer, Budgets, and Cost Anomaly Detection are enabled **on this
  account directly**, not via a payer account. If the account is in fact an Organizations member,
  the anomaly monitor becomes `LINKED_ACCOUNT`-dimensional and billing data may only be visible from
  the payer — planning must branch on this answer.

### Teardown Sweep Design

- **D-05:** `scripts/verify-teardown.sh` is **Bash + AWS CLI v2 + `jq`**, `set -euo pipefail`, a
  single file. Not Python/boto3. Rationale: zero runtime to install or version-pin, identical
  invocation from `make down` and from CI, and `research/PITFALLS.md` §Pitfall 3 already supplies a
  working skeleton to start from.
- **D-06:** The sweep is **two-layered**, both layers always run:
  1. **Tag layer** — `resourcegroupstaggingapi get-resources` filtered on `Project`.
  2. **Blind-spot layer** — explicit per-service API enumeration for controller-created and
     untagged resources. Must cover exactly the LIFE-05 list: ALBs, target groups, controller-created
     security groups (`k8s-*`), EC2 instances, available EBS volumes, manual snapshots, unassociated
     Elastic IPs, available ENIs, and CloudWatch log groups.
  Rationale: `resourcegroupstaggingapi` does not cover every service, and ALB/Karpenter resources
  only carry project tags if propagation was configured — a tag-only sweep is exactly the
  unverifiable teardown this phase exists to prevent.
- **D-07:** Immortal resources are excluded by an **explicit allowlist, not a blanket ignore.** L0
  resources carry `Layer=00-bootstrap` and are additionally named in a committed allowlist file
  (`scripts/teardown-allowlist.txt`). Anything alive that is neither tagged `Layer=00-bootstrap` nor
  on the allowlist is a failure. Rationale: adding a new immortal resource must be a conscious act
  that edits the allowlist; a pattern-based ignore silently grows blind spots.
  — **Reversibility:** costly — the allowlist contract is consumed by `make down` from Phase 2 on
  and by CI; changing its shape later means touching every caller.
- **D-08:** **Three-way exit contract:** `0` = clean, `1` = orphans found (prints a table grouped by
  orphan class with ARN/ID and the class's usual cause), `2` = script or credential error. Rationale:
  `make down` must distinguish "the account is dirty" from "the verifier is broken" — collapsing
  both into non-zero makes a broken verifier look like a dirty account.
- **D-09:** The failure proof is a **committed, repeatable test**, not a one-time manual
  demonstration: `scripts/test-verify-teardown.sh` creates one untagged 1 GiB `gp3` EBS volume,
  asserts exit code `1`, deletes the volume, asserts exit code `0`, and cleans up on trap. This
  script is the evidence artifact for the Phase 1 hard gate and for success criterion 1.
- **D-10:** The sweep is **region-scoped to `var.region` plus a global pass** for genuinely global
  services (IAM, CloudFront, S3). Rationale: a region-only sweep misses a globally-created orphan; a
  full all-regions sweep costs minutes of API calls every teardown.
- **D-11:** `scripts/nuke.sh` (the Layer-4 force-delete remediation from `research/PITFALLS.md`) is
  **deferred to Phase 2**. This phase verifies teardown; it does not remediate it. Building the nuke
  before the verifier inverts the phase's whole premise.

### Terraform State Bootstrap (chicken-and-egg)

- **D-12:** The state bucket is **created by Terraform with a local backend, then migrated.**
  `layers/00-bootstrap` creates its own versioned, SSE-encrypted, public-access-blocked S3 bucket on
  a first apply with no backend block; the backend block is then enabled and
  `terraform init -migrate-state` moves `bootstrap/terraform.tfstate` into the bucket it just
  created. Rationale: no CLI-created snowflake resource outside code — the bucket is codified and
  reproducible, which LIFE-10 requires.
  — **Reversibility:** one-way in practice — once real state lives in the bucket, re-bootstrapping
  means a manual state export/import.
- **D-13:** Bucket name is `tfstate-<account-id>-<region>`, derived at apply time from
  `aws_caller_identity` and `var.region` — never hardcoded, never committed with a literal account
  ID. State keys follow `research/ARCHITECTURE.md` Decision 2 exactly: `bootstrap/`, `infra/`,
  `data/`, `gitops/terraform.tfstate`.
- **D-14:** **S3 bucket versioning is the only state-recovery mechanism** and is documented as such
  in `layers/00-bootstrap/README.md`, with a copy-pasteable
  `aws s3api list-object-versions` → `get-object` recovery sequence. The local
  `terraform.tfstate.backup` left behind by the migration is gitignored and explicitly not treated
  as a backup strategy.
- **D-15:** `00-bootstrap` **has no path into the daily loop.** No `make down` target touches it.
  A separate, deliberately awkward `make nuke-bootstrap` target requiring a typed confirmation
  string exists only for account decommissioning.
  — **Reversibility:** one-way — destroying L0 destroys the state for every other layer.

### L0 Layer Boundary — what exists after Phase 1

- **D-16:** `layers/00-bootstrap` contains, and only contains: the S3 state bucket, the GitHub OIDC
  provider and CI roles, the Budget and Cost Anomaly Detection monitor plus their SNS topic, ECR
  repositories, the observability S3 bucket, and the SPA S3 bucket + CloudFront distribution.
  Matches `research/ARCHITECTURE.md` Decision 2's L0 row and LIFE-09.
- **D-17:** **CloudFront and the SPA bucket are created now, in Phase 1**, with a placeholder
  origin and no content — honouring the ROADMAP Phase 11 note that CloudFront must never enter the
  daily loop. Configuration: **OAC** (not the legacy feature-frozen OAI), `PriceClass_100`, and
  `custom_error_response` mapping 403/404 → `/index.html` for SPA routing.
  — **Reversibility:** costly — a CloudFront distribution takes 5–15 min to deploy and 15–45 min to
  delete; discovering in Phase 11 that it belongs in L0 would cost a full session.
- **D-18:** ECR repositories are created via `for_each` over a `var.services` list seeded with the
  six Milestone-1 services, each with `scan_on_push = true`, `image_tag_mutability = IMMUTABLE`, and
  a lifecycle policy retaining the last 10 images. Rationale: daily rebuilds accumulate images
  indefinitely otherwise, and that storage charge is invisible until it is not.
- **D-19:** The observability S3 bucket is created now (Tempo/Loki backing, per the "S3 rather than
  EBS" decision) with a lifecycle rule expiring objects after 30 days. Empty until Phase 5.
- **D-20:** **Not** in L0 in Phase 1: SSM parameters (deferred to Phase 10 with External Secrets
  Operator), Secrets Manager (deferred; ≤2 genuinely rotating credentials later), and Cognito
  (Phase 2's `20-data` layer per the layer table).
- **D-21:** CloudWatch log groups created by this phase are **declared explicitly in Terraform with
  `retention_in_days = 1`.** Rationale: `research/PITFALLS.md` Pitfall 4 — implicit log groups
  default to never-expire and outlive `terraform destroy`. Establishing the convention in L0 makes
  it the pattern every later layer copies.

### Cost Guardrails & OIDC Scoping

- **D-22:** ⚠ CONFIRM — All cost alerts route through **one SNS topic** (`cost-alerts`) with an
  email subscription taking its address from a required `var.alert_email` — no default, no committed
  value, supplied via gitignored tfvars. Both the Budget and the anomaly subscription publish there.
  Rationale: a single channel, no email address in Git, and a Slack/Chatbot subscriber can be added
  later without touching the budget resources.
- **D-23:** **Two budgets, not one:** a monthly `COST` budget at the $5 idle ceiling with
  notifications at 50/80/100% of *forecasted* spend plus 100% of *actual*; and a Cost Anomaly
  Detection monitor with an `ABSOLUTE_VALUE` threshold of **$1** at `DAILY` frequency. Rationale:
  COST-04 specifies both, and default anomaly thresholds are tuned for enterprise spend and will
  never fire at this scale.
- **D-24:** OIDC trust is scoped by **explicit `sub` claim values, never a wildcard**:
  `repo:<owner>/<repo>:ref:refs/heads/main` and `repo:<owner>/<repo>:pull_request`, with
  `aud = sts.amazonaws.com` asserted via `StringEquals`. Owner/repo come from variables, not
  hardcoded. Rationale: Pitfall 36 — a `repo:owner/*` trust policy lets any repo in the org assume
  the role.
- **D-25:** **Two CI roles, not one:** `gha-terraform-plan` (read-only plus state read/lock),
  assumable only from `pull_request`; and `gha-terraform-apply` (broad), assumable only from
  `refs/heads/main`. Satisfies CD-05's branch scoping and pre-wires Phase 3's "plan on PR, apply on
  merge" success criterion.
  — **Reversibility:** costly — every GitHub Actions workflow references these role ARNs by name;
  splitting or renaming later touches all of them.
- **D-26:** The apply role is **deliberately broad in Phase 1** — administrator-equivalent with an
  explicit `Deny` on Organizations, account-closure, and billing-configuration actions. Tightening
  to least privilege is deferred to Phase 10. Rationale: an over-tight CI policy this early converts
  every phase into a permissions-debugging exercise instead of an AWS one. **Flagged for revisit —
  this is a conscious, temporary posture, not an oversight.**
- **D-27:** The GitHub OIDC provider is created once in L0 with url
  `https://token.actions.githubusercontent.com` and client ID `sts.amazonaws.com`. A thumbprint is
  supplied to satisfy the API but is documented in-code as ignored by AWS's own trust store — **do
  not build thumbprint rotation automation.** Rationale: thumbprint-rotation cron jobs are a
  well-known source of phantom CI outages and are no longer necessary.

### Repository Layout & Conventions

- **D-28:** Directory layout, established now because every later phase inherits it:
  ```
  Makefile
  COSTS.md                     # measured wall-clock + real spend (COST-09)
  VERSIONS.md                  # every pinned provider/module version (LIFE-10)
  docs/RUNBOOK-account-setup.md
  layers/00-bootstrap/ 10-infra/ 20-data/ 30-gitops/    # 10/20/30 are empty stubs in Phase 1
  modules/
  scripts/verify-teardown.sh
  scripts/test-verify-teardown.sh
  scripts/teardown-allowlist.txt
  .github/workflows/
  ```
  `COSTS.md` and `VERSIONS.md` sit at the repo root — they are referenced by ID in REQUIREMENTS.md
  without a path, and root placement keeps them discoverable.
- **D-29:** `10-infra`, `20-data`, and `30-gitops` exist as **empty stub directories with only a
  `versions.tf` and backend block** after Phase 1. Rationale: the state-key contract and the
  "no `kubernetes`/`helm` provider outside `30-gitops`" grep-test from Phase 2 both need the
  skeleton to exist.
- **D-30:** **No committed `*.tfvars` with account-specific values.** Each layer ships a
  `terraform.tfvars.example`; the real `terraform.tfvars` is gitignored. Region and project name
  carry defaults in `variables.tf` so the example file only contains genuinely operator-specific
  values (`alert_email`, `github_owner`, `github_repo`).
- **D-31:** `default_tags` is set in **every** layer's provider block from a shared locals
  convention: `Project`, `Layer`, `ManagedBy`, `Environment`. `Layer` is load-bearing — it is what
  `verify-teardown.sh` uses to separate immortal from ephemeral.
  — **Reversibility:** costly — renaming a tag key forces an update across every resource in the
  account and re-baselines both the sweep and Cost Explorer attribution history.
- **D-32:** The Makefile is the single entry point. Phase 1 targets only: `bootstrap`,
  `verify-teardown`, `test-verify-teardown`, `fmt`, `validate`. `up` and `down` are added in
  Phase 2, not stubbed here.
- **D-33:** Terraform version pinned via `.terraform-version` **and** `required_version`; all
  provider and module versions pinned to **exact** versions (`= 6.66.0`, not `~> 6.66`) and mirrored
  into `VERSIONS.md`. Rationale: LIFE-10 requires a rebuild weeks later to produce an identical
  stack — `~>` silently defeats that.

### The Agent's Discretion

Because the operator was unavailable, the following were resolved by the agent and are open to
override without rework cost: sweep output formatting, script file names, Makefile target names,
the exact lifecycle-policy image count (10), and the observability-bucket expiry window (30 days).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Teardown & orphan classes
- `.planning/research/PITFALLS.md` §"Pitfall 3" — the four-layer verification approach, the working
  `verify-teardown.sh` skeleton, and the tag-propagation caveats for ALB controller and Karpenter.
  This is the primary source for D-05 through D-10.
- `.planning/research/PITFALLS.md` §"Pitfall 4" — CloudWatch log-group never-expire default; source
  for D-21.
- `.planning/research/PITFALLS.md` §"Priority Ranking" and §"Pitfall-to-Phase Mapping" — confirms
  pitfalls 2, 3, 8, 36 are this phase's responsibility.
- `.planning/research/ARCHITECTURE.md` §"Decision 3 — Teardown choreography" — the complete orphan
  class table (what creates each orphan, why it is not in state, what it blocks). The sweep must
  cover every row.

### Terraform layering & state
- `.planning/research/ARCHITECTURE.md` §"Decision 2 — Terraform layering: 4 layers, not 5" — the
  authoritative L0/L1/L2/L3 contents table, state keys, the S3 backend block with `use_lockfile`,
  and the verified version pins (Terraform 1.16.4, `hashicorp/aws` 6.66.0, VPC 6.7.3, EKS 21.26.0,
  fck-nat 1.6.1). Source for D-12, D-13, D-16, D-33.

### Phase contract
- `.planning/ROADMAP.md` §"Phase 1" — goal, the five success criteria, the hard gate, and the
  blocking research flag on AWS unit pricing.
- `.planning/ROADMAP.md` §"Phase 11" note — "CloudFront must never enter the daily loop … it lives
  in L0 from Phase 1"; source for D-17.
- `.planning/REQUIREMENTS.md` — COST-01, COST-04, COST-05, COST-08, COST-09, LIFE-05, LIFE-07,
  LIFE-08, LIFE-09, LIFE-10, CD-05 (lines 16–37, 72). LIFE-05 in particular enumerates the exact
  resource types the sweep must check.
- `.planning/PROJECT.md` §"Constraints" and §"Key Decisions" — the S3-native-locking amendment, the
  no-long-lived-credentials rule, the ≤$5/month idle ceiling, and the learning-first tiebreaker.

### Cost model
- `.planning/research/PITFALLS.md` §"1.1 The Silent-Accrual Inventory" — the idle line items the
  $5/month ceiling must survive; figures are `us-east-1` and are explicitly flagged as needing
  regional re-verification, which is this phase's blocking research task.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
None — the repository is greenfield. It contains only `README.md`, `AGENTS.md`, `.planning/`, and
GSD tooling under `.github/`. There is no `layers/`, no `modules/`, no `scripts/`, no `Makefile`,
and no CI workflow. Every file in this phase is a first-of-its-kind.

### Established Patterns
No code patterns exist yet. The patterns this phase *establishes* — four-layer state keys,
`default_tags` with a load-bearing `Layer` key, exact version pinning, gitignored tfvars, the
Makefile as sole entry point — become the constraints every subsequent phase inherits. Planning
should treat them as conventions being authored, not discovered.

### Integration Points
- `scripts/verify-teardown.sh` is consumed by `make down` step 7 from Phase 2 onward — its exit
  contract (D-08) and allowlist format (D-07) are public interfaces, not internal details.
- The `gha-terraform-plan` / `gha-terraform-apply` role ARNs are consumed by every GitHub Actions
  workflow from Phase 3 onward.
- ECR repository URLs are consumed by the Phase 3 CI pipeline.
- The observability S3 bucket is consumed by Tempo in Phase 5 and Loki in Phase 9.
- The SPA bucket and CloudFront distribution are consumed by the Phase 11 frontend.

</code_context>

<specifics>
## Specific Ideas

- The `verify-teardown.sh` skeleton in `research/PITFALLS.md` is a genuine starting point, not an
  illustration — start from it rather than writing from scratch, then extend it to cover the full
  LIFE-05 list and the D-07 allowlist logic.
- The failure demonstration in success criterion 1 ("make it exit non-zero by manually creating a
  single untagged EBS volume") is codified as `test-verify-teardown.sh` (D-09) so it can be re-run
  on every future change to the sweep rather than being a one-time ceremony.
- `COSTS.md` starts life in this phase as the record of *verified regional pricing*; Phase 2 then
  appends measured `make up`/`make down` wall-clock times to the same file.

</specifics>

<deferred>
## Deferred Ideas

- **`scripts/nuke.sh` / `aws-nuke` / `cloud-nuke` evaluation** — teardown *remediation*, belongs in
  Phase 2 alongside `make down`. Deliberately not built before the verifier exists.
- **Least-privilege CI apply policy** — D-26 accepts a broad apply role for now; tighten in Phase 10
  alongside Pod Identity and the rest of the security hardening.
- **SSM Parameter Store parameters and External Secrets Operator wiring** — Phase 10.
- **Secrets Manager for the ≤2 genuinely rotating credentials** — Phase 10.
- **Slack / AWS Chatbot alert subscriber** — the SNS topic in D-22 makes this a one-resource
  addition later; not needed to satisfy COST-04.
- **Interface VPC endpoint default-off flag** — Phase 2, with the VPC.
- **Cost Explorer per-layer attribution dashboard** — success criterion 4 only requires that
  attribution *is possible* via `default_tags`; a saved report or dashboard is polish for later.

</deferred>

---

*Phase: 1-Account, L0 Bootstrap & Teardown Harness*
*Context gathered: 2026-09-24*
