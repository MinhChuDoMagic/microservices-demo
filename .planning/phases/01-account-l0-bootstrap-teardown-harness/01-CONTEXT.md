# Phase 1: Account, L0 Bootstrap & Teardown Harness - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers an isolated, cost-guardrailed AWS account containing exactly one populated
Terraform layer — `layers/00-bootstrap`, the immortal layer — plus a teardown verifier that is
proven able to fail before anything exists to tear down.

**In scope:** account prerequisites and baseline inventory, S3 remote state with native
`use_lockfile` locking, the four-layer directory skeleton, `default_tags` cost attribution, a
zero-spend Budget and $1 Cost Anomaly Detection monitor, GitHub Actions OIDC federation with
branch-scoped trust, and `scripts/verify-teardown.sh` with a committed test that proves it exits
non-zero on a real orphan.

**Out of scope (later phases):** VPC, EKS, node groups, drain scripts, `make up`/`make down`,
`nuke.sh` (Phase 2); ECR repositories and service code (Phase 3); observability S3 bucket
(Phase 5); SSM parameters and least-privilege IAM tightening (Phase 10); SPA bucket and CloudFront
(Phase 11).

**Hard gate:** `verify-teardown.sh` must exist and be demonstrably capable of failing before
Phase 2 provisions anything.

</domain>

<decisions>
## Implementation Decisions

### Account & Region

- **D-01:** The practice account is a **manual prerequisite, never Terraform-managed**. No
  `aws_organizations_account` resource, no account vending. Terraform assumes it is already running
  inside the target account. `docs/RUNBOOK-account-setup.md` records the manual steps (root MFA,
  admin identity, billing/Cost Explorer opt-in, cost-allocation tag activation) so the account is
  reproducible by a human. Rationale: account setup is slow, one-way, and bootstraps the very
  credentials Terraform needs.
  — **Reversibility:** one-way — the account is the trust anchor for every role, bucket name, and
  budget.
- **D-02:** Region is **`us-east-1` (N. Virginia)**, single region, declared once as `var.region`
  with that default in every layer's `variables.tf`. Chosen over `ap-southeast-1` deliberately:
  every price in `research/PITFALLS.md` is already denominated in `us-east-1`, so this substantially
  discharges the phase's blocking pricing-verification flag, and it is the cheapest region outright.
  Latency was the cost accepted.
  — **Reversibility:** costly — the state bucket name embeds the region and `COSTS.md` is
  region-specific; changing it means a cross-region state migration and a full pricing re-verification.
- **D-03 (amended 2026-10-08):** The practice account is a **newly created, dedicated member
  account in the operator's existing AWS Organization**. Its account ID is the trust anchor for
  this project; the Organization management account and payer remain outside this repository and
  Terraform never creates or manages Organization resources. The management account controls
  organization-level Cost Explorer enablement and may restrict member access; the member account
  can view only its own cost and usage data. Consolidated payment and organization discounts may
  affect the net bill, so `COSTS.md` models published list prices and does not claim to reconcile
  the payer's final invoice. Cost Anomaly Detection uses a `DIMENSIONAL` `SERVICE` monitor in the
  member account; `LINKED_ACCOUNT` monitors remain management-account-only.
  — **Amendment:** the user explicitly replaced the prior standalone-account decision with the
  dedicated member account. Before account-dependent operations, the runbook must verify that the
  management account has enabled Cost Explorer and permits linked-account access, and that the
  member's IAM billing access is enabled. No account ID is committed.
- **D-04:** The newly created member account is **confirmed effectively empty** — nothing running,
  no resources that must survive the sweep, and near-zero project-account spend. The blunt,
  account-wide sweep in D-07/D-08 remains safe, and the Budget is measured against this member
  account's spend rather than unrelated organization accounts.
  **Planning must include a pre-flight baseline inventory** as the first task — run the sweep
  against the account *before* anything is provisioned, and put anything pre-existing that must
  survive onto the D-09 allowlist. If that inventory turns up more than expected, escalate rather
  than silently widening the allowlist.
- **D-05:** The blocking research flag is discharged **in this phase**: all AWS unit pricing is
  verified against published `us-east-1` rates and recorded in `COSTS.md` before the budget numbers
  are committed. Figures that could not be authoritatively sourced are recorded as estimates with
  that label, not silently averaged.

### Teardown Sweep Design

- **D-06:** `scripts/verify-teardown.sh` is **Bash + AWS CLI v2 + `jq`**, `set -euo pipefail`, a
  single file. Not Python/boto3. Rationale: zero runtime to install or version-pin, identical
  invocation from `make down` and from CI, and `research/PITFALLS.md` §Pitfall 3 already supplies a
  working skeleton to extend.
- **D-07:** The sweep is **two-layered**, both layers always run:
  1. **Tag layer** — `resourcegroupstaggingapi get-resources` filtered on `Project`.
  2. **Blind-spot layer** — explicit per-service API enumeration for controller-created and
     untagged resources, covering exactly the LIFE-05 list: ALBs, target groups, controller-created
     security groups (`k8s-*`), EC2 instances, available EBS volumes, manual snapshots,
     unassociated Elastic IPs, available ENIs, and CloudWatch log groups.
  Rationale: `resourcegroupstaggingapi` does not cover every service, and ALB/Karpenter resources
  only carry project tags if propagation was configured — a tag-only sweep is exactly the
  unverifiable teardown this phase exists to prevent.
- **D-08:** **Three-tier region scope**, in one pass:
  1. Full enumeration in `var.region`.
  2. Global pass for IAM, CloudFront, S3.
  3. **Cheap all-enabled-regions pass limited to the expensive resource types only** — EC2
     instances, EKS clusters, ALBs, RDS instances, Elastic IPs.
  Rationale: a region-only sweep misses a stray-region orphan from a mis-targeted console session;
  a full all-regions enumeration costs minutes on every teardown. Tier 3 buys the money-losing
  cases for a handful of API calls.
- **D-09:** Immortal resources are excluded by an **explicit allowlist, not a blanket ignore.** L0
  resources carry `Layer=00-bootstrap` and are additionally named in a committed
  `scripts/teardown-allowlist.txt`. Anything alive that is neither tagged `Layer=00-bootstrap` nor
  on the allowlist is a failure. The allowlist grows as L0 grows (see D-17) — that growth being a
  conscious, reviewable edit is the entire point.
  — **Reversibility:** costly — the allowlist contract is consumed by `make down` from Phase 2 on
  and by the scheduled CI sweep; changing its shape later touches every caller.
- **D-10:** **Three-way exit contract:** `0` = clean, `1` = orphans found, `2` = script or
  credential error. Rationale: `make down` must distinguish "the account is dirty" from "the
  verifier is broken" — collapsing both into non-zero makes a silently broken verifier look like a
  clean account, which is the worst possible failure mode for this script.
- **D-11:** **Dual output.** Human-readable table to stdout, grouped by orphan class with ARN/ID and
  the class's usual cause; **plus** a JSON artifact written to disk (`.teardown-report.json`,
  gitignored). Rationale: Phase 2's hard gate is "two consecutive zero-orphan round-trips" — a
  machine-readable artifact makes that auditable rather than remembered.
- **D-12:** **Scheduled CI sweep** in addition to on-demand use: a GitHub Actions workflow on a cron
  schedule assumes the **read-only `gha-terraform-plan` role** (D-22 — needs no new permissions),
  runs the sweep, and fails loudly if the account is dirty. Rationale: catches the session that was
  never torn down, which is the single most expensive mistake available in this project.
  Invocations: `make down` step 7 (from Phase 2), `make verify-teardown` on demand, and this cron.
- **D-13:** The failure proof is a **committed, repeatable test**, not a one-time manual
  demonstration: `scripts/test-verify-teardown.sh` creates one untagged 1 GiB `gp3` EBS volume,
  asserts exit code `1`, deletes the volume, asserts exit code `0`, and cleans up on trap. This is
  the evidence artifact for the Phase 1 hard gate and for success criterion 1.
- **D-14:** `scripts/nuke.sh` (the Layer-4 force-delete remediation from `research/PITFALLS.md`) is
  **deferred to Phase 2**, alongside `make down`. Rationale: sequencing discipline — this phase
  verifies teardown; building remediation before the verifier inverts the phase's premise. Accepted
  cost: a wedged first `make up` in Phase 2 has no nuke available yet.

### Terraform State Bootstrap (chicken-and-egg)

- **D-15:** The state bucket is **created by Terraform with a local backend, then migrated.**
  `layers/00-bootstrap` creates its own versioned, SSE-encrypted, public-access-blocked S3 bucket on
  a first apply with no backend block; the backend is then configured and
  `terraform init -migrate-state` moves `bootstrap/terraform.tfstate` into the bucket it just
  created. Rationale: no CLI-created snowflake resource outside code, which LIFE-10 requires.
  — **Reversibility:** one-way in practice — once real state lives in the bucket, re-bootstrapping
  means a manual state export/import.
- **D-16:** **`backend.hcl` is generated, not committed.** Because the bucket name is
  `tfstate-<account-id>-<region>` derived at apply time (D-18), the shared partial-backend config
  file cannot contain a literal bucket name. `make bootstrap` therefore: (1) applies `00-bootstrap`
  with a local backend, (2) writes `backend.hcl` from the apply's bucket-name output, (3) re-runs
  `terraform init -backend-config=../backend.hcl -migrate-state`. `backend.hcl` is gitignored; a
  committed `backend.hcl.example` documents its shape.
  — **Reversibility:** costly — every layer's `init` depends on this file's location and key names.
- **D-17:** Bucket name is `tfstate-<account-id>-<region>`, derived from `aws_caller_identity` and
  `var.region` — never hardcoded, never committed with a literal account ID. State keys follow
  `research/ARCHITECTURE.md` Decision 2 exactly: `bootstrap/`, `infra/`, `data/`,
  `gitops/terraform.tfstate`.
- **D-18:** **S3 bucket versioning is the only state-recovery mechanism** and is documented as such
  in `layers/00-bootstrap/README.md`, with a copy-pasteable
  `aws s3api list-object-versions` → `get-object` recovery sequence. The local
  `terraform.tfstate.backup` left by the migration is gitignored and explicitly not a backup
  strategy.
- **D-19:** `00-bootstrap` **has no path into the daily loop.** No `make down` target touches it. A
  separate, deliberately awkward `make nuke-bootstrap` requiring a typed confirmation string exists
  only for account decommissioning.
  — **Reversibility:** one-way — destroying L0 destroys the state for every other layer.

### L0 Layer Contents — deliberately minimal in Phase 1

- **D-20:** After Phase 1, `layers/00-bootstrap` contains **only**: the S3 state bucket, the GitHub
  OIDC provider and the two CI roles, and the cost guardrails (Budget, Cost Anomaly Detection
  monitor, SNS topic + email subscription). Nothing else.
- **D-21:** Everything else that *belongs to* L0 is created **by the phase that first needs it**,
  into this same layer:
  - **ECR repositories → Phase 3** (first CI build). `for_each` over a `var.services` list,
    `scan_on_push = true`, `IMMUTABLE` tags, lifecycle policy retaining the last 10 images.
  - **Observability S3 bucket → Phase 5** (Tempo). 30-day object expiry.
  - **SPA S3 bucket + CloudFront → Phase 11** (frontend). OAC not the legacy OAI,
    `PriceClass_100`, `custom_error_response` 403/404 → `/index.html`.
  **LIFE-09 governs *placement*, not *timing*** — these resources never enter the daily loop
  because they live in L0, regardless of which phase creates them. The ROADMAP Phase 11 note
  ("CloudFront … lives in L0 from Phase 1") is honoured as a layer-assignment instruction.
  Rationale: creating unused slow-to-delete resources in an account you are still learning to sweep
  adds risk and allowlist entries for zero benefit.
- **D-22:** **Not in L0 at all in Phase 1 or later-by-default:** SSM parameters (Phase 10, with
  External Secrets Operator), Secrets Manager (Phase 10, ≤2 genuinely rotating credentials),
  Cognito (`20-data` layer per the layer table).
- **D-23:** CloudWatch log groups created by this phase are **declared explicitly in Terraform with
  `retention_in_days = 1`.** Rationale: `research/PITFALLS.md` Pitfall 4 — implicit log groups
  default to never-expire and outlive `terraform destroy`. Establishing the convention in L0 makes
  it the pattern every later layer copies.

### Cost Guardrails & OIDC Scoping

- **D-24:** All cost alerts route through **one SNS topic** (`cost-alerts`) with an email
  subscription taking its address from a required `var.alert_email`, supplied via gitignored tfvars.
  Confirmed value: `chunhatminh01@gmail.com` — **supplied at apply time, never committed.** Both the
  Budget and the anomaly subscription publish there. A Slack/Chatbot subscriber can be added later
  without touching the budget resources.
- **D-25:** **Two budgets, not one:** a monthly `COST` budget at the $5 idle ceiling with
  notifications at 50/80/100% of *forecasted* spend plus 100% of *actual*; and a Cost Anomaly
  Detection monitor with an `ABSOLUTE_VALUE` threshold of **$1** at `DAILY` frequency. For the
  dedicated member account, use a `DIMENSIONAL` `SERVICE` monitor; do not configure a
  `LINKED_ACCOUNT` monitor, which is management-account-only. Cost Explorer enablement may
  automatically create the AWS-managed service monitor, so implementation must inspect existing
  monitors and import rather than collide. Rationale: COST-04 specifies both, and default anomaly
  thresholds are tuned for enterprise spend and will never fire at this scale.
- **D-26:** OIDC trust is scoped by **explicit `sub` claim values, never a wildcard**:
  `repo:<owner>/<repo>:ref:refs/heads/main` and `repo:<owner>/<repo>:pull_request`, with
  `aud = sts.amazonaws.com` asserted via `StringEquals`. Owner and repo come from variables.
  Rationale: Pitfall 36 — a `repo:owner/*` trust policy lets any repo in the org assume the role.
- **D-27:** **Two CI roles, not one:** `gha-terraform-plan` (read-only plus state read/lock),
  assumable only from `pull_request`; and `gha-terraform-apply` (broad), assumable only from
  `refs/heads/main`. Satisfies CD-05's branch scoping, pre-wires Phase 3's "plan on PR, apply on
  merge", and gives the scheduled sweep (D-12) a read-only identity for free.
  — **Reversibility:** costly — every GitHub Actions workflow references these role ARNs by name.
- **D-28:** The apply role is **broad in Phase 1** — administrator-equivalent with an explicit
  `Deny` on Organizations, account-closure, and billing-configuration actions — **and Phase 10
  carries an explicit task to replace it with a policy generated empirically from CloudTrail via IAM
  Access Analyzer**, not hand-written. Rationale: a least-privilege Terraform policy for EKS +
  Karpenter + ALB controller is genuinely hard to guess, and the failure mode is a 20-minute
  `make up` dying at minute 18 on a missing `iam:PassRole`. Deriving it from observed activity turns
  a guessing exercise into a measurement. **This is a conscious temporary posture with a scheduled
  end, not an oversight.**
- **D-29:** The GitHub OIDC provider is created once in L0 with url
  `https://token.actions.githubusercontent.com` and client ID `sts.amazonaws.com`. A thumbprint is
  supplied to satisfy the API but documented in-code as ignored by AWS's own trust store — **do not
  build thumbprint rotation automation.** Rationale: thumbprint-rotation jobs are a well-known
  source of phantom CI outages and are no longer necessary.

### Repository Layout & Conventions

- **D-30:** Directory layout, established now because every later phase inherits it:
  ```
  Makefile
  COSTS.md                     # verified us-east-1 pricing now; measured wall-clock from Phase 2
  VERSIONS.md                  # every pinned provider/module version (LIFE-10)
  backend.hcl.example          # real backend.hcl is generated + gitignored (D-16)
  docs/RUNBOOK-account-setup.md
  layers/00-bootstrap/         # populated
  layers/10-infra/             # stub
  layers/20-data/              # stub
  layers/30-gitops/            # stub
  modules/
  scripts/verify-teardown.sh
  scripts/test-verify-teardown.sh
  scripts/teardown-allowlist.txt
  .github/workflows/
  ```
  `COSTS.md` and `VERSIONS.md` sit at the repo root — REQUIREMENTS.md references both by bare name.
- **D-31:** `10-infra`, `20-data`, and `30-gitops` exist as **stub directories containing only
  `versions.tf` and backend configuration**. Rationale: Phase 2's
  `grep -r 'provider "kubernetes"\|provider "helm"' layers/` success criterion needs the skeleton to
  exist, and the state-key contract is settled once rather than four times.
- **D-32:** **Partial backend configuration** — one shared `backend.hcl` (generated per D-16),
  each layer's `terraform { backend "s3" {} }` left empty, and `terraform init` always invoked
  through the Makefile so the `-backend-config` flag is never forgotten. Rationale: bucket and
  region are declared once instead of four times; the Makefile-only-init constraint is acceptable
  because the Makefile is already the sole entry point (D-34).
- **D-33:** **No committed `*.tfvars` with account-specific values.** Each layer ships a
  `terraform.tfvars.example`; the real `terraform.tfvars` is gitignored. With region defaulted in
  `variables.tf`, the only operator-specific values are `alert_email`, `github_owner`,
  `github_repo`. **Additionally: a `make doctor` target** validates prerequisites before anything is
  applied — AWS CLI v2 present, credentials valid and pointing at the expected account, `jq`
  present, Terraform version matching `.terraform-version`, required tfvars populated — and fails
  with a specific, actionable message rather than a Terraform stack trace.
- **D-34:** `default_tags` is set in **every** layer's provider block from a shared locals
  convention: `Project`, `Layer`, `ManagedBy`, `Environment`. `Layer` is load-bearing — it is what
  `verify-teardown.sh` uses to separate immortal from ephemeral.
  — **Reversibility:** costly — renaming a tag key forces an update across every resource and
  re-baselines both the sweep and Cost Explorer attribution history.
- **D-35:** The Makefile is the single entry point. Phase 1 targets only: `doctor`, `bootstrap`,
  `verify-teardown`, `test-verify-teardown`, `fmt`, `validate`. `up` and `down` arrive in Phase 2.
- **D-36:** Terraform version pinned via `.terraform-version` **and** `required_version`; all
  provider and module versions pinned to **exact** versions (`= 6.66.0`, not `~> 6.66`) and mirrored
  into `VERSIONS.md`. Rationale: LIFE-10 requires a rebuild weeks later to produce an identical
  stack — `~>` silently defeats that, and it fails long after the mistake is made.

### The Agent's Discretion

Resolved by the agent, open to override without rework cost: sweep table formatting, the JSON
artifact's schema and filename, script and Makefile target names, the ECR lifecycle image count
(10) and observability bucket expiry (30 days) when those phases arrive, and the exact cron schedule
for the scheduled sweep.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Teardown & orphan classes
- `.planning/research/PITFALLS.md` §"Pitfall 3" — the four-layer verification approach, the working
  `verify-teardown.sh` skeleton, and the tag-propagation caveats for the ALB controller and
  Karpenter. Primary source for D-06 through D-13.
- `.planning/research/PITFALLS.md` §"Pitfall 4" — CloudWatch log-group never-expire default; source
  for D-23.
- `.planning/research/PITFALLS.md` §"Priority Ranking" and §"Pitfall-to-Phase Mapping" — confirms
  pitfalls 2, 3, 8, 36 are this phase's responsibility.
- `.planning/research/ARCHITECTURE.md` §"Decision 3 — Teardown choreography" — the complete orphan
  class table (what creates each orphan, why it is not in state, what it blocks). The sweep must
  cover every row.

### Terraform layering & state
- `.planning/research/ARCHITECTURE.md` §"Decision 2 — Terraform layering: 4 layers, not 5" — the
  authoritative L0/L1/L2/L3 contents table, state keys, the S3 backend block with `use_lockfile`,
  and verified version pins (Terraform 1.16.4, `hashicorp/aws` 6.66.0, VPC 6.7.3, EKS 21.26.0,
  fck-nat 1.6.1). Source for D-15, D-17, D-20, D-36.

### Phase contract
- `.planning/ROADMAP.md` §"Phase 1" — goal, the five success criteria, the hard gate, and the
  blocking research flag on AWS unit pricing.
- `.planning/ROADMAP.md` §"Phase 2" — the grep-test success criterion that D-31's stubs serve, and
  the two-round-trip hard gate that D-11's JSON artifact makes auditable.
- `.planning/ROADMAP.md` §"Phase 11" note — CloudFront must never enter the daily loop; interpreted
  as layer placement in D-21.
- `.planning/REQUIREMENTS.md` — COST-01, COST-04, COST-05, COST-08, COST-09, LIFE-05, LIFE-07,
  LIFE-08, LIFE-09, LIFE-10, CD-05 (lines 16–37, 72). LIFE-05 enumerates the exact resource types
  the sweep must check.
- `.planning/PROJECT.md` §"Constraints" and §"Key Decisions" — the S3-native-locking amendment, the
  no-long-lived-credentials rule, the ≤$5/month idle ceiling, and the learning-first tiebreaker.

### Cost model
- `.planning/research/PITFALLS.md` §"1.1 The Silent-Accrual Inventory" — the idle line items the
  $5/month ceiling must survive. Figures are `us-east-1`, which per D-02 is now the project's
  region, so they apply directly rather than needing regional translation.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
None — the repository is greenfield. It contains only `README.md`, `AGENTS.md`, `.planning/`, and
GSD tooling under `.github/`. There is no `layers/`, no `modules/`, no `scripts/`, no `Makefile`,
and no CI workflow. Every file in this phase is a first-of-its-kind.

### Established Patterns
No code patterns exist yet. The patterns this phase *establishes* — four-layer state keys, partial
backend config driven through the Makefile, `default_tags` with a load-bearing `Layer` key, exact
version pinning, gitignored tfvars with `make doctor` validation, explicit log-group retention —
become the constraints every subsequent phase inherits. Planning should treat them as conventions
being authored, not discovered.

### Integration Points
- `scripts/verify-teardown.sh` is consumed by `make down` step 7 from Phase 2 onward and by the
  scheduled CI sweep — its exit contract (D-10), allowlist format (D-09), and JSON schema (D-11) are
  public interfaces, not internal details.
- `backend.hcl` (D-16) is consumed by every layer's `init` from Phase 2 onward.
- The `gha-terraform-plan` / `gha-terraform-apply` role ARNs are consumed by every GitHub Actions
  workflow from Phase 3 onward, and by the scheduled sweep in this phase.
- The `00-bootstrap` layer is extended — not replaced — by Phases 3, 5, and 11 (D-21).

</code_context>

<specifics>
## Specific Ideas

- The `verify-teardown.sh` skeleton in `research/PITFALLS.md` is a genuine starting point, not an
  illustration — start from it, then extend to the full LIFE-05 list, the D-09 allowlist, the D-08
  three-tier region scope, and the D-11 dual output.
- The failure demonstration in success criterion 1 ("make it exit non-zero by manually creating a
  single untagged EBS volume") is codified as `test-verify-teardown.sh` so it re-runs on every
  future change to the sweep rather than being a one-time ceremony.
- **Run the sweep against the account before provisioning anything** (D-04). It doubles as the
  baseline inventory and as a smoke test that the script works against a real account.
- `COSTS.md` starts life as the record of verified `us-east-1` pricing; Phase 2 appends measured
  `make up`/`make down` wall-clock times to the same file.
- `make doctor` should fail on the *wrong account* specifically — comparing `sts get-caller-identity`
  against an expected account ID is the cheapest possible guard against running this against
  something else.

</specifics>

<deferred>
## Deferred Ideas

- **`scripts/nuke.sh` / `cloud-nuke` evaluation** → Phase 2, alongside `make down` (D-14).
- **ECR repositories** → Phase 3, into the L0 layer (D-21).
- **Observability S3 bucket** → Phase 5, into the L0 layer (D-21).
- **SPA bucket + CloudFront** → Phase 11, into the L0 layer (D-21).
- **CloudTrail/IAM-Access-Analyzer-generated least-privilege CI apply policy** → Phase 10 (D-28).
  This is now a committed task, not a vague intention.
- **SSM Parameter Store parameters + External Secrets Operator wiring** → Phase 10.
- **Secrets Manager for ≤2 genuinely rotating credentials** → Phase 10.
- **Slack / AWS Chatbot alert subscriber** → any time; one resource on the existing SNS topic.
- **Interface VPC endpoint default-off flag** → Phase 2, with the VPC.
- **Cost Explorer per-layer attribution dashboard** → polish; success criterion 4 only requires that
  attribution be possible.

</deferred>

---

*Phase: 1-Account, L0 Bootstrap & Teardown Harness*
*Context gathered: 2026-09-24*
