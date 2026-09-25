---
phase: 1
phase_slug: account-l0-bootstrap-teardown-harness
artifact: RESEARCH
created: 2026-09-24
region: us-east-1
requirements: [COST-01, COST-04, COST-05, COST-08, COST-09, LIFE-05, LIFE-07, LIFE-08, LIFE-09, LIFE-10, CD-05]
---

# Phase 1 Research: Account, L0 Bootstrap & Teardown Harness

> **Scope of this document.** Phase 1's roadmap entry carries a 🔬 **blocking** research
> flag on AWS unit pricing. This document discharges that flag and covers the three other
> areas the phase cannot be planned without: Terraform S3 native state locking, GitHub
> Actions OIDC federation, and the teardown sweep's enumeration coverage.
>
> Research was conducted in three parallel slices (Parts A, B, C below), each verified
> independently against primary sources. Figures that could not be authoritatively sourced
> are marked `[UNVERIFIED]` rather than estimated.

---

## Executive Summary

**The blocking pricing flag is discharged.** Every figure the existing project corpus carried
as `[UNVERIFIED]` — including the one `research/ARCHITECTURE.md` explicitly flagged as
blocking — is now resolved to HIGH confidence, verified against the **AWS Price List Bulk
API** (public, credential-free, machine-readable) rather than the JS-rendered pricing pages.

**Phase 1's own idle cost is ≈ $0.01/month** against a $5.00 ceiling — $4.99 of headroom.
Every line item in D-20's L0 layer except S3 is a hard $0.00. The $5 ceiling exists entirely
to catch Phase 2–5 leakage, not to constrain L0. COST-09 is not at risk in this phase.

**Both core version pins are verified real and current.** Terraform **1.16.4** is the current
latest stable (released 2026-09-23); `hashicorp/aws` **6.66.0** is latest. `use_lockfile`
landed in Terraform **1.10.0** and went GA in **1.11.0**, so 1.16.4 is comfortably above the
floor. `dynamodb_table` is deprecated but **not removed** — verified by grepping the v1.12
through v1.16 changelogs for a removal entry (zero hits). `research/ARCHITECTURE.md`
Decision 2 is accurate as written.

**One finding is genuinely blocking and must be resolved before the IAM roles are written**
(see F-01 below). Three more findings contradict locked decisions in `01-CONTEXT.md` and
need an explicit amendment task rather than a silent fix.

---

## Blocking Findings & Required Decision Amendments

These are the items where research contradicts a locked decision or a stated success
criterion. Each needs an explicit planning response — none should be silently absorbed.

### F-01 — BLOCKING: GitHub immutable `sub` claims break D-26 verbatim

GitHub repositories created **on or after 2026-07-15** emit an OIDC `sub` claim of the form
`repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main` — **not** the literal
`repo:OWNER/REPO:ref:refs/heads/main` that D-26 specifies. A trust policy using the D-26
literal against such a repository fails with AWS's documented error:
`Not authorized to perform sts:AssumeRoleWithWebIdentity`.

Both CI roles would be dead on arrival, and the failure surfaces only at the first CI run.

**Required planning response:** a `checkpoint:human-verify` task sequenced **before** the IAM
role tasks that runs `gh api repos/OWNER/REPO --jq .created_at` and selects the correct `sub`
shape. Part C supplies an immutable-aware `locals` block that handles both forms.
`[VERIFIED: docs.github.com/en/actions/reference/security/oidc]`

### F-02 — Success criterion 3 is not achievable as written via Cost Anomaly Detection

SC3 requires a $1 spend to raise a Cost Anomaly Detection alert **within one day**. AWS
documents **10 days of per-service history** as a hard prerequisite for CAD, plus up to 24h
of monitor warm-up and up to 24h of Cost Explorer data lag. On a genuinely empty account
(D-04) every service is "new", so CAD cannot fire inside the stated window.

**Required planning response:** add a second `aws_budgets_budget` with
`time_unit = "DAILY"` and an `ACTUAL` / `ABSOLUTE_VALUE` notification at `1`. This is
deterministic, needs no ML baseline, and satisfies SC3's *intent* on day one. Keep the CAD
monitor — it is the right long-run instrument — but record its first real firing as a
deferred observation rather than a phase-sealing criterion. **This is the single highest-value
addition research surfaced for this phase.**

### F-03 — Amend D-25: `FORECASTED` notifications cannot fire for ~5 weeks

AWS Budgets requires roughly **5 weeks of historical spend** before it will produce a
forecast. D-25 configures notifications at 50/80/100% of *forecasted* spend plus 100% of
*actual*. On a new/empty account, **three of those four notifications are inert** for the
first ~5 weeks; only the 100%-ACTUAL alert is live.

**Required planning response:** keep the forecast notifications (they become correct later),
but document the dead window in `COSTS.md` so it is not mistaken for a misconfiguration, and
rely on the F-02 daily-actual budget for early coverage.

### F-04 — Amend D-25: CAD `frequency = "DAILY"` with an SNS-only subscriber is very likely invalid

AWS documents `DAILY` anomaly summaries as **email-delivered**, while individual alerts are
what require SNS. Every `hashicorp/aws` provider example pairing `DAILY` uses `EMAIL`.
D-24's single-SNS-topic routing and D-25's `DAILY` frequency are therefore in tension.

**Required planning response:** use `frequency = "IMMEDIATE"`. This preserves D-24's
single-topic routing *and* reduces alert latency — it is strictly better for this project.

### F-05 — Amend D-03's consequence: `DIMENSIONAL` is correct, not "no dimension"

D-03 correctly concludes the monitor must not be `LINKED_ACCOUNT` (that type is
management-account-only). But the correct monitor for a standalone account is
`type = "DIMENSIONAL"` with `monitor_dimension = "SERVICE"`, not an absent dimension.

Additionally: **enabling Cost Explorer auto-creates an AWS-managed SERVICE monitor**, and the
quota is **1 SERVICE monitor per account**. A Terraform-declared monitor may collide with it.

**Required planning response:** an `aws ce get-anomaly-monitors` preflight during the
implementation task, with an import path if the managed monitor already exists.

### F-06 — Amend D-29: omit `thumbprint_list` entirely

D-29's premise — "a thumbprint is supplied to satisfy the API" — is no longer true.
`thumbprint_list` is `Optional` in `hashicorp/aws`, the provider ships a "Without A
Thumbprint" example, and AWS's own `configure-aws-credentials` README states the thumbprint
"will be ignored". Omitting it **strengthens** D-29's no-rotation-automation intent rather
than weakening it. `[VERIFIED: provider docs + aws-actions/configure-aws-credentials README]`

### F-07 — The plan role needs scoped write access to `*.tflock`

`terraform plan` acquires a state lock by default, and under `use_lockfile` that lock is a
real S3 object. A `gha-terraform-plan` role with pure `ReadOnlyAccess` **fails at lock
acquisition**. D-27 already says "read-only **plus state read/lock**" — this is the concrete
expansion of that clause: `s3:PutObject` and `s3:DeleteObject` scoped to `*.tflock`.

### F-08 — D-28's `Deny` must not cover `budgets:*` or `ce:*`

D-28 specifies an explicit `Deny` on billing-configuration actions. Taken literally that
would deny `budgets:*` and `ce:*` — which **this phase's own Terraform requires** to create
the Budget and the anomaly monitor. The apply role would be unable to apply L0.

**Required planning response:** scope the billing `Deny` to account/payment-configuration
actions (`aws-portal:ModifyPaymentMethods`, `aws-portal:ModifyBilling`,
`account:CloseAccount`, `organizations:*`) and explicitly **exclude** `budgets:*` and `ce:*`.

### F-09 — WITHDRAWN (stale): `PROJECT.md` already specifies S3 native locking

> **Corrected 2026-09-24 after live measurement during plan verification.** This finding as
> originally written was **wrong** and has been withdrawn. It is kept here rather than deleted
> because a downstream plan task was authored against its false premise.

The original claim was that `PROJECT.md` still mandates "S3 + DynamoDB state locking" and
needed an amendment task. Direct measurement shows the opposite:

- `PROJECT.md` line 21 already reads *"remote state in S3 using native `use_lockfile` locking
  plus bucket versioning"*.
- `PROJECT.md` line 136 already records *"DynamoDB state locking is deprecated in favour of S3
  native locking"* among the absorbed research corrections.
- There is **no** Out-of-Scope row excluding a DynamoDB lock table; the Out of Scope section
  contains no state-locking entry at all.

**No amendment task is required.** `PROJECT.md` and success criterion 2 already agree.

**Trap to avoid — this is the part that still matters.** `PROJECT.md` line 28 contains the
string `S3 + DynamoDB` in a completely unrelated context: *"**gateway endpoints only** (S3 +
DynamoDB, free)"*, describing free VPC **gateway endpoints**. Any verification that greps for
`S3 \+ DynamoDB` to prove DynamoDB locking is absent **will match that line and fail**, and an
executor driven to make it pass would mutate a correct VPC requirement. Any check in this area
must anchor its pattern on state-locking context, never on the bare product-name pair.

**Required planning response:** assert that the native-locking constraint is *present*, rather
than replacing text that does not exist.

### F-10 — `prevent_destroy` cannot be variable-driven, so `make nuke-bootstrap` is three problems

Terraform requires `prevent_destroy` to be a literal (*"only literal values can be used"*).
D-19's `make nuke-bootstrap` therefore cannot simply pass a flag. It must (1) edit code to
flip the literal, (2) migrate state back to a local backend first, and (3) purge every object
version and delete marker before the bucket will delete.

### F-11 — D-23 may have zero instances in Phase 1

D-23 establishes the `retention_in_days = 1` convention for CloudWatch log groups. None of
D-20's four L0 resource groups natively emit CloudWatch logs, so the convention may have **no
concrete instance** in this phase. Plan it as a documented convention (and a `make doctor` /
review check), not as a resource task that will find nothing to do.

### F-12 — Pricing correction: EKS extended support is additive

EKS extended support is **+$0.50/hr on top of the $0.10/hr base (= $0.60/hr total)**, not a
flat $0.60/hr replacement. The existing corpus states it ambiguously.

---

## Validation Architecture

How each success criterion can be validated, split by what the validation *requires*. This
section is the input to `01-VALIDATION.md`.

**Three validation tiers used below:**

| Tier | Meaning | Runs in CI? | Needs live AWS? |
|---|---|---|---|
| **T1 — Static** | Asserts on repository contents only | Yes | No |
| **T2 — Live-account automated** | Scripted assertion against a real AWS account | Yes, with OIDC role | Yes |
| **T3 — Deferred observational** | Requires elapsed real time or human observation | No | Yes |

The important structural point: **SC3 and SC4 both contain a T3 component that cannot
complete inside the phase's implementation window.** They must be planned with an automatable
T1/T2 proxy that seals the phase, plus an explicitly deferred observation recorded in
`COSTS.md`. Planning them as ordinary tasks will either stall the phase or produce a false
green.

### SC1 — `verify-teardown.sh` exits 0 clean and 1 on a real orphan

| Tier | Validation |
|---|---|
| T1 | `shellcheck scripts/verify-teardown.sh` and `bash -n` — syntax and lint, no AWS. |
| T1 | **Fixture-driven exclusion tests.** Stub the `aws` binary on `PATH` and feed recorded JSON for each orphan class. This is where the false-positive exclusions (default SGs, terminated instances, `--owner-ids self` snapshots, `RequesterManaged` ENIs) get proven — and it is the only tier that can prove them *cheaply and repeatably*. Strongly recommended; Part C supplies the per-class shapes. |
| T1 | Assert every LIFE-05 class name appears in the script (coverage grep). |
| T2 | `scripts/test-verify-teardown.sh` (D-13) — creates one untagged 1 GiB gp3 volume, asserts exit 1, deletes, asserts exit 0, cleans up on trap. This is the phase's **hard-gate evidence artifact**. Cost is a fraction of a cent. |
| T2 | Exit-code-2 path: run with deliberately invalid credentials and assert exit 2, proving D-10's three-way contract is real and a broken verifier cannot masquerade as a clean account. |

> **Design constraint surfaced by research:** the script must check its `HARD_ERROR`
> accumulator **before** its findings accumulator. Reversed, a mid-sweep credential expiry
> prints "account is CLEAN". Part C gives the accumulator/trap pattern that reconciles
> `set -euo pipefail` with "continue past individual class failures".

### SC2 — State in a versioned S3 bucket, `.tflock` appears and disappears, no DynamoDB

| Tier | Validation |
|---|---|
| T1 | `grep -r 'dynamodb_table\|dynamodb_endpoint' layers/` returns zero matches. |
| T1 | `grep -r 'use_lockfile' layers/` confirms native locking is configured. |
| T2 | `aws dynamodb list-tables` returns an empty list — proves "no DynamoDB table anywhere" against the live account, not just the code. |
| T2 | `aws s3api get-bucket-versioning` reports `Enabled`. |
| T2 | **The lock demonstration, race-free:** because versioning is on (D-18), the lock's `DeleteObject` leaves a retained object version **plus** a delete marker. `aws s3api list-object-versions --prefix bootstrap/terraform.tfstate.tflock` shows the full acquire/release lifecycle **after** the apply, and `get-object --version-id` reads back the lock JSON. **No polling loop, no timing race** — this is the reliable way to satisfy SC2's "appearing during apply and disappearing after". |

### SC3 — $1 resource raises a CAD alert within a day; zero-spend Budget configured

| Tier | Validation |
|---|---|
| T1 | Terraform declares both budgets, the CAD monitor, the CAD subscription, the SNS topic, and the SNS topic policy granting `budgets.amazonaws.com` and `costalerts.amazonaws.com`. **The topic policy is the silent-failure point** — a default SNS policy drops these publishers with no error anywhere. |
| T2 | `aws budgets describe-budgets` and `aws ce get-anomaly-monitors` / `get-anomaly-subscriptions` confirm the live configuration matches. |
| T2 | `aws sns get-topic-attributes` → assert the policy contains both service principals. |
| T2 | `aws sns list-subscriptions-by-topic` → assert the email subscription is `Confirmed`, **not** `PendingConfirmation`. Terraform cannot confirm an email subscription; a human must click the link, and Terraform will happily report success with the subscription inert. |
| **T3** | **The CAD alert actually firing.** Per F-02 this cannot occur inside the phase. Record as a deferred observation in `COSTS.md` with the date it becomes testable. |
| T2 | **Proxy that seals the phase:** the F-02 daily `ACTUAL`/`ABSOLUTE_VALUE` $1 budget is deterministic and its notification path is assertable immediately. |

### SC4 — Per-layer cost attribution in Cost Explorer; idle ≤ $5/month

| Tier | Validation |
|---|---|
| T1 | Every layer's provider block sets `default_tags` with all four keys (`Project`, `Layer`, `ManagedBy`, `Environment`). `Layer` is load-bearing for the sweep, so assert it specifically. |
| T2 | `aws resourcegroupstaggingapi get-resources --tag-filters Key=Layer,Values=00-bootstrap` returns every L0 resource — proves the tags actually landed, which `default_tags` does **not** guarantee for resources created *by* another resource. |
| T1 | `COSTS.md` contains the verified us-east-1 unit-price table and the line-item idle model from Part A. |
| **T3** | **Cost Explorer attribution against a real billing period.** Cost allocation tags are activated manually in the Billing console, take up to 24h, and **never backfill**. Attribution is therefore impossible to demonstrate on the day the resources are created. Record as a deferred observation; the manual activation itself belongs in `docs/RUNBOOK-account-setup.md` (D-01) and must be sequenced **first**, because everything created before activation is permanently unattributable. |

### SC5 — GitHub Actions assumes a repo+branch-scoped role; no long-lived keys

| Tier | Validation |
|---|---|
| T1 | Trust policies use `StringEquals` (never `StringLike`) on both `:sub` and `:aud`; no `*` appears in any `sub` value. Part C enumerates the loose-trust shapes to grep for. |
| T1 | No workflow references `aws-access-key-id` / `aws-secret-access-key`; every AWS-touching workflow declares `permissions: id-token: write`. |
| T2 | A real workflow run on `main` assumes `gha-terraform-apply`; a run from a pull request assumes `gha-terraform-plan`. |
| T2 | **The negative test is the actual proof of scoping:** a workflow on a non-`main`, non-PR ref must **fail** to assume the apply role. A positive-only test proves the role works, not that it is scoped. |
| T2 | `aws iam generate-credential-report` → assert zero users hold active access keys and the root account has none; `gh secret list` → assert no AWS credential secrets. |

---

## How to Read the Rest of This Document

The three parts below are the verbatim research slices. They contain the concrete HCL, AWS
CLI, and Bash the planner and executor should copy from.

- **Part A** — AWS unit pricing (us-east-1), the Phase 1 idle cost model, and cost guardrail
  implementation (Budgets, SNS topic policy, Cost Anomaly Detection, cost allocation tags).
- **Part B** — Terraform S3 native state locking, the bootstrap chicken-and-egg sequence,
  state bucket hardening and recovery, the layer skeleton, version pinning, and `make doctor`.
- **Part C** — GitHub Actions OIDC federation, exact trust policy shapes, Pitfall 36 failure
  modes, and the teardown sweep's per-class enumeration with false-positive exclusions.

Each part ends with its own **Gotchas & Landmines** and **Open Questions** sections. The open
questions are non-blocking unless promoted to a finding above.


---

# Part A — AWS Pricing & Cost Guardrails

## AWS Unit Pricing (us-east-1)

**Verification method.** All `[VERIFIED]` figures below were pulled **this session (2026-09-25)** from the
**AWS Price List Bulk API** — a public, credential-free, authoritative endpoint:

```bash
# Regional per-service price list (JSON)
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<SERVICE_CODE>/current/us-east-1/index.json"

# Global (non-regional) services
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<SERVICE_CODE>/current/index.json"

# EC2 is ~303 MB — stream-grep it, never download whole:
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/us-east-1/index.csv" \
  | grep -E 'NatGateway|VolumeUsage\.gp3|BoxUsage:t4g\.nano'
```

The `aws` CLI is **NOT installed** on this machine (`command -v aws` → not found), so the Pricing Query API
(`aws pricing get-products`) was unavailable; the Bulk API was used instead. `terraform` is also not installed.
Note also that `aws.amazon.com/*/pricing/` marketing pages are JS-rendered and cannot be scraped — the Bulk API is
the only machine-readable authoritative source.

### Prior-art baseline (what the existing research already asserted)

Extracted first, per instruction, from the existing corpus. Verdict column is this session's result.

| Claim in existing research | Source line | Verdict this session |
|---|---|---|
| EKS control plane `$0.10/cluster-hr` | [PITFALLS.md](.planning/research/PITFALLS.md#L55), [STACK.md](.planning/research/STACK.md#L21) | ✅ **CONFIRMED** |
| EKS extended support `$0.60/cluster-hr` | [PITFALLS.md](.planning/research/PITFALLS.md#L56) | ⚠️ **CORRECTED** — price list line is `$0.50/hr` *additional*; `$0.10 + $0.50 = $0.60` total. Net effect identical, mechanism different. |
| Interface VPC endpoint `$0.01/endpoint-ENI-hr` | [PITFALLS.md](.planning/research/PITFALLS.md#L57), [STACK.md](.planning/research/STACK.md#L326) | ✅ **CONFIRMED** |
| Public IPv4 `~$0.005/hr`, marked MEDIUM / "rate not re-confirmed" | [PITFALLS.md](.planning/research/PITFALLS.md#L63) | ✅ **NOW CONFIRMED & UPGRADED TO HIGH** — idle *and* in-use both `$0.005/hr` |
| EBS gp3 `~$0.08/GB-mo` | [PITFALLS.md](.planning/research/PITFALLS.md#L65) | ✅ **CONFIRMED** |
| CloudWatch Logs `~$0.50/GB` ingest, `~$0.03/GB-mo` storage, both MEDIUM | [PITFALLS.md](.planning/research/PITFALLS.md#L71-L72) | ✅ **CONFIRMED & UPGRADED TO HIGH** |
| ECR `$0.10/GB-mo`, MEDIUM | [PITFALLS.md](.planning/research/PITFALLS.md#L70) | ✅ **CONFIRMED & UPGRADED TO HIGH** |
| NAT Gateway `$0.045/hr + $0.045/GB`, tagged `[UNVERIFIED]` | [STACK.md](.planning/research/STACK.md#L329) | ✅ **NOW VERIFIED** |
| `t4g.nano` `~$0.0042/hr` | [STACK.md](.planning/research/STACK.md#L330) | ✅ **CONFIRMED** |
| Cross-AZ `$0.01/GB each direction`, MEDIUM | [PITFALLS.md](.planning/research/PITFALLS.md#L73) | ✅ **CONFIRMED & UPGRADED TO HIGH** (plus: first 1 GB/mo free) |
| S3 + DynamoDB state "pennies, `<$0.10`" | [PITFALLS.md](.planning/research/PITFALLS.md#L75) | ✅ **CONFIRMED** — actually `<$0.02`; and D-20 uses `use_lockfile`, so **there is no DynamoDB line at all** |
| Blanket caveat: "AWS unit pricing … **MEDIUM** … not re-verified against the pricing API this session. **Verify before committing the budget.**" | [ARCHITECTURE.md](.planning/research/ARCHITECTURE.md#L950) | ✅ **This section discharges that caveat.** |

### Verified unit pricing table

| Item | Unit | Verified price | Source + date | Confidence |
|---|---|---|---|---|
| **S3 Standard storage** (first 50 TB) | GB-month | **$0.023** | Bulk API `AmazonS3/us-east-1`, pubDate `2026-09-18` | HIGH `[VERIFIED]` |
| S3 Standard storage (next 450 TB / >500 TB) | GB-month | $0.022 / $0.021 | same | HIGH `[VERIFIED]` |
| **S3 PUT/COPY/POST/LIST** (Tier1) | request | **$0.000005** (= $0.005 per 1,000) | same | HIGH `[VERIFIED]` |
| **S3 GET + all other** (Tier2) | request | **$0.0000004** (= $0.004 per 10,000) | same | HIGH `[VERIFIED]` |
| **S3 versioning** | — | **No separate charge.** Each noncurrent version is billed as a **full independent object** at Standard storage rates — *not* a delta. | [CITED: docs.aws.amazon.com/AmazonS3/latest/userguide/versioning-workflows.html](https://docs.aws.amazon.com/AmazonS3/latest/userguide/versioning-workflows.html) — *"Normal Amazon S3 rates apply for every version of an object that is stored and transferred. Each version of an object is the entire object; it is not a diff from the previous version. Thus, if you have three versions of an object stored, you are charged for three objects."* | HIGH `[CITED]` |
| **CloudWatch Logs ingestion** (Standard class) | GB | **$0.50** | Bulk API `AmazonCloudWatch/us-east-1`, pubDate `2026-09-22`, usagetype `USE1-DataProcessing-Bytes` | HIGH `[VERIFIED]` |
| CloudWatch Logs ingestion (Infrequent Access class) | GB | $0.25 | same | HIGH `[VERIFIED]` |
| **CloudWatch Logs storage** | GB-month | **$0.03** | same, usagetype `USE1-TimedStorage-ByteHrs` | HIGH `[VERIFIED]` |
| **AWS Budgets — standard budgets** | budget-day | **$0.00, range `0–Inf`** | Bulk API `AWSBudgets/current`, pubDate `2026-09-11`, usagetype `BudgetsUsage` | HIGH `[VERIFIED]` — see ⚠️ note below |
| AWS Budgets — **action-enabled** budgets | budget-day | **$0.00 for first 62 budget-days/mo, then $0.10** | same, usagetype `ActionEnabledBudgetsUsage`; quota doc confirms *"Number of free budgets with actions per account: 2"* ([CITED](https://docs.aws.amazon.com/cost-management/latest/userguide/management-limits.html)) | HIGH `[VERIFIED]` |
| AWS Budgets — budget reports | message | $0.01 per report delivered | same | HIGH `[VERIFIED]` |
| **Cost Anomaly Detection** | — | **No offer code exists in the Price List index**; docs describe it as *"a feature within Cost Explorer"* | `[ASSUMED]` — see Open Questions Q1 | LOW |
| **Cost Explorer** — console | — | Free (enablement is free; console browsing is free) | `[ASSUMED]` — no positive price-list line; see Q1 | LOW |
| **Cost Explorer — API** (`GetCostAndUsage` etc.) | request | **$0.01** | Bulk API `AWSCostExplorer/current`, pubDate `2026-09-11`, usagetype `USE1-APIRequest` | HIGH `[VERIFIED]` |
| Cost Explorer — granular (hourly) cost data storage | 1,000 UsageRecord-months | $0.01 | same | HIGH `[VERIFIED]` |
| **SNS — Email / Email-JSON notifications** | notification | **First 1,000/month FREE**, then **$2.00 per 100,000** | Bulk API `AmazonSNS/us-east-1`, pubDate `2026-09-15`, usagetype `DeliveryAttempts-SMTP` | HIGH `[VERIFIED]` |
| SNS — API requests (incl. Publish) | request | First 1,000,000/month FREE, then $0.50/1M | same, usagetype `Requests-Tier1` | HIGH `[VERIFIED]` |
| SNS — topic existence | — | **$0.00** — no hourly/monthly charge line exists for a standard topic | `[VERIFIED: AmazonSNS/us-east-1 price list has no topic-hours line item]` | HIGH |
| **IAM roles, policies, OIDC provider, STS** | — | **$0.00** | [CITED: docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) — *"AWS Identity and Access Management (IAM), AWS IAM Identity Center and AWS Security Token Service (AWS STS) are features of your AWS account offered at no additional charge."* | HIGH `[CITED]` |
| **ECR storage** | GB-month | **$0.10** | Bulk API `AmazonECR/us-east-1`, pubDate `2026-09-11` | HIGH `[VERIFIED]` |
| ECR archive-tier storage / retrieval | GB-month / GB | $0.10 (0–150 TB) / $0.03 retrieval | same | HIGH `[VERIFIED]` |
| **EBS gp3 storage** | GB-month | **$0.08** | EC2 `index.csv`, `Last-Modified: 2026-09-24`, usagetype `EBS:VolumeUsage.gp3` | HIGH `[VERIFIED]` |
| EBS gp3 provisioned IOPS (above baseline) | IOPS-month | $0.005 | same, `EBS:VolumeP-IOPS.gp3` | HIGH `[VERIFIED]` |
| EBS gp3 provisioned throughput (above baseline) | MiBps-month | $0.04 | same, `EBS:VolumeP-Throughput.gp3` (list price stated as `40.96 per GiBps-mo` = `$0.04/MiBps-mo`) | HIGH `[VERIFIED]` |
| EBS gp3 **free baseline** | — | **3,000 IOPS + 125 MiB/s included at no charge**; only provisioning *above* this bills | `[ASSUMED]` — the price list shows the *incremental* SKUs but does not state the baseline; universally documented but not re-fetched. See Q4. | LOW |
| **EC2 `t4g.nano` on-demand, Linux, shared tenancy** | hour | **$0.0042** (= **$3.07/mo**) | EC2 `index.csv` 2026-09-24 — literal description string `"$0.0042 per On Demand Linux t4g.nano Instance Hour"` | HIGH `[VERIFIED]` |
| **Public IPv4 — in-use** | hour | **$0.005** (= **$3.65/mo**) | Bulk API `AmazonVPC/us-east-1`, pubDate `2026-09-17`, `USE1-PublicIPv4:InUseAddress` — *"$0.005 per In-use public IPv4 address per hour"* | HIGH `[VERIFIED]` |
| **Public IPv4 — IDLE (unattached EIP)** | hour | **$0.005 — IDENTICAL RATE** | same, `USE1-PublicIPv4:IdleAddress` — *"$0.005 per Idle public IPv4 address per hour"* | HIGH `[VERIFIED]` |
| Public IPv4 — contiguous BYOIP block | hour/IP | $0.008 | same, `USE1-PublicIPv4:ContiguousBlock` | HIGH `[VERIFIED]` |
| **EKS control plane** | cluster-hour | **$0.10** (= **$73.00/mo**) | Bulk API `AmazonEKS/us-east-1`, pubDate `2026-09-18`, `USE1-AmazonEKS-Hours:perCluster` | HIGH `[VERIFIED]` |
| EKS **extended support** surcharge | cluster-hour | **+$0.50** (total $0.60/hr = $438/mo) | same, `USE1-AmazonEKS-Hours:extendedSupport` | HIGH `[VERIFIED]` |
| **Interface VPC endpoint** | endpoint-ENI-hour | **$0.01** (= **$7.30/AZ/mo**) | Bulk API `AmazonVPC/us-east-1`, `USE1-VpcEndpoint-Hours` — *"$0.01 per VPC Endpoint Hour"* | HIGH `[VERIFIED]` |
| Interface VPC endpoint — data processed | GB | $0.01 (≤1 PB) / $0.006 (1–5 PB) / $0.004 (>5 PB) | same, `USE1-VpcEndpoint-Bytes` | HIGH `[VERIFIED]` |
| **Gateway VPC endpoint** (S3, DynamoDB) | — | **$0.00** — no charge line exists | `[VERIFIED: AmazonVPC/us-east-1 price list contains no gateway-endpoint SKU]` | HIGH |
| **Data transfer OUT to internet — free tier** | GB/month | **First 100 GB/month FREE, aggregated globally** | Bulk API `AWSDataTransfer/us-east-1`, pubDate `2026-09-16`, `Global-DataTransfer-Out-Bytes` | HIGH `[VERIFIED]` |
| Data transfer OUT to internet — beyond free tier | GB | **$0.090** (first 10 TB) / $0.085 / $0.070 / $0.050 | same, `DataTransfer-Out-Bytes` | HIGH `[VERIFIED]` |
| **Cross-AZ / regional data transfer** | GB | **$0.010 each direction** (= $0.02/GB round trip) | same, `DataTransfer-Regional-Bytes` — *"regional data transfer - in/out/between EC2 AZs or using elastic IPs or ELB"* | HIGH `[VERIFIED]` |
| Cross-AZ — free tier | GB/month | **First 1 GB/month free** | same, `Global-DataTransfer-Regional-Bytes` | HIGH `[VERIFIED]` |
| **NAT Gateway** | hour | **$0.045** (= **$32.85/mo**) | EC2 `index.csv` 2026-09-24, `NatGateway-Hours` — *"$0.045 per NAT Gateway Hour"* | HIGH `[VERIFIED]` |
| NAT Gateway — data processed | GB | **$0.045** | same, `NatGateway-Bytes` | HIGH `[VERIFIED]` |

> ⚠️ **AWS Budgets pricing discrepancy — read this.** The Price List Bulk API **today** reports
> `BudgetsUsage = $0.00` across the *entire* range `0–Inf`, i.e. standard (non-action) budgets appear to be
> **unlimited and free**. This contradicts the long-standing, widely-cited model of *"first 2 budgets free, then
> $0.02 per budget-day."* The `$0.02/budget-day` SKU **no longer appears in the price list at all**; the only
> non-zero budget SKU is `ActionEnabledBudgetsUsage` ($0.10/budget-day after 62 free budget-days/month), which
> lines up exactly with the documented quota *"Number of free budgets with actions per account: 2"*.
> **Practical read:** the two budgets this phase creates are **action-free COST budgets → $0.00 either way**,
> so the phase's cost model is unaffected by which model is correct. Do not propagate the `$0.02/budget-day`
> figure forward without re-checking. See Q2.

### Not applicable to this project (recorded so nobody re-researches them)

- **Route 53 public hosted zone** — `$0.50/zone/month, not prorated, charged at creation AND on the 1st`
  ([PITFALLS.md](.planning/research/PITFALLS.md#L64), [PITFALLS.md](.planning/research/PITFALLS.md#L291)). Not in
  L0 and not created by Phase 1. Re-verification deferred; the 12-hour-deletion grace rule in
  [PITFALLS.md](.planning/research/PITFALLS.md#L293) is `[ASSUMED]` and was **not** re-checked this session.
- **ALB/NLB** `$0.0225/hr` ([PITFALLS.md](.planning/research/PITFALLS.md#L60)) — Phase 4+, not re-verified.

---

## Phase 1 Idle Cost Model

**Scope (locked, D-20):** after Phase 1, `layers/00-bootstrap` contains **only** the S3 state bucket, the GitHub
OIDC provider + two CI roles, and the cost guardrails (Budget, CAD monitor, SNS topic + email subscription).
Nothing else. ([01-CONTEXT.md](.planning/phases/01-account-l0-bootstrap-teardown-harness/01-CONTEXT.md#L150))

**Usage assumptions** (stated so the arithmetic is auditable):
- ~200 Terraform backend operations/month (plan + apply + CI runs), each ≈ 4 Tier1 (PUT/LIST — incl. the
  `use_lockfile` native S3 lock object write/delete) + 6 Tier2 (GET/HEAD) requests.
- L0 `terraform.tfstate` ≈ 50 KB; versioning enabled → ~200 noncurrent versions accrue in month one ≈ **10 MB**.
- ≤ 20 alert emails/month.

| # | Line item | Driver | Rate | Monthly |
|---|---|---|---|---|
| 1 | S3 Standard storage — tfstate + all noncurrent versions | 0.010 GB | $0.023/GB-mo | **$0.0002** |
| 2 | S3 Tier1 requests (PUT/COPY/POST/LIST + lock object) | ~800 req | $0.000005/req | **$0.0040** |
| 3 | S3 Tier2 requests (GET and all others) | ~1,200 req | $0.0000004/req | **$0.0005** |
| 4 | DynamoDB state lock table | — | — | **$0.00 — does not exist.** D-20 uses S3 native `use_lockfile`, so the classic DynamoDB lock line is eliminated entirely. |
| 5 | IAM OIDC provider (`aws_iam_openid_connect_provider`) | 1 | $0.00 | **$0.00** |
| 6 | IAM roles ×2 + inline/managed policies | 2 | $0.00 | **$0.00** |
| 7 | AWS Budgets — 1 monthly COST budget, **no budget actions** | 1 budget | $0.00/budget-day | **$0.00** |
| 8 | Cost Anomaly Detection monitor + subscription | 1 + 1 | no charge line exists | **$0.00** `[ASSUMED]` |
| 9 | SNS topic (standard, unencrypted) | 1 | no topic-hours SKU | **$0.00** |
| 10 | SNS Publish API requests | ~20 | first 1M/mo free | **$0.00** |
| 11 | SNS email notification deliveries | ~20 | first 1,000/mo free | **$0.00** |
| 12 | Cost Explorer console access | — | free | **$0.00** `[ASSUMED]` |
| 13 | KMS key for SNS/S3 SSE | — | — | **$0.00 — none.** SSE-S3 (`AES256`) is free; **do not** use SSE-KMS on the SNS topic (see Gotchas — it breaks Budgets *and* costs $1/key-month). |
| | **TOTAL** | | | **≈ $0.005 — round to $0.01/month** |

**Verdict: PASSES the ≤ $5/month idle ceiling with $4.99 of headroom (99.9%).**

The Phase 1 L0 layer is, to two decimal places, **free**. Every single line except S3 is a hard `$0.00`, and S3
is half a cent. This is the correct outcome — it means the $5 ceiling exists **entirely** to catch leakage from
Phases 2–5, not to constrain L0 itself.

**Items that are explicitly $0.00:** IAM OIDC provider, IAM roles, AWS Budgets (action-free), Cost Anomaly
Detection, SNS topic, SNS publishes, SNS emails (under 1,000/mo), Cost Explorer console, gateway endpoints,
DynamoDB (absent by design).

**What the $5 ceiling actually has to absorb later** (all verified above, for the planner's forward model):

| Future leak | Rate | Monthly if left up | % of $5 ceiling |
|---|---|---|---|
| One forgotten EKS control plane | $0.10/hr | **$73.00** | **1,460%** |
| One orphaned NAT Gateway | $0.045/hr | $32.85 | 657% |
| One orphaned ALB (base) | $0.0225/hr | $16.43 | 329% |
| One interface VPC endpoint, 1 AZ | $0.01/hr | $7.30 | 146% |
| One orphaned/idle Elastic IP | $0.005/hr | **$3.65** | **73%** |
| fck-nat `t4g.nano` running 24/7 | $0.0042/hr | $3.07 | 61% |
| 10 GB of stale ECR images | $0.10/GB-mo | $1.00 | 20% |

**A single leaked idle Elastic IP consumes 73% of the entire monthly ceiling.** That one line is the strongest
argument for the teardown verifier, and the `$1` CAD threshold is calibrated almost exactly to it (an idle EIP
crosses $1 in ~8.3 days).

---

## Cost Guardrail Implementation Notes

### 1. `aws_budgets_budget` — monthly COST budget with 4 notifications

`notification` is a **repeatable block**, one per threshold. There is no list-of-thresholds form. Each block is
an independent alert with its own subscriber set.

**`subscriber_sns_topic_arns` vs `subscriber_email_addresses`:** both are `(Optional)`, but the provider requires
**at least one of the two per `notification` block**
([CITED: provider docs](https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/budgets_budget.html.markdown) —
*"Either this or `subscriber_email_addresses` is required."*). AWS caps each alert at **10 email addresses and
exactly 1 SNS topic** ([CITED: AWS Budgets best practices](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-best-practices.html)).
Since D routes everything through one SNS topic, use `subscriber_sns_topic_arns` **only** and omit the email list
— the human's email is attached once, at the topic, not four times at the budget.

```hcl
data "aws_caller_identity" "current" {}

resource "aws_budgets_budget" "l0_monthly_ceiling" {
  name         = "l0-monthly-cost-ceiling"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Count gross spend. Leaving include_credit=true (the default) lets free-tier
  # credits mask real burn — exactly the failure this budget exists to catch.
  cost_types {
    include_credit             = false
    include_refund             = false
    include_discount           = true
    include_subscription       = true
    include_other_subscription = true
    include_recurring          = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  # The topic policy MUST exist before Budgets validates the subscriber.
  depends_on = [aws_sns_topic_policy.cost_alerts]
}
```

Valid enum values, all `[CITED]` from the provider docs: `comparison_operator` ∈ {`LESS_THAN`, `EQUAL_TO`,
`GREATER_THAN`}; `notification_type` ∈ {`ACTUAL`, `FORECASTED`}; `threshold_type` ∈ {`PERCENTAGE`,
`ABSOLUTE_VALUE`}; `time_unit` ∈ {`MONTHLY`, `QUARTERLY`, `ANNUALLY`, `DAILY`}.

> 🔴 **The FORECASTED-alerts cold-start trap.** *"AWS requires approximately **5 weeks of usage data** to generate
> budget forecasts. If you set a budget to alert based on a forecasted amount, this budget alert isn't triggered
> until you have enough historical usage information."*
> ([CITED: budgets-best-practices](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-best-practices.html))
> On a genuinely-empty, brand-new account, **three of the four notifications (all the FORECASTED ones) are dead
> for roughly the first 5 weeks.** Only the 100%-ACTUAL alert can fire. The plan must not treat
> "budget created, `terraform apply` green" as "budget alerting works."

Other Budgets timing facts, all `[CITED]`: budget data *"is updated up to three times a day … typically 8–12
hours after the previous update"*; ACTUAL alerts fire **once per budget period**, FORECASTED alerts may fire
repeatedly as the forecast crosses back and forth.

### 2. The SNS topic policy trap

Two different AWS service principals publish here, and a default-policy SNS topic **silently drops both** — no
error, no `terraform apply` failure, no dead-letter. The only symptom is alerts that never arrive. AWS
Budgets' own troubleshooting confirms the failure mode: *"**Invalid SNS topic** — AWS Budgets doesn't have access
to the SNS topic. Confirm that you've allowed `budgets.amazonaws.com` the ability to publish messages to this SNS
topic, in the SNS topic's resource-based policy."*
([CITED: budgets-sns-policy](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html))

| Publisher | Service principal | Conditions required | Source |
|---|---|---|---|
| AWS Budgets | `budgets.amazonaws.com` | `aws:SourceAccount` **and** `aws:SourceArn` (`arn:aws:budgets::<acct>:*`) | [CITED: budgets-sns-policy](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html) |
| Cost Anomaly Detection | `costalerts.amazonaws.com` | **none in the canonical example** | [CITED: provider `ce_anomaly_subscription` docs](https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ce_anomaly_subscription.html.markdown) |

> ⚠️ **`aws_sns_topic_policy` REPLACES the entire policy — it does not append.** If you write only the two
> service statements, you delete the default statement that lets *your own account* `Subscribe`,
> `GetTopicAttributes`, `SetTopicAttributes`, etc. `aws_sns_topic_subscription` can then fail, and you can lock
> yourself out of administering the topic. The `__default_statement_ID` block below is **mandatory**, not
> decorative — the provider's own canonical example includes it for exactly this reason.

```hcl
resource "aws_sns_topic" "cost_alerts" {
  name = "cost-alerts"
  # DO NOT set kms_master_key_id — see Gotchas.
}

data "aws_iam_policy_document" "cost_alerts" {
  policy_id = "__default_policy_ID"

  statement {
    sid     = "AWSBudgetsSNSPublishingPermissions"
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    resources = [aws_sns_topic.cost_alerts.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid     = "AWSAnomalyDetectionSNSPublishingPermissions"
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["costalerts.amazonaws.com"]
    }
    resources = [aws_sns_topic.cost_alerts.arn]
    # Deliberately unconditioned — matches the canonical AWS/provider example.
    # Adding aws:SourceAccount here is UNVERIFIED and risks silent drops.
  }

  # MANDATORY: preserves account-owner administration of the topic.
  statement {
    sid    = "__default_statement_ID"
    effect = "Allow"
    actions = [
      "SNS:Subscribe", "SNS:SetTopicAttributes", "SNS:RemovePermission",
      "SNS:Receive", "SNS:Publish", "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes", "SNS:DeleteTopic", "SNS:AddPermission",
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_sns_topic.cost_alerts.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "cost_alerts" {
  arn    = aws_sns_topic.cost_alerts.arn
  policy = data.aws_iam_policy_document.cost_alerts.json
}
```

**Verify the policy landed:**
```bash
aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" \
  --query 'Attributes.Policy' --output text | python3 -m json.tool
```
**Prove Budgets can actually publish** (the only real test — publishing as yourself proves nothing about the
service principal):
```bash
# End-to-end smoke test: temporarily add an ABSOLUTE_VALUE ACTUAL notification at $0.01
# to the existing budget, wait for the next 8-12h Budgets refresh, confirm the email lands,
# then remove it. This is the ONLY way to validate the budgets.amazonaws.com path pre-spend.
aws budgets describe-notifications-for-budget \
  --account-id "$ACCOUNT_ID" --budget-name l0-monthly-cost-ceiling
```

### 3. `aws_ce_anomaly_monitor` + `aws_ce_anomaly_subscription`

**Monitor type for a standalone account.** The scope brief says *"`DIMENSIONAL`/`LINKED_ACCOUNT` is NOT
applicable."* That is **half right and needs correcting**: it is **`LINKED_ACCOUNT` specifically** that is
unavailable — *"Linked Accounts … **Only available in management accounts**"* — whereas the AWS-services monitor
is *"Available in both management and member accounts"*
([CITED: getting-started-ad](https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html)).
So **`monitor_type = "DIMENSIONAL"` with `monitor_dimension = "SERVICE"` IS the correct account-wide monitor**,
and is the only whole-account option short of a `CUSTOM` monitor. `monitor_dimension` valid values:
`COST_CATEGORY`, `LINKED_ACCOUNT`, `SERVICE`, `TAG` `[CITED: provider docs]`.

**`threshold` vs `threshold_expression`.** The current `hashicorp/aws` docs for `aws_ce_anomaly_subscription`
document **`threshold_expression` only** — the scalar `threshold` argument is gone
([CITED: provider main-branch docs](https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ce_anomaly_subscription.html.markdown)).
**For `hashicorp/aws` 6.x, use `threshold_expression`.** The v6 upgrade guide does *not* list this resource,
which means the removal landed **during the 5.x line**, not at the 6.0 boundary — so 6.x has only ever had
`threshold_expression`. `[VERIFIED for 6.x]` / `[ASSUMED]` on the precise 5.x version where `threshold` was dropped.

> 🔴 **`frequency = "DAILY"` + SNS-only subscriber is very likely INVALID.** AWS documents the two modes as
> mutually specialised: *"**Individual alerts** — … **These notifications require an Amazon SNS topic**"* and
> *"**Daily summaries** — An email notification with a daily summary … **At least one email recipient must be
> specified.**"* ([CITED: getting-started-ad](https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html)).
> The provider's own examples mirror this exactly: every `DAILY` example uses `type = "EMAIL"`, and the **only**
> SNS example uses `frequency = "IMMEDIATE"`.
> **This directly conflicts with the locked decision (DAILY frequency + single SNS topic).** Two ways out:
> 1. **Recommended — switch to `frequency = "IMMEDIATE"`.** It is SNS-native, keeps the one-topic routing intact,
>    and materially *helps* the "detect within one day" success criterion (a DAILY summary is generated at
>    00:00 UTC for the *previous* day, adding up to 24 h of latency on top of CAD's own 24 h).
> 2. Keep `DAILY` and add a second `subscriber { type = "EMAIL" }` block — but then alerts no longer flow
>    through the single-topic path the decision was made to guarantee.
> `frequency` valid values: `DAILY` | `IMMEDIATE` | `WEEKLY` `[CITED: provider docs]`.

```hcl
resource "aws_ce_anomaly_monitor" "account_services" {
  name              = "l0-account-service-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "cost_alerts" {
  name      = "l0-anomaly-1usd"
  frequency = "IMMEDIATE" # see note above; "DAILY" requires an EMAIL subscriber

  monitor_arn_list = [aws_ce_anomaly_monitor.account_services.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"] # $1 absolute impact
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}
```

Threshold dimension keys, `[CITED]`: `ANOMALY_TOTAL_IMPACT_ABSOLUTE` (dollars) and
`ANOMALY_TOTAL_IMPACT_PERCENTAGE` (percent). `values` is a **list of strings**, not a number.

### 4. Detection latency — the honest answer for success criterion 3

AWS publishes these as hard numbers in the quota table
([CITED: management-limits](https://docs.aws.amazon.com/cost-management/latest/userguide/management-limits.html)):

| Property | Value |
|---|---|
| Time to detect anomaly after usage | **Up to 24 hours** |
| Historical data required for detection | **10 days minimum** |

And in prose ([CITED: manage-ad](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html)):
*"Cost Anomaly Detection runs approximately three times a day … uses data from Cost Explorer, which has a delay
of up to 24 hours. As a result, it can take up to 24 hours to detect an anomaly after a usage occurs. **If you
create a new monitor, it can take 24 hours to begin detecting new anomalies. For a new service subscription, 10
days of historical service usage data is needed before anomalies can be detected for that service.**"*

> 🔴 **This is a direct, material risk to success criterion 3 ("within one day").** Compose the delays:
> - **Up to 24 h** for the monitor to become active after creation, **plus**
> - **Up to 24 h** Cost-Explorer data lag before the spend is even visible, **plus**
> - **10 days of per-service history** before *that service* can be scored at all.
>
> On an **empty** account, the 10-day rule is the killer: **every** service is a "new service subscription".
> Spin up an EKS cluster on day 1 and CAD has **zero** EKS history — it cannot declare an anomaly, because
> "anomalous" is defined relative to a baseline that does not exist. Realistically CAD will not reliably alert
> on a $1 spend on a brand-new service until roughly **day 11–12 of that service's life**, and the
> worst-case latency once warm is **~24–48 h**, not "within one day."
>
> **Consequence for the plan:** CAD **cannot** be the mechanism that satisfies "detect a $1 spend within one
> day" during the first two weeks. If that criterion is load-bearing, it needs a second mechanism — e.g. a
> **`time_unit = "DAILY"` COST budget with an `ACTUAL` + `ABSOLUTE_VALUE` notification at `1`**, which is
> deterministic, threshold-based (no ML baseline, no warm-up), and bounded only by the 8–12 h Budgets refresh.
> That is the single highest-value addition this research suggests for Phase 1.

Additional CAD blind spots, all from the quota table `[CITED]` — **these services are NOT monitored at all**:
AWS Marketplace (except Bedrock 3P models), **AWS Support**, WorkSpaces, **Cost Explorer**, **Budgets**,
AWS Shield, **Amazon Route 53**, **AWS Certificate Manager**. And: *"Only analyzes **Usage** charge type and
**NetUnblendedCost**."* → **a leaked $0.50 Route 53 hosted zone is doubly invisible to CAD** (unsupported
service *and* a recurring, not usage, charge). [PITFALLS.md](.planning/research/PITFALLS.md#L291) identifies
hosted zones as a real $10/month leak vector; CAD will never catch it. Only the Budget will.

---

## Cost Allocation Tags & Cost Explorer — Manual Prerequisites

**What Terraform CAN do:**
- Apply tags to resources (`default_tags` / per-resource `tags`).
- Create the Budget, the CAD monitor + subscription, the SNS topic, policy, and subscription.
- Implicitly trigger Cost Explorer enablement: *"If you didn't enable Cost Explorer yet … **AWS Budgets will
  enable Cost Explorer when you create your first budget.**"*
  ([CITED: budgets-create](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html))

**What Terraform CANNOT do — these belong in D-01's manual runbook:**

| Manual step | Why Terraform can't | Latency | Source |
|---|---|---|---|
| **Enable Cost Explorer** | *"You **can't enable Cost Explorer using the API**."* Console-only, one time. | Current month's data in **~24 h**; the remaining 13 months take *"a few days longer"*; refreshes *"at least once every 24 hours"* thereafter. | [CITED: ce-enable](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-enable.html) |
| **Activate user-defined cost allocation tag keys** (`Project`, `Layer`, `ManagedBy`, `Environment`) | No Terraform resource. Billing console, or the `UpdateCostAllocationTagsStatus` API via raw CLI. | **Up to 24 h** for a newly-applied tag key to even *appear* on the Cost allocation tags page, **then up to a further 24 h to activate** — i.e. **up to 48 h end-to-end**. | [CITED: activating-tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html) |
| **Confirm the SNS email subscription** | Requires a human clicking a link in an email. | Indefinite — blocks until clicked. | see next section |

**Tags do NOT backfill.** *"Tags are not applied to resources that were created before the tags were created."*
([CITED: custom-tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/custom-tags.html)) Cost
allocation data is **forward-only**: activating `Layer` on day 10 gives you zero `Layer`-attributed cost for
days 1–9, permanently. **Therefore the tag-activation runbook step must run on day 1, before any
cost-generating phase** — otherwise the `Layer`-keyed cost attribution that D-34 calls "load-bearing" has a
permanent hole in it.

Two further tagging restrictions `[CITED: custom-tags]`:
- The `aws:` prefix is **reserved**; user-defined keys surface in reports prefixed `user:` (so `Layer` appears as
  `user:Layer`). The four chosen keys (`Project`, `Layer`, `ManagedBy`, `Environment`) are all safe.
- *"**AWS Budgets does not support tags for cost allocation.** This means you will not see tag information in
  cost and usage data."* ([CITED: budgets-best-practices](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-best-practices.html))
  — tagging the budget resource itself is for IAM/ABAC only, never for cost reporting.

**Runbook verification commands** (post-manual-step, for the D-01 runbook's "prove it" line):
```bash
# Did Cost Explorer actually turn on? (errors/empties until enabled + populated)
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-2d +%F),End=$(date -u +%F) \
  --granularity DAILY --metrics UnblendedCost
# NOTE: this call costs $0.01 per request (verified above). Don't poll it in a loop.

# Which cost allocation tag keys exist and are Active?
aws ce list-cost-allocation-tags --status Active --output table
aws ce list-cost-allocation-tags --status Inactive --output table

# Activate them non-interactively (alternative to the console):
aws ce update-cost-allocation-tags-status --cost-allocation-tags-status \
  TagKey=Project,Status=Active TagKey=Layer,Status=Active \
  TagKey=ManagedBy,Status=Active TagKey=Environment,Status=Active
```

### `default_tags` with `hashicorp/aws` 6.x — limitations

| Gotcha | Impact | Mitigation |
|---|---|---|
| **`default_tags` does not propagate to resources created *by* a resource.** ASG-launched EC2 instances, EKS managed-node-group instances/EBS/ENIs, Karpenter-provisioned nodes, and ALB-controller-created load balancers are created by a *service*, not by Terraform, and never inherit provider `default_tags`. | The `Layer` key — which D-34 declares load-bearing for cost attribution — will be **missing from exactly the resources that cost the most**. Cost Explorer will report the bulk of spend as `Layer = (not tagged)`. | Set tags at each propagating mechanism: ASG `tag { key … propagate_at_launch = true }`, EKS MNG `tags`, Karpenter `EC2NodeClass.spec.tags`, ALB controller `--default-tags`. Phase 4/5 concern, but decide the convention **now**. `[ASSUMED]` — inferred from the documented cost-allocation caveat that *"Some services launch other AWS resources … you can tag the supporting resources"* ([CITED: custom-tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/custom-tags.html)); not verified against a live plan. |
| **Key collision between `default_tags` and resource-level `tags`.** Documented behaviour: *"tags with matching keys will overwrite those defined at the provider-level."* | Silent override, not an error. A per-resource `Layer = "l1"` beats the provider's `Layer = "l0"` with no warning. | Never repeat a `default_tags` key at resource level unless the override is intentional and commented. `[CITED: provider docs]` |
| **Perpetual diffs from externally-mutated tags.** EKS, Karpenter, and the ALB controller write `kubernetes.io/*`, `karpenter.sh/*`, `eks:*` tags onto Terraform-managed resources. | Every `terraform plan` shows a tag diff forever; `plan` is no longer a clean signal, which corrodes the teardown-verifier discipline. | Provider-level escape hatch: `ignore_tags { key_prefixes = ["kubernetes.io/", "karpenter.sh/", "eks:", "aws:"] }`. `[ASSUMED]` — `ignore_tags` block exists and is the documented mechanism; the specific prefix list for this stack is inferred, not verified. |
| `tags_all` is the computed merged map | Reference `tags_all`, not `tags`, when asserting on effective tags in tests/outputs. | `[CITED: provider docs]` |
| **Not every AWS resource supports tags** | A `default_tags` value cannot be applied where the API has no tag support; this is silent. | For Phase 1 specifically this is fine: `aws_budgets_budget`, `aws_ce_anomaly_monitor`, `aws_ce_anomaly_subscription`, `aws_sns_topic`, `aws_s3_bucket`, and `aws_iam_openid_connect_provider` all document `tags` + `tags_all` support. `[CITED: provider docs]` |

---

## Email Subscription Confirmation

`aws_sns_topic_subscription` with `protocol = "email"` **cannot be confirmed by Terraform**. AWS states it
plainly: *"For notifications to be sent, **you must accept the subscription** to the Amazon SNS notification
topic … Under **Status**, `PendingConfirmation` appears if a subscription hasn't been accepted and confirmed."*
([CITED: budgets-sns-policy](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html))

Terraform will happily `apply` green with the subscription ARN literally set to the string
`pending confirmation`. **A green apply is not a working alert path.**

```hcl
resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # The ARN is the literal string "pending confirmation" until a human clicks.
  # Do not build downstream dependencies on this resource's `arn` attribute.
}
```

**Planning implications:**
1. Phase 1 needs an explicit **`checkpoint:human-verify`** task: *"Open the confirmation email sent to
   `<alert_email>` and click **Confirm subscription**."*
2. The task must be **ordered after** the `apply` that creates the subscription, and **before** any success
   criterion that asserts alerts are deliverable.
3. Terraform will show a **perpetual no-op** for this resource; it will not drift-correct or re-send.
4. If the email is missed, AWS does not retry automatically — it must be re-requested.

**Verify confirmation via CLI** (this is the assertion the verifier should make — not `terraform apply` exit code):
```bash
# Should print "Confirmed" — a real ARN means confirmed; the literal string
# "PendingConfirmation" in SubscriptionArn means it is NOT confirmed.
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query "Subscriptions[?Protocol=='email'].[Endpoint,SubscriptionArn]" --output table

# Machine-checkable gate for the teardown/bootstrap verifier:
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query "length(Subscriptions[?Protocol=='email' && SubscriptionArn!='PendingConfirmation'])" \
  --output text   # must be >= 1

# Resend the confirmation request if it was lost:
aws sns confirm-subscription --topic-arn "$TOPIC_ARN" --token "$TOKEN"  # token comes from the email link
```

---

## Gotchas & Landmines

- **FORECASTED budget alerts are dead for ~5 weeks on a new account.** *Why it bites:* three of the four
  notifications you just built cannot fire, so the phase "passes" with 25% of its alerting actually working, and
  nobody finds out until a real overspend goes unannounced. `[CITED]`
- **CAD needs 10 days of per-service history and up to 24 h to warm up.** *Why it bites:* it structurally cannot
  meet a "detect within one day" criterion on an empty account for the first ~1.5 weeks of each new service —
  the exact window in which a bootstrap experiment is most likely to leak money. `[CITED]`
- **CAD ignores Route 53, ACM, Support, WorkSpaces, Budgets, and Cost Explorer entirely, and only scores *Usage*
  charge types.** *Why it bites:* the $0.50-per-creation Route 53 hosted zone that
  [PITFALLS.md](.planning/research/PITFALLS.md#L291) flags as a $10/month leak is invisible to CAD on **both**
  counts — wrong service *and* wrong charge type. `[CITED]`
- **`frequency = "DAILY"` with an SNS-only subscriber conflicts with AWS's documented alerting modes.** *Why it
  bites:* it is an `apply`-time API rejection at best, and at worst a subscription that exists but never delivers
  — discovered only when an anomaly fails to page you. `[CITED]`
- **Enabling Cost Explorer auto-creates an AWS-managed `SERVICE` anomaly monitor** (*"AWS sets up an AWS services
  monitor and a daily summary alert subscription … $100 and 40%"*), and the quota is **1 AWS-managed services
  monitor per account**. *Why it bites:* your Terraform `DIMENSIONAL`/`SERVICE` monitor may collide with a
  monitor that AWS silently created for you, producing a quota error or a duplicate-alert situation on first
  apply. Plan for a pre-apply `aws ce get-anomaly-monitors` check and a possible `terraform import`.
  `[CITED]` on the auto-creation and the quota; `[ASSUMED]` on the exact collision failure mode.
- **`aws_sns_topic_policy` replaces the whole policy.** *Why it bites:* omitting `__default_statement_ID` strips
  your own account's `SNS:Subscribe`/`SetTopicAttributes` rights — the email subscription fails and you can't
  easily fix the topic. `[CITED: provider canonical example]`
- **Never enable SSE-KMS on the `cost-alerts` topic.** AWS: *"**The SNS topic is encrypted** — You have
  encryption enabled on the SNS topic. The SNS topic won't work without additional permissions. **Disable
  encryption on the topic.**"* *Why it bites:* a reflexive "encrypt everything" security pass silently breaks
  every budget alert, and additionally adds a $1/key-month charge to a $0.01 layer. `[CITED]`
- **Budgets and SNS must be in the same account; cross-account SNS is unsupported.** *Why it bites:* irrelevant
  today (standalone account) but hard-blocks any future move under an Organization payer. `[CITED]`
- **Every public IPv4 bills at $0.005/hr whether attached or idle** (Feb-2024 change). *Why it bites:* the old
  "release the EIP later, it's only charged when idle" instinct is now exactly backwards — and one leaked EIP is
  **73% of the entire $5 ceiling**. `[VERIFIED]`
- **S3 versioning bills every noncurrent version as a whole object.** *Why it bites:* trivial for a 50 KB
  tfstate, but the same bucket used for anything larger with frequent writes grows monotonically and forever —
  and `terraform destroy` on a versioned bucket fails unless versions are purged. Add a
  `noncurrent_version_expiration` lifecycle rule now, while the bucket is empty. `[CITED]`
- **CloudWatch log groups default to `Never Expire`.** *Why it bites:* at $0.03/GB-month with no expiry, the bill
  only ever goes up, and these groups are among the most commonly orphaned resources
  ([PITFALLS.md](.planning/research/PITFALLS.md#L72)). `[VERIFIED]` on rate.
- **Cost allocation tags never backfill and take up to 48 h to activate.** *Why it bites:* if tag activation
  isn't day-1, the `Layer` attribution that D-34 calls load-bearing has a permanent, unrecoverable hole exactly
  over the project's early experimentation period. `[CITED]`
- **`aws ce get-cost-and-usage` costs $0.01 per call.** *Why it bites:* a teardown verifier that polls Cost
  Explorer in a loop can itself become a line item — 500 polls/month = $5.00 = the entire ceiling. Use
  `describe-*` / `list-*` calls for resource-existence checks; reserve `ce` API calls for genuine cost queries.
  `[VERIFIED]`
- **`default_tags` never reaches service-launched resources.** *Why it bites:* the most expensive resources
  (EKS nodes, Karpenter instances, controller-created ALBs) arrive untagged, so `Layer`-keyed cost attribution
  is blindest precisely where the money is.
- **Budget tags are not cost allocation tags.** *Why it bites:* tagging the budget resource looks like cost
  attribution but produces nothing in Cost Explorer. `[CITED]`
- **The EC2 price list is 303 MB.** *Why it bites:* a naive `curl -o` in a verification script will stall CI.
  Always stream-grep. `[VERIFIED — Content-Length: 302856576]`

---

## Open Questions

**Q1 — Is Cost Anomaly Detection genuinely free? `[UNVERIFIED]`**
No offer code for Cost Anomaly Detection exists in the Price List index (`AWSBudgets` and `AWSCostExplorer` are
present; no anomaly-detection offer). That is **absent evidence**, which is not proof of a $0 price. AWS docs
describe CAD as *"a feature within Cost Explorer"* but no page consulted this session states "no additional
cost" affirmatively.
*Resolution:* check the AWS Cost Management pricing page in a real browser (it is JS-rendered and not
scrapable), or create the monitor and confirm no `AWSCostExplorer`-family line item appears on the bill after a
full billing cycle. **Impact if wrong: negligible** — even a nonzero price would be cents.

**Q2 — Are standard AWS Budgets now unlimited-free, or still 2-free-then-$0.02/budget-day? `[UNVERIFIED]`**
The live price list says `BudgetsUsage = $0.00` over `0–Inf`, and the `$0.02/budget-day` SKU is absent. The
quota doc's *"Number of free budgets **with actions** per account: 2"* corroborates that the "2 free" limit now
attaches to **action-enabled** budgets only.
*Resolution:* confirm on the AWS Budgets pricing page in a browser, or observe the first bill.
**Impact on this phase: zero** — one action-free COST budget is $0.00 under either model. Flagged only to stop
the stale `$0.02/budget-day` figure propagating into later phases' models.

**Q3 — Will `frequency = "DAILY"` + SNS-only subscriber actually apply? `[UNVERIFIED]`**
Documentary evidence is strong that it will not (daily summaries are documented as email-delivered; every
provider `DAILY` example uses `EMAIL`; the only SNS example uses `IMMEDIATE`), but no `terraform apply` was run
— `terraform` is not installed here.
*Resolution:* a single `terraform plan`/`apply` against the real account settles it in minutes. **Recommend the
plan simply adopt `IMMEDIATE`**, which sidesteps the question entirely and improves detection latency.

**Q4 — EBS gp3 free baseline (3,000 IOPS / 125 MiB/s). `[UNVERIFIED]`**
The price list exposes only the *incremental* provisioned-IOPS and provisioned-throughput SKUs; it does not
encode the included baseline. Phase 2+ concern only.
*Resolution:* the EBS pricing page, or empirically — provision a default gp3 volume and confirm no
`VolumeP-IOPS`/`VolumeP-Throughput` line items appear.

**Q5 — Does Cost Explorer's auto-created AWS-managed anomaly monitor collide with a Terraform-created
`DIMENSIONAL`/`SERVICE` monitor? `[UNVERIFIED]`**
The auto-creation is `[CITED]` and the 1-per-account quota is `[CITED]`, but the interaction is inferred.
*Resolution:* run `aws ce get-anomaly-monitors` against the target account **before** writing the plan. If an
AWS-managed services monitor already exists, the plan needs an `import` block rather than a `create`. This is a
cheap pre-flight check that should happen during planning, not during execution.

**Q6 — Exact `hashicorp/aws` version that removed the scalar `threshold` argument. `[UNVERIFIED]`**
Established: 6.x documents `threshold_expression` only, and the v6 upgrade guide does not mention this
resource — so the removal occurred within the 5.x line. The precise 5.x version was not pinned down.
*Resolution:* grep the provider CHANGELOG. **Impact: none** — the 6.x syntax above is correct regardless.

**Q7 — Is the Route 53 "hosted zone deleted within 12 hours is not charged" rule still accurate? `[UNVERIFIED]`**
Carried forward from [PITFALLS.md](.planning/research/PITFALLS.md#L293) and **not** re-verified this session
(out of Phase 1 scope, but it is the single largest per-session cost lever in the existing model and the whole
teardown discipline rests on it).
*Resolution:* re-read the Route 53 pricing page before Phase 4 commits to creating hosted zones per session.

---

# Part B — Terraform State, Bootstrap & Versioning

## Terraform S3 Native State Locking

### Version history — precise

| Terraform | What happened | Source |
|---|---|---|
| **1.10.0** | `use_lockfile` introduced. Changelog: *"The s3 backend now supports S3 native state locking. When used with DynamoDB-based locking, locks will be acquired from both sources. In a future minor release … the DynamoDB locking mechanism and associated arguments will be deprecated."* | [CHANGELOG v1.10](https://github.com/hashicorp/terraform/blob/v1.10/CHANGELOG.md) ([#35661](https://github.com/hashicorp/terraform/issues/35661)) |
| **1.11.0** | **GA.** *"S3 native state locking is now generally available. The `use_lockfile` argument enables users to adopt the S3-native mechanism … As part of this change, we've deprecated the DynamoDB-related arguments."* | [CHANGELOG v1.11](https://github.com/hashicorp/terraform/blob/v1.11/CHANGELOG.md) ([#36338](https://github.com/hashicorp/terraform/issues/36338)) |
| **1.12 – 1.16** | **No removal.** Grepping `dynamodb` across the v1.12, v1.13, v1.14, v1.15 and v1.16 CHANGELOGs returns **zero hits** — `dynamodb_table` / `dynamodb_endpoint` are still *Deprecated, not removed* as of 1.16.4. | Verified by grep against all six release-branch CHANGELOGs |

**Current docs wording (v1.16.x):** *"Locking can be enabled via S3 or DynamoDB. However, **DynamoDB-based locking is deprecated** and will be removed in a future minor version."*
— [`web-unified-docs` `content/terraform/v1.16.x/docs/language/backend/s3.mdx`](https://github.com/hashicorp/web-unified-docs/blob/main/content/terraform/v1.16.x/docs/language/backend/s3.mdx), §State Locking

**Verdict on the D-36 pin:** **Terraform 1.16.4 is comfortably fine.** The functional floor for GA `use_lockfile` is **1.11.0**; the absolute floor is 1.10.0. 1.16.4 is five minor versions above GA. ARCHITECTURE.md Decision 2's "drop DynamoDB state locking" is correct and is the current documented default posture.

**`required_version` recommendation:** pin exact per D-36 — `required_version = "= 1.16.4"`. Do **not** use `>= 1.11.0`; D-36 mandates exact pins. (See *Version Pinning* below for the one nuance this creates.)

### Exact backend syntax — full form

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-123456789012-us-east-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

`use_lockfile` — *"(Optional) Whether to use a lockfile for locking the state file. **Defaults to `false`.**"* [CITED: s3.mdx:56] It is opt-in; omitting it means **no locking at all** (silent, no warning). This is the single highest-value line in the whole backend block.

### Exact backend syntax — partial form (D-32, what we actually commit)

Every layer commits an **empty** backend block:

```hcl
# layers/00-bootstrap/backend.tf  (identical in 10-infra / 20-data / 30-gitops
# except for nothing — the key comes from the CLI, see below)
terraform {
  backend "s3" {}
}
```

And the generated, gitignored `backend.hcl` at the repo root (D-16):

```hcl
# backend.hcl — GENERATED by `make bootstrap`. Do not commit. Do not edit.
bucket       = "tfstate-123456789012-us-east-1"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

The **`key` is deliberately absent from `backend.hcl`** because it differs per layer (D-17). It is supplied on the command line, so one shared file serves all four layers:

```bash
terraform -chdir=layers/00-bootstrap init \
  -backend-config=../../backend.hcl \
  -backend-config="key=bootstrap/terraform.tfstate"
```

> ⚠️ **D-16 says `-backend-config=../backend.hcl`.** With `-chdir`, Terraform resolves the `-backend-config` path **relative to the `-chdir` directory**, so from `layers/00-bootstrap` the repo root is `../../`, not `../`. If instead the Makefile `cd`s into the layer dir, `../..` still applies. `../backend.hcl` is only correct if `backend.hcl` is written into `layers/`, not the repo root. **The plan must pick one and be consistent.** Recommendation: put `backend.hcl` at the **repo root** next to `Makefile`/`backend.hcl.example`, and always pass `-backend-config="$(ROOT)/backend.hcl"` as an **absolute** path from the Makefile (`ROOT := $(shell pwd)`), which removes the ambiguity entirely.

**`backend.hcl.example` (committed):**

```hcl
# backend.hcl.example — shape documentation only.
# The real backend.hcl is GENERATED by `make bootstrap` and is gitignored,
# because the bucket name embeds the AWS account ID (D-16/D-17).
#
#   bucket = "tfstate-<account-id>-<region>"
#
# `key` is NOT set here — it is passed per-layer via:
#   -backend-config="key=<layer>/terraform.tfstate"
bucket       = "tfstate-000000000000-us-east-1"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

### The lock object: name, location, contents

**Name and location** — the lock object is the state key with `.tflock` appended, written as a **sibling of the state object in the same bucket**:

```go
// internal/backend/remote-state/s3/backend_state.go
lockFileSuffix = ".tflock"

// getLockFilePath returns the path to the lock file for the given Terraform state.
// For `default.tfstate`, the lock file is stored at `default.tfstate.tflock`.
func (b *Backend) getLockFilePath(name string) string {
	return b.path(name) + lockFileSuffix
}
```
[VERIFIED: hashicorp/terraform v1.16 `internal/backend/remote-state/s3/backend_state.go:32`, `:291-295`]

So for this project:

| Layer | State object | Lock object |
|---|---|---|
| `00-bootstrap` | `bootstrap/terraform.tfstate` | `bootstrap/terraform.tfstate.tflock` |
| `10-infra` | `infra/terraform.tfstate` | `infra/terraform.tfstate.tflock` |
| `20-data` | `data/terraform.tfstate` | `data/terraform.tfstate.tflock` |
| `30-gitops` | `gitops/terraform.tfstate` | `gitops/terraform.tfstate.tflock` |

**Contents** — JSON marshal of `statemgr.LockInfo`:

```go
type LockInfo struct {
	ID        string    // Unique ID for the lock (random UUID)
	Operation string    // Terraform operation, provided by the caller
	Info      string    // Extra information to store with the lock
	Who       string    // user@hostname when available
	Version   string    // Terraform version
	Created   time.Time // Time that the lock was taken
	Path      string    // Path to the state file
}
```
[VERIFIED: hashicorp/terraform v1.16 `internal/states/statemgr/locker.go`]

Realised on disk as (`ContentType: application/json`):

```json
{
  "ID": "6f3c1f0e-1c2b-4c9a-8f2e-0a1b2c3d4e5f",
  "Operation": "OperationTypeApply",
  "Info": "",
  "Who": "minhcn2.gst@CPP00297778F",
  "Version": "1.16.4",
  "Created": "2026-09-25T09:14:02.113Z",
  "Path": "tfstate-123456789012-us-east-1/bootstrap/terraform.tfstate"
}
```

**How the lock is acquired — conditional write, not a permission trick:**

```go
input := &s3.PutObjectInput{
	ContentType: aws.String("application/json"),
	Body:        bytes.NewReader(lockFileJson),
	Bucket:      aws.String(c.bucketName),
	Key:         aws.String(c.lockFilePath),
	IfNoneMatch: aws.String("*"),
}
if !c.skipS3Checksum {
	input.ChecksumAlgorithm = s3types.ChecksumAlgorithmSha256
}
```
[VERIFIED: `internal/backend/remote-state/s3/client.go:355-366`]

> **Correction to a common framing.** `IfNoneMatch: "*"` is an **HTTP request header on `PutObject`** (S3 conditional writes), **not** an IAM condition key. There is **no separate IAM permission** for it and **no `s3:PutObject` `Condition` block to write**. Plain `s3:PutObject` on the `.tflock` ARN is sufficient and complete. Anyone adding an IAM `Condition` to "enable conditional writes" is cargo-culting.

The mutual exclusion is enforced **by S3 itself**: a second `PutObject` with `If-None-Match: *` against an existing key returns `412 PreconditionFailed`, and Terraform then `GET`s the existing `.tflock` to render the "Lock Info" block in the error.

**Release** — `DeleteObject` on the `.tflock` key, but only after an ID match:

```go
// Verify that the provided lock ID matches the lock ID of the retrieved lock file.
if lockInfo.ID != id {
	return fmt.Errorf("lock ID '%s' does not match the existing lock ID '%s'", id, lockInfo.ID)
}
// Delete the lock file to release the lock.
_, err = c.s3Client.DeleteObject(ctx, &s3.DeleteObjectInput{ ... })
```
[VERIFIED: `client.go:540-554`]

### IAM permissions for locking

Official policy shape [CITED: s3.mdx:80-115]:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::tfstate-123456789012-us-east-1"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::tfstate-123456789012-us-east-1/*/terraform.tfstate"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::tfstate-123456789012-us-east-1/*/terraform.tfstate.tflock"
    }
  ]
}
```

Docs notes, verbatim:
- *"If `use_lockfile` is set, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` are required on the lock file, e.g., `arn:aws:s3:::mybucket/path/to/my/key.tflock`."* [CITED: s3.mdx:75-77]
- *"`s3:DeleteObject` is **not** required on the state file, as Terraform does not delete it."* [CITED: s3.mdx:79] — so `DeleteObject` is scoped to the `.tflock` ARN only. Good least-privilege boundary for the D-27 `gha-terraform-plan` role.
- **No DynamoDB permissions are needed.** The `dynamodb:GetItem/PutItem/DeleteItem` block in the docs is explicitly gated on *"If you are using the deprecated DynamoDB-based locking mechanism."* We are not (D-15/ARCHITECTURE Decision 2).

> ⚠️ **Doc bug to not copy.** The docs' `s3:ListBucket` example carries `"Condition": {"StringEquals": {"s3:prefix": "mybucket/path/to/my/key"}}` — the `s3:prefix` key takes an **object key prefix**, which never includes the bucket name. Copying it verbatim yields a `ListBucket` that matches nothing. Either drop the condition (as above) or write `"s3:prefix": "bootstrap/"`. [Observation from s3.mdx:88-94]

### Demonstrating the lock — success criterion 2

The `.tflock` lives for the duration of the apply only, so a naive `aws s3 ls` after the fact shows nothing. Three methods, in descending order of reliability:

**Method 1 — post-hoc via object versions (RECOMMENDED; this is the durable evidence artifact).**

Because D-18 turns versioning **on**, the `DeleteObject` that releases the lock does **not** erase anything — S3 inserts a **delete marker** and retains the `.tflock` object version. Both are inspectable **after** the apply completes, with no race and no timing:

```bash
BUCKET="tfstate-$(aws sts get-caller-identity --query Account --output text)-us-east-1"
KEY="bootstrap/terraform.tfstate.tflock"

# 1. Run a normal apply (no special flags needed).
terraform -chdir=layers/00-bootstrap apply -auto-approve

# 2. The lock object is GONE from the current-version view:
aws s3api head-object --bucket "$BUCKET" --key "$KEY"
#    -> An error occurred (404) when calling the HeadObject operation: Not Found

# 3. ...but its full lifecycle is preserved in the version history:
aws s3api list-object-versions \
  --bucket "$BUCKET" --prefix "$KEY" \
  --query '{Acquired:Versions[].{VersionId:VersionId,Modified:LastModified,Size:Size},
            Released:DeleteMarkers[].{VersionId:VersionId,Modified:LastModified,IsLatest:IsLatest}}' \
  --output table
```

Expected: one row under `Acquired` (the lock being taken) and one row under `Released` with `IsLatest: True` (the lock being dropped). The two `LastModified` timestamps bracket the apply.

Then read the lock's actual contents back:

```bash
VID=$(aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" \
        --query 'Versions[0].VersionId' --output text)

aws s3api get-object --bucket "$BUCKET" --key "$KEY" --version-id "$VID" /tmp/lock.json >/dev/null
jq . /tmp/lock.json
# { "ID": "...", "Operation": "OperationTypeApply", "Who": "user@host",
#   "Version": "1.16.4", "Created": "...", "Path": "..." }
```

> **Retention caveat:** the noncurrent-version expiry rule below (`noncurrent_days`) eventually reaps these. With `noncurrent_days = 30` there is a comfortable 30-day window to demonstrate it. Capture the `list-object-versions` output into the phase evidence artifact rather than relying on it being re-runnable months later.

**Method 2 — live observation via background poller.** Catches it in flight; needs the apply to exceed the poll interval:

```bash
BUCKET="tfstate-$(aws sts get-caller-identity --query Account --output text)-us-east-1"
KEY="bootstrap/terraform.tfstate.tflock"

( while :; do
    if aws s3api head-object --bucket "$BUCKET" --key "$KEY" >/dev/null 2>&1; then
      echo "[$(date -u +%H:%M:%S)] LOCK PRESENT"
    else
      echo "[$(date -u +%H:%M:%S)] lock absent"
    fi
    sleep 1
  done ) & POLLER=$!
trap 'kill "$POLLER" 2>/dev/null' EXIT

terraform -chdir=layers/00-bootstrap apply -auto-approve
kill "$POLLER"; trap - EXIT
```

Add `-parallelism=1` to stretch a short apply. Do **not** introduce a `time_sleep` resource to slow it down — D-20 pins L0's contents to exactly four things.

**Method 3 — contention proof (proves it actually excludes, not just that a file appears).**

```bash
terraform -chdir=layers/00-bootstrap apply -auto-approve & APPLY=$!
sleep 2
terraform -chdir=layers/00-bootstrap plan    # expected to FAIL
wait "$APPLY"
```

The second invocation exits non-zero with `Error acquiring the state lock` and prints the `Lock Info:` block (ID / Path / Operation / Who / Version / Created) read straight out of the `.tflock`. This is the strongest single piece of evidence — it demonstrates the object, its contents, and its effect in one output. It is, however, timing-dependent; pair it with Method 1.

### `force-unlock` and stale locks

`terraform force-unlock <LOCK_ID>` goes through the same `unlockWithFile` path, which **`GET`s the `.tflock`, unmarshals it, and refuses unless `lockInfo.ID == id`** [VERIFIED: `client.go:540-546`]. Consequences:

- You **must** supply the exact lock ID. It is printed in the `Lock Info:` block of the failure — copy it from there.
  ```bash
  terraform -chdir=layers/00-bootstrap force-unlock 6f3c1f0e-1c2b-4c9a-8f2e-0a1b2c3d4e5f
  ```
- **There is no TTL and no automatic expiry.** An apply killed with `SIGKILL`, a laptop that slept, or a cancelled GitHub Actions job leaves the `.tflock` in place **forever**. This is a real operational hazard for a project whose whole premise is nightly teardown.
- Escape hatch if the ID is unreadable or `force-unlock` refuses (e.g. corrupt lock JSON) — delete the object directly:
  ```bash
  aws s3api delete-object --bucket "$BUCKET" --key "bootstrap/terraform.tfstate.tflock"
  ```
  Only ever do this after confirming no apply is genuinely running. With versioning on, this is itself recoverable (it just adds another delete marker).
- `force-unlock` does **not** need `-force` on the S3 backend; it prompts for confirmation unless `-force` is passed.

**Recommendation for the plan:** add a `make unlock LAYER=<n>` target that prints the current lock holder (`Who`/`Created`) from `list-object-versions` before doing anything, so the operator sees *whose* lock they are about to break.

### Migration caveat — DynamoDB (we have none, but do not do this)

`lockWithDynamoDB` is called **in addition to** `lockWithFile` when both are configured:

```go
// double locking: dynamodb + file (design decision: both must succeed)
```
[VERIFIED: `client.go:327`]

So if `dynamodb_table` is ever set alongside `use_lockfile`, **both** locks must be acquired, and failure to acquire the DynamoDB lock rolls back the S3 lock. That mode exists **only** as a migration bridge for teams coming from pre-1.10 setups.

**For this project: never set `dynamodb_table` or `dynamodb_endpoint`.** There is no table, there was never a table, and adding one would (a) adopt a deprecated mechanism, (b) add a fifth immortal resource to L0 in violation of D-20, and (c) add a DynamoDB line item to a $5 budget. ARCHITECTURE.md already flags that this **contradicts PROJECT.md's "S3 + DynamoDB state locking"** requirement — the plan should carry an explicit task to amend that requirement text to *"S3 remote state with native `use_lockfile` locking"* so the contradiction is resolved in writing rather than silently ignored.

---

## Bootstrap Sequence (chicken-and-egg)

### The shape of the problem

`00-bootstrap` must create the bucket that will hold `00-bootstrap`'s own state. D-15 resolves it as: apply with a **local** backend → bucket now exists → configure the backend → `terraform init -migrate-state` pushes the local state up into the bucket it just made.

The wrinkle D-16 adds: the bucket name is `tfstate-<account-id>-<region>` (D-17), unknowable until `aws_caller_identity` resolves, so the backend config **cannot be committed**. Hence generated `backend.hcl`.

### Required outputs in `layers/00-bootstrap/outputs.tf`

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state for all layers."
  value       = aws_s3_bucket.tfstate.id
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}
```

### `make bootstrap` — the actual sequence

```makefile
ROOT          := $(shell pwd)
BOOTSTRAP_DIR := $(ROOT)/layers/00-bootstrap
BACKEND_HCL   := $(ROOT)/backend.hcl

.PHONY: bootstrap
bootstrap: doctor
	@set -euo pipefail; \
	cd "$(BOOTSTRAP_DIR)"; \
	\
	if [ -f .terraform/terraform.tfstate ] \
	   && [ "$$(jq -r '.backend.type // "null"' .terraform/terraform.tfstate)" = "s3" ]; then \
	  echo "==> 00-bootstrap already migrated to S3; re-initialising only."; \
	  BUCKET="$$(jq -r '.backend.config.bucket' .terraform/terraform.tfstate)"; \
	  $(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET"; \
	  terraform init -input=false -reconfigure \
	    -backend-config="$(BACKEND_HCL)" \
	    -backend-config="key=bootstrap/terraform.tfstate"; \
	  terraform apply -input=false -auto-approve; \
	  exit 0; \
	fi; \
	\
	echo "==> [1/4] Applying 00-bootstrap with a LOCAL backend"; \
	terraform init -input=false -backend=false; \
	terraform apply -input=false -auto-approve; \
	\
	echo "==> [2/4] Generating $(BACKEND_HCL) from apply output"; \
	BUCKET="$$(terraform output -raw state_bucket_name)"; \
	$(MAKE) -s _write-backend-hcl BUCKET="$$BUCKET"; \
	\
	echo "==> [3/4] Migrating local state into s3://$$BUCKET/bootstrap/terraform.tfstate"; \
	terraform init -input=false -force-copy \
	  -backend-config="$(BACKEND_HCL)" \
	  -backend-config="key=bootstrap/terraform.tfstate"; \
	\
	echo "==> [4/4] Verifying the migration"; \
	terraform plan -input=false -detailed-exitcode || \
	  { [ $$? -eq 2 ] && { echo "ERROR: drift after migration"; exit 1; }; }; \
	aws s3api head-object --bucket "$$BUCKET" --key bootstrap/terraform.tfstate >/dev/null; \
	echo "==> Bootstrap complete. State is remote."

.PHONY: _write-backend-hcl
_write-backend-hcl:
	@printf '%s\n' \
	  '# GENERATED by `make bootstrap` (D-16). Do not commit. Do not edit.' \
	  'bucket       = "$(BUCKET)"' \
	  'region       = "$(AWS_REGION)"' \
	  'encrypt      = true' \
	  'use_lockfile = true' > "$(BACKEND_HCL)"
```

Notes on the specific flags:

- **`terraform init -backend=false`** for step 1. This is the correct way to say "no backend at all" — it installs providers and skips backend initialisation entirely. It is cleaner than commenting out the `backend "s3" {}` block, because D-32 requires that block to be committed and *present*. `-backend=false` lets the empty block stay in the file while the first apply writes `terraform.tfstate` locally. [CITED: [validate.mdx:27-30](https://github.com/hashicorp/web-unified-docs/blob/main/content/terraform/v1.16.x/docs/cli/commands/validate.mdx) documents `-backend=false` as the "don't access the configured backend" switch]
- **`-force-copy`** on step 3 rather than bare `-migrate-state`. `terraform init` auto-detects that a backend appeared and offers migration interactively; `-force-copy` answers "yes" non-interactively, which is what an unattended `make` target needs. `-migrate-state` alone still prompts. Using `-input=false` without `-force-copy` will **fail** rather than proceed.
- **`-detailed-exitcode`** on the verification plan: `0` = no changes (migration clean), `2` = drift (something is wrong), `1` = error.

### Detecting "already migrated" — the idempotency check

The canonical marker is `.terraform/terraform.tfstate` — the **backend state file**, not the resource state. After a successful migration it contains:

```json
{
  "version": 3,
  "backend": {
    "type": "s3",
    "config": { "bucket": "tfstate-123456789012-us-east-1", "key": "bootstrap/terraform.tfstate", ... },
    "hash": 1234567890
  }
}
```

So:

```bash
jq -r '.backend.type // "null"' layers/00-bootstrap/.terraform/terraform.tfstate
# -> "s3"   == already migrated
# -> "null" == local backend, or file absent == never bootstrapped
```

Two complementary checks worth adding, because `.terraform/` is gitignored and therefore absent on a fresh clone or a fresh CI runner:

```bash
# Does the bucket already exist in the account? (survives a wiped .terraform/)
BUCKET="tfstate-$(aws sts get-caller-identity --query Account --output text)-us-east-1"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  # Does remote state already exist inside it?
  if aws s3api head-object --bucket "$BUCKET" --key bootstrap/terraform.tfstate >/dev/null 2>&1; then
    echo "already-bootstrapped"   # -> regenerate backend.hcl, plain init, no migration
  fi
fi
```

This is the **robust** form and should be what the Makefile actually keys on, because it asks the account rather than the local scratch directory. The decision table:

| Bucket exists | Remote state exists | `.terraform/` says s3 | Action |
|---|---|---|---|
| no | — | — | Full bootstrap (steps 1–4) |
| yes | no | — | Bucket made but migration interrupted → write `backend.hcl`, `init -force-copy` |
| yes | yes | yes | Write `backend.hcl`, `init -reconfigure`, `apply` |
| yes | yes | no (fresh clone) | Write `backend.hcl`, `init -reconfigure`, `apply` — **`-reconfigure`, not `-force-copy`** |

> ⚠️ **The one genuinely dangerous case.** On a fresh clone with remote state already present, if the local `terraform.tfstate` file happens to exist (e.g. left behind from a previous local apply) and you run `init -force-copy`, Terraform will **overwrite the good remote state with the stale local one**. This is the single worst thing that can happen in this phase. Guard it: `-force-copy` must be reachable **only** on the "remote state does not exist" branch. Everywhere else use `-reconfigure`.

### `prevent_destroy` — syntax and the caveats

```hcl
resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"

  # D-19: L0 is immortal. This bucket holds the state of every other layer.
  lifecycle {
    prevent_destroy = true
  }

  tags = { Layer = "00-bootstrap" }
}
```

Official semantics [CITED: [lifecycle.mdx:71-79](https://github.com/hashicorp/web-unified-docs/blob/main/content/terraform/v1.16.x/docs/language/meta-arguments/lifecycle.mdx)]:

> *"When `prevent_destroy` is set to `true`, Terraform rejects plans that would destroy the infrastructure object associated with the resource and returns an error. The argument must be present in the configuration. This rule doesn't prevent Terraform from destroying a resource if you remove its configuration."*
>
> *"Enabling `prevent_destroy`, however, **makes certain configuration changes impossible to apply** and prevents the `terraform destroy` command from operating once such objects are created. Use `prevent_destroy` sparingly."*

Three caveats that matter here:

1. **It blocks legitimate replacement, not just `destroy`.** Any change that forces replacement of the bucket — most importantly a change to `bucket` (the name), which is `ForceNew` — will fail the **plan**, not the apply. Since the name embeds `var.region`, **changing `var.region` becomes a hard error**, which is exactly the "costly reversibility" D-02 warns about, now enforced by the tool. That is desirable, but it should be documented in `layers/00-bootstrap/README.md` so it isn't a surprise.
2. **It cannot be overridden at runtime.** There is no `-force` flag, no environment variable, no `-target` escape. Worse, it cannot even be driven by a variable:
   > *"…the dependency graph. As a result, **only literal values can be used** because the processing happens too early for arbitrary expression evaluation."* [CITED: lifecycle.mdx:31-32]

   So `prevent_destroy = var.allow_nuke` **does not compile**. Any design that assumes a tfvar can unlock it is wrong.
3. **Removing the resource from configuration bypasses it entirely** (per the doc text above) — which is the seam `make nuke-bootstrap` has to use.

### How `make nuke-bootstrap` (D-19) must therefore work

Given (2), the guard can only be removed by **editing code**. Given the state lives inside the bucket being destroyed, there is also a **second chicken-and-egg on the way down**. And given versioning is on, a non-empty versioned bucket cannot be deleted at all without purging every version.

The sequence, in order — all three problems must be solved:

```makefile
.PHONY: nuke-bootstrap
nuke-bootstrap:
	@set -euo pipefail; \
	echo "This DESTROYS the Terraform state bucket for EVERY layer."; \
	echo "It is irreversible. All other layers must already be destroyed."; \
	printf 'Type exactly: DESTROY BOOTSTRAP %s\n> ' "$$(aws sts get-caller-identity --query Account --output text)"; \
	read -r CONFIRM; \
	EXPECT="DESTROY BOOTSTRAP $$(aws sts get-caller-identity --query Account --output text)"; \
	[ "$$CONFIRM" = "$$EXPECT" ] || { echo "Mismatch. Aborted."; exit 1; }; \
	\
	cd "$(BOOTSTRAP_DIR)"; \
	\
	echo "==> [1/5] Refusing to proceed if other layers still hold state"; \
	BUCKET="$$(terraform output -raw state_bucket_name)"; \
	for K in infra data gitops; do \
	  if aws s3api head-object --bucket "$$BUCKET" --key "$$K/terraform.tfstate" >/dev/null 2>&1; then \
	    echo "ERROR: $$K/terraform.tfstate still exists. Destroy that layer first."; exit 1; \
	  fi; \
	done; \
	\
	echo "==> [2/5] Migrating state back to LOCAL (cannot destroy the bucket we store state in)"; \
	terraform init -input=false -force-copy -backend=false; \
	\
	echo "==> [3/5] Lifting the prevent_destroy guard"; \
	mv guard.tf guard.tf.disabled; \
	\
	echo "==> [4/5] Emptying the versioned bucket (all versions + delete markers)"; \
	./scripts/empty-versioned-bucket.sh "$$BUCKET"; \
	\
	echo "==> [5/5] Destroying"; \
	terraform destroy -input=false -auto-approve; \
	mv guard.tf.disabled guard.tf; \
	rm -f "$(BACKEND_HCL)"; \
	echo "==> L0 destroyed. The account no longer has Terraform state."
```

The `guard.tf` file-swap is the cleanest mechanism, and it keeps the guard visible in code review rather than buried in a `sed` expression:

```hcl
# layers/00-bootstrap/guard.tf
# Renamed to guard.tf.disabled ONLY by `make nuke-bootstrap` (D-19).
# prevent_destroy cannot be driven by a variable — only literal values are
# permitted (lifecycle.mdx). File-swapping is the only supported escape.
resource "aws_s3_bucket" "tfstate" {
  lifecycle {
    prevent_destroy = true
  }
}
```

> ⚠️ **Terraform does not support split `resource` blocks** — you cannot declare `aws_s3_bucket.tfstate` in two files. The `guard.tf` above is **illustrative of intent only and will not parse**. The real options are: (a) `sed -i.bak 's/prevent_destroy = true/prevent_destroy = false/'` on the single `main.tf` inside the nuke target, restoring from `.bak` afterwards; or (b) commit the whole `aws_s3_bucket.tfstate` resource in a file `state-bucket.tf` and have the nuke target run a targeted `sed` against just that file. **Recommendation: (a), with the restore in a `trap` so an interrupted nuke cannot leave the guard down.** The plan must not ship the two-block form.

Also required — `scripts/empty-versioned-bucket.sh`, because `terraform destroy` on a non-empty bucket fails with `BucketNotEmpty` and `force_destroy = true` must **not** be set on a state bucket in normal operation (it would make a stray `destroy` silently eat all state history):

```bash
#!/usr/bin/env bash
set -euo pipefail
BUCKET="${1:?usage: empty-versioned-bucket.sh <bucket>}"

while :; do
  PAYLOAD=$(aws s3api list-object-versions --bucket "$BUCKET" --max-keys 1000 \
    --query '{Objects: ([Versions, DeleteMarkers][] || [])[].{Key:Key,VersionId:VersionId}}' \
    --output json)
  COUNT=$(jq '.Objects | length' <<<"$PAYLOAD")
  [ "$COUNT" -eq 0 ] && break
  aws s3api delete-objects --bucket "$BUCKET" --delete "$(jq -c '. + {Quiet:true}' <<<"$PAYLOAD")" >/dev/null
  echo "deleted $COUNT versions/markers"
done
echo "bucket $BUCKET is empty"
```

---

## State Bucket Hardening & Recovery

### What is default now vs. what to declare anyway

| Concern | AWS default today | Declare it? | Why |
|---|---|---|---|
| **Encryption at rest** | ✅ SSE-S3 automatic. *"Amazon S3 now applies server-side encryption with Amazon S3 managed keys (SSE-S3) as the base level of encryption for every bucket… Starting **January 5, 2023**, all new object uploads to Amazon S3 are automatically encrypted."* [CITED: [default-encryption-faq](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-encryption-faq.html)] | **Yes — declare** | Free, no drift, and it makes the intent auditable. Without the resource, a future console change to SSE-KMS produces no Terraform diff. |
| **Public access blocked** | ✅ *"By default, new buckets, access points, and objects don't allow public access."* [CITED: [access-control-block-public-access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)] (BPA-on-by-default since April 2023) | **Yes — declare** | Same reasoning, plus it is the single control every security scanner (`tfsec`, `checkov`, Trivy) looks for. Omitting it produces findings even though the bucket is safe. |
| **ACLs disabled / object ownership** | ✅ *"The default setting is Bucket owner enforced"*, *"all ACLs are disabled"* [CITED: create-bucket-overview] | **Optional** | Genuinely redundant for a new bucket. Declare it only if a scanner demands it. Lowest value of the four. |
| **Versioning** | ❌ **Off by default** | **Yes — mandatory** | D-18 makes this the *only* recovery mechanism, and the backend docs carry a `~> Warning!`: *"It is highly recommended that you enable Bucket Versioning on the S3 bucket to allow for state recovery in the case of accidental deletions and human error."* [CITED: s3.mdx:15-17] |

**Verdict:** declare all four. Three are redundant *at creation time* but none are redundant *as drift detection* — which is the actual job of IaC. The cost is four zero-dollar resources and about 25 lines. The counter-argument (fewer resources = shorter teardown) does not apply: L0 never tears down (D-19).

### The HCL (provider `hashicorp/aws` `= 6.66.0`)

```hcl
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  # force_destroy intentionally omitted (defaults false). See make nuke-bootstrap.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3. KMS would add per-request cost for zero benefit here.
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
```

> **Cost note for `COSTS.md`:** `sse_algorithm = "AES256"` (SSE-S3) is **free**. `aws:kms` with a customer-managed key costs **$1/month for the key alone** — 20% of the entire $5 budget (D-25) — plus per-request charges on every state read/write and every lock acquire/release. For a single-operator practice account, SSE-S3 is the correct choice. Do not "upgrade" to KMS.

### Noncurrent-version expiry — the rule that stops unbounded growth

Every `terraform apply` writes a new state object version. Every lock acquire/release writes a `.tflock` version **and** a delete marker. Across four layers and a nightly up/down cycle this is roughly 8–20 new versions per day, retained forever, for the life of the account. Small in bytes, but unbounded, and it makes `list-object-versions` unusable for the D-18 recovery procedure within a few months.

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # AWS rejects a lifecycle configuration on a versioned bucket configured
  # before versioning is active; the dependency makes the ordering explicit.
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {} # applies to all objects — see note below

    noncurrent_version_expiration {
      noncurrent_days           = 30
      newer_noncurrent_versions = 10
    }
  }

  rule {
    id     = "reap-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

`newer_noncurrent_versions = 10` means *"keep at least the 10 most recent noncurrent versions regardless of age"* — so even after a 30-day idle gap you still have ten recoverable state generations. That is the belt-and-braces D-18 needs. [CITED: [s3_bucket_lifecycle_configuration.html.markdown](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/website/docs/r/s3_bucket_lifecycle_configuration.html.markdown) §`noncurrent_version_expiration` Block]

**The `filter {}` trap.** Provider 6.x documents it precisely:

> *"The `filter` argument, while Optional, is **required** if the `rule` configuration block does not contain a `prefix` **and** you intend to override the default behavior of setting the rule to filter objects with the empty string prefix (`""`). Since `prefix` is deprecated by Amazon S3 and will be removed in the next major version of the Terraform AWS Provider, we recommend users specify `filter`."*
>
> *"The `filter` configuration block must either be specified as the empty configuration block (`filter {}`) or with **exactly one** of `prefix`, `tag`, `and`, `object_size_greater_than` or `object_size_less_than` specified."*
>
> *"A rule **cannot be updated** from having a filter … to only having a prefix via the `rule.prefix` parameter."*

[CITED: provider v6.66.0 lifecycle docs, §`rule` Block and §`filter` Block]

Three concrete consequences:
1. **Always write `filter {}` explicitly.** Omitting it "works" but leaves you on the deprecated implicit-prefix path.
2. **Never put two of `prefix`/`tag`/`object_size_*` directly inside `filter`** — wrap them in `and {}`. Doing otherwise is a plan-time error, and it is the most common mistake with this resource.
3. **`rule.prefix` is Deprecated** and removed in provider 7.x. Do not use it.

Also note `expected_bucket_owner` is now marked **Deprecated** on this resource in 6.66.0 — do not add it.

### D-18 recovery sequence (copy-pasteable, for `layers/00-bootstrap/README.md`)

```bash
# --- Terraform state recovery via S3 object versioning -----------------------
# This is the ONLY state recovery mechanism (D-18). terraform.tfstate.backup is
# a local scratch file, is gitignored, and is NOT a backup strategy.

BUCKET="tfstate-$(aws sts get-caller-identity --query Account --output text)-us-east-1"
LAYER=infra                                 # bootstrap | infra | data | gitops
KEY="${LAYER}/terraform.tfstate"

# 1. List every retained version, newest first, with size and timestamp.
aws s3api list-object-versions \
  --bucket "$BUCKET" --prefix "$KEY" \
  --query 'reverse(sort_by(Versions[?Key==`'"$KEY"'`],&LastModified))[].{
             When:LastModified, Bytes:Size, IsLatest:IsLatest, VersionId:VersionId}' \
  --output table

# 2. Pull the version you want to a local file and sanity-check it BEFORE using it.
VERSION_ID="<paste VersionId from step 1>"
aws s3api get-object \
  --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION_ID" \
  ./recovered.tfstate
jq -r '"serial=\(.serial) lineage=\(.lineage) resources=\(.resources|length)"' ./recovered.tfstate

# 3. Restore by writing it back as the new current version.
#    (Do NOT delete the bad version — keep the forensic trail.)
aws s3api put-object \
  --bucket "$BUCKET" --key "$KEY" \
  --body ./recovered.tfstate \
  --content-type application/json

# 4. Re-sync the local working directory and confirm no drift.
terraform -chdir="layers/$(printf '%s' "$LAYER" | sed 's/^bootstrap$/00-bootstrap/;s/^infra$/10-infra/;s/^data$/20-data/;s/^gitops$/30-gitops/')" \
  init -reconfigure -input=false \
  -backend-config="$PWD/backend.hcl" \
  -backend-config="key=$KEY"
terraform -chdir=... plan -input=false -detailed-exitcode   # want exit 0
rm -f ./recovered.tfstate
```

> ⚠️ **`serial` and `lineage`.** Restoring an older version rolls `serial` **backwards**. Terraform tolerates this on S3 (unlike Terraform Cloud), but if any other operator or CI run wrote state in between, their changes are silently lost. Before restoring: confirm nothing else is mid-apply (`list-object-versions` on the `.tflock` prefix), and record the `serial` you are overwriting. Never restore a state file with a **different `lineage`** — that is a different configuration's state and will orphan every resource.

---

## Layer Skeleton & Partial Backend Config

### What a D-31 stub layer minimally contains

Three files. Two are mandatory; the third is required by D-02's "declared once as `var.region` with that default in every layer's `variables.tf`".

**`layers/10-infra/versions.tf`** (byte-identical in `20-data` and `30-gitops`; `00-bootstrap` is the same but will grow provider blocks):

```hcl
terraform {
  # D-36: exact pin, mirrored in VERSIONS.md and .terraform-version.
  required_version = "= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.66.0"
    }
  }

  # D-32: PARTIAL backend configuration. Every value is supplied by the
  # Makefile via -backend-config. Never run `terraform init` by hand.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = var.project
      Layer   = "10-infra"
    }
  }
}
```

**`layers/10-infra/variables.tf`:**

```hcl
variable "region" {
  description = "AWS region. Single-region project (D-02)."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Value of the Project tag, consumed by the teardown sweep (D-07)."
  type        = string
  default     = "microservices-demo"
}
```

**`layers/10-infra/README.md`** — one paragraph: what lands here, in which phase, and "this layer is a stub until Phase 2".

No `main.tf`, no `outputs.tf`, no `.tf` file declaring resources. That is the whole stub.

### Does `terraform init -backend-config=...` succeed with zero resources?

**Yes.** `init` is concerned with backend setup, provider installation and module installation. Zero `resource` blocks is a perfectly valid configuration — it is exactly what `terraform init` in an empty directory does, and adding a backend changes nothing about that. The backend is contacted to check for existing state; finding none, Terraform treats the workspace as empty.

One behaviour worth stating explicitly so the plan's verification step expects the right thing: **`init` alone does not create the state object in S3.** `s3://…/infra/terraform.tfstate` will **not** exist after initialising a stub layer. The object is written on the first state persist (first `apply`, or an `import`/`state` subcommand). So a Phase 1 verification task must assert:

```bash
# CORRECT assertion for a stub layer after init:
test -f layers/10-infra/.terraform/terraform.tfstate
jq -e '.backend.type == "s3"' layers/10-infra/.terraform/terraform.tfstate

# WRONG — this will fail, and it is not a bug:
# aws s3api head-object --bucket "$BUCKET" --key infra/terraform.tfstate
```

Corollary: the bootstrap flow only needs to `init` the three stubs to **prove the backend config is valid**; it must not try to `apply` them.

### Does `terraform validate` need `init` first?

**Yes** — and there is a purpose-built flag for validating without touching the backend:

> *"Validation requires an initialized working directory with any referenced plugins and modules installed. To initialize a working directory for validation without accessing any configured backend, use: `terraform init -backend=false`"*

[CITED: [`v1.16.x/docs/cli/commands/validate.mdx:27-30`](https://github.com/hashicorp/web-unified-docs/blob/main/content/terraform/v1.16.x/docs/cli/commands/validate.mdx)]

This is important for two places in this phase:

1. **CI / `make validate`** can validate all four layers with **no AWS credentials at all** — which means the D-12 scheduled sweep and PR checks stay cheap, and a validation job cannot accidentally touch state:
   ```makefile
   .PHONY: validate
   validate:
   	@set -euo pipefail; \
   	for d in layers/*/; do \
   	  echo "==> validate $$d"; \
   	  terraform -chdir="$$d" init -backend=false -input=false >/dev/null; \
   	  terraform -chdir="$$d" validate; \
   	done; \
   	terraform fmt -recursive -check -diff
   ```
2. **Step 1 of `make bootstrap`** already uses `-backend=false` for the same reason.

> ⚠️ Running `init -backend=false` and later `init -backend-config=...` in the **same directory** requires `-reconfigure` on the second call, because Terraform detects the backend changed from "none" to "s3". The `make validate` target above is therefore mildly destructive to a bootstrapped working directory's `.terraform/` state. Either run `validate` in CI only, or have it operate on a throwaway copy, or have `make bootstrap` always pass `-reconfigure`/`-force-copy` as the decision table above prescribes.

---

## Version Pinning — Verified

All four pins from ARCHITECTURE.md Decision 2 within this slice's scope were checked live against the authoritative registries on **2026-09-25**.

| Pin | Claimed | Exists? | Evidence | Verdict |
|---|---|---|---|---|
| **Terraform** | `1.16.4` | ✅ **Yes — and it is the current latest stable** | `GET https://api.releases.hashicorp.com/v1/releases/terraform/latest` → `1.16.4`, `timestamp_created: 2026-09-23T12:45:12.385Z`. `https://releases.hashicorp.com/terraform/1.16.4/` → `HTTP 200`. | [VERIFIED] **Pin as-is.** |
| **`hashicorp/aws`** | `6.66.0` | ✅ **Yes — current latest** | `GET https://registry.terraform.io/v1/providers/hashicorp/aws` → `.version == "6.66.0"`; tail of `.versions` = `…6.64.0, 6.65.0, 6.66.0`. Direct `/v1/providers/hashicorp/aws/6.66.0` → `6.66.0`. | [VERIFIED] **Pin as-is.** |
| `terraform-aws-modules/vpc` | `6.7.3` | — | Out of this slice's scope (Phase 2 layer). | Deferred to the VPC/EKS research slice. |
| `terraform-aws-modules/eks` | `21.26.0` | — | Out of scope here. ARCHITECTURE.md records its floor as `terraform >= 1.5.7`, `aws >= 6.59` — **both satisfied** by 1.16.4 / 6.66.0. | Compatible. |
| `RaJiska/fck-nat` | `1.6.1` | — | Out of scope here. | Deferred. |

**Two notes on the freshness of these pins:**

1. Terraform 1.16.4 was released **two days ago** (2026-09-23). Pinning to a release this new is a real (if small) risk — point releases occasionally regress. It is also the *most* patched 1.16.x, so on balance correct. The plan should simply record the release date in `VERSIONS.md` so a future reader knows how fresh the pin was when chosen.
2. `1.17.0-beta2` exists in the release index. **Do not pin to it.** Pre-releases are not covered by `required_version = "= 1.16.4"` semantics in a useful way and tfenv will happily install them.

### `.terraform-version` file format

Plain text, **one line, bare version string, no operator, no `v` prefix**:

```
1.16.4
```

`.terraform-version` is read by **tfenv** and **tfswitch**, both of which look for the file in the current directory and then walk up parent directories. Resolution order in tfenv is `TFENV_TERRAFORM_VERSION` env var **first**, then `.terraform-version`, defaulting to `latest` if neither is found. [CITED: [tfutils/tfenv README](https://github.com/tfutils/tfenv/blob/master/README.md), §`.terraform-version` File / §`TFENV_TERRAFORM_VERSION`]

Place it at the **repo root**, not per-layer — one Terraform binary serves all four layers.

### How `.terraform-version` and `required_version` interact

They are **completely independent mechanisms that do not validate each other**, which is precisely why D-36 mandates both:

| | `.terraform-version` | `required_version` |
|---|---|---|
| Read by | tfenv / tfswitch (version *managers*) | Terraform itself |
| Effect | **Selects which binary runs** | **Rejects** the run if the running binary doesn't match |
| When | Before Terraform starts | At `init`/`plan`/`apply` time |
| If absent | tfenv falls back to `latest` | Any version is accepted |

The failure mode D-36 defends against: a contributor without tfenv installed runs their system Terraform 1.14; `.terraform-version` is ignored entirely; `required_version = "= 1.16.4"` catches it with a clear error instead of letting a mismatched binary rewrite state. Conversely, a contributor *with* tfenv gets the right binary automatically and never sees the error. **Both, or neither works.**

tfenv can cross-check them — `tfenv install latest-allowed` / `tfenv use min-required` parse `required_version` out of the `.tf` files — but this only works with **range** operators. With an exact pin (`= 1.16.4`) they are trivially the same value, so the only real safeguard is that `make doctor` asserts the two agree (see below).

Add to `.gitignore` alongside the D-16 entries:

```gitignore
# Generated backend config (D-16) — contains the AWS account ID
backend.hcl

# Terraform working dirs and local state
**/.terraform/
*.tfstate
*.tfstate.*
*.tfstate.backup

# Variables carrying the alert email (D-24) and other secrets
*.tfvars
!*.tfvars.example

# Teardown report (D-11)
.teardown-report.json
```

> ⚠️ `*.tfstate*` **must** be gitignored before the first `make bootstrap`, because step 1 applies with a local backend and writes `terraform.tfstate` containing the account ID into the working tree. Getting this wrong commits it. The plan should order the `.gitignore` task **before** the bootstrap task.

### Recommended `VERSIONS.md` shape

Single table, one row per pinned artifact, with the *exact* pin string as it appears in code so a reviewer can grep for drift:

```markdown
# VERSIONS.md

Every version in this project is pinned to an **exact** version (D-36) — never a
`~>` range. This file is the single source of truth. If you change a version,
change it here **and** in the file named in the "Pinned in" column, in the same commit.

Last verified against upstream registries: **2026-09-25**

| Artifact | Version | Pin syntax (verbatim) | Pinned in | Source of truth |
|---|---|---|---|---|
| Terraform CLI | 1.16.4 | `1.16.4` | `.terraform-version` | [releases.hashicorp.com](https://releases.hashicorp.com/terraform/1.16.4/) |
| Terraform CLI | 1.16.4 | `required_version = "= 1.16.4"` | `layers/*/versions.tf` | same |
| `hashicorp/aws` | 6.66.0 | `version = "= 6.66.0"` | `layers/*/versions.tf` | [registry](https://registry.terraform.io/providers/hashicorp/aws/6.66.0) |
| `terraform-aws-modules/vpc` | 6.7.3 | `version = "6.7.3"` | `layers/10-infra/vpc.tf` *(Phase 2)* | [registry](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.7.3) |
| `terraform-aws-modules/eks` | 21.26.0 | `version = "21.26.0"` | `layers/10-infra/eks.tf` *(Phase 2)* | [registry](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.26.0) |
| `RaJiska/fck-nat` | 1.6.1 | `version = "1.6.1"` | `layers/10-infra/nat.tf` *(Phase 2)* | [registry](https://registry.terraform.io/modules/RaJiska/fck-nat/aws/1.6.1) |

## Constraint floors (informational — do not relax the exact pins above)

| Consumer | Requires |
|---|---|
| S3 backend `use_lockfile` (GA) | Terraform >= 1.11.0 |
| `terraform-aws-modules/eks` 21.x | Terraform >= 1.5.7, `aws` >= 6.59, `time` >= 0.9, `tls` >= 4.0 |

## Deliberately NOT used

| Thing | Why |
|---|---|
| DynamoDB state-lock table | Deprecated since Terraform 1.11 in favour of `use_lockfile`. Contradicts PROJECT.md; see ADR. |
| `kubernetes` provider | Removed as a requirement by EKS module v21. Do not reintroduce. |
```

Note the **two rows for Terraform**. That is intentional — the version appears in two files with two different syntaxes, and `make doctor` checks that both agree.

---

## `make doctor` Preflight Checks

D-33. Every check is independent, every failure is actionable, and the target reports **all** failures rather than dying on the first one — an operator should fix everything in one pass, not play whack-a-mole.

**`scripts/doctor.sh`:**

```bash
#!/usr/bin/env bash
set -uo pipefail   # deliberately NOT -e: we want to run every check

readonly EXPECTED_REGION="us-east-1"
readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILED=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n     \033[33m→ %s\033[0m\n' "$1" "$2"; FAILED=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "make doctor — preflight for $(basename "$ROOT")"
echo

# ---------------------------------------------------------------- 1. AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
  fail "AWS CLI not found" \
       "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
else
  # aws --version prints e.g. "aws-cli/2.15.30 Python/3.11.8 darwin/23.4.0 exe/x86_64"
  AWS_RAW="$(aws --version 2>&1)"
  AWS_VER="${AWS_RAW#aws-cli/}"; AWS_VER="${AWS_VER%% *}"
  AWS_MAJOR="${AWS_VER%%.*}"
  if [ "$AWS_MAJOR" != "2" ]; then
    fail "AWS CLI is v${AWS_VER}; this project requires v2" \
         "v1 lacks commands used by verify-teardown.sh. Upgrade: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  else
    ok "AWS CLI v${AWS_VER}"
  fi
fi

# ------------------------------------------------------------------------ 2. jq
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found" "Install it: 'brew install jq' (macOS) or 'apt-get install -y jq' (Debian/Ubuntu)"
else
  ok "jq $(jq --version | sed 's/^jq-//')"
fi

# ------------------------------------------------- 3. Credentials valid + account
CALLER_JSON="$(aws sts get-caller-identity --output json 2>&1)"
if [ $? -ne 0 ]; then
  fail "AWS credentials are not valid" \
       "aws sts get-caller-identity failed: $(printf '%s' "$CALLER_JSON" | tr '\n' ' ' | cut -c1-160)
       → Run 'aws configure' or 'aws sso login', or export AWS_PROFILE."
else
  ACTUAL_ACCOUNT="$(jq -r '.Account' <<<"$CALLER_JSON")"
  ACTUAL_ARN="$(jq -r '.Arn' <<<"$CALLER_JSON")"

  if [ -f "$ROOT/.aws-account-id" ]; then
    EXPECTED_ACCOUNT="$(tr -d '[:space:]' < "$ROOT/.aws-account-id")"
    if [ "$ACTUAL_ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
      fail "Credentials point at account ${ACTUAL_ACCOUNT}, expected ${EXPECTED_ACCOUNT}" \
           "You are pointed at the WRONG AWS ACCOUNT. Identity: ${ACTUAL_ARN}
       → Fix AWS_PROFILE / AWS_ACCESS_KEY_ID, or update .aws-account-id if the account genuinely changed."
    else
      ok "Account ${ACTUAL_ACCOUNT} (${ACTUAL_ARN##*/})"
    fi
  else
    warn "No .aws-account-id pin file; cannot verify the target account."
    warn "Currently authenticated to ${ACTUAL_ACCOUNT} as ${ACTUAL_ARN}"
    warn "Create it with: echo ${ACTUAL_ACCOUNT} > .aws-account-id   # gitignored"
  fi
fi

# ------------------------------------------------------------------- 4. Region
EFFECTIVE_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}"
if [ "$EFFECTIVE_REGION" != "$EXPECTED_REGION" ]; then
  fail "Effective AWS region is '${EFFECTIVE_REGION:-<unset>}', expected '${EXPECTED_REGION}'" \
       "Every price in COSTS.md is ${EXPECTED_REGION}-denominated (D-02).
       → export AWS_REGION=${EXPECTED_REGION}"
else
  ok "Region ${EFFECTIVE_REGION}"
fi

# ----------------------------------------------------- 5. Terraform version pin
if ! command -v terraform >/dev/null 2>&1; then
  fail "terraform not found" "Install tfenv then run 'tfenv install' (it reads .terraform-version)"
elif [ ! -f "$ROOT/.terraform-version" ]; then
  fail ".terraform-version is missing" "Create it at the repo root containing exactly the pinned version (D-36)"
else
  WANT="$(tr -d '[:space:]' < "$ROOT/.terraform-version")"
  HAVE="$(terraform version -json 2>/dev/null | jq -r '.terraform_version')"
  if [ "$HAVE" != "$WANT" ]; then
    fail "Terraform ${HAVE} is on PATH but .terraform-version pins ${WANT}" \
         "Run 'tfenv install ${WANT} && tfenv use ${WANT}' (or 'tfswitch ${WANT}')"
  else
    ok "Terraform ${HAVE}"
  fi

  # cross-check the pin against required_version (the two-file hazard, D-36)
  RV="$(grep -hoE 'required_version[[:space:]]*=[[:space:]]*"= [0-9.]+"' \
          "$ROOT"/layers/*/versions.tf 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  if [ -z "$RV" ]; then
    warn "No exact required_version found in layers/*/versions.tf"
  elif [ "$(wc -l <<<"$RV")" -ne 1 ]; then
    fail "Layers disagree on required_version: $(tr '\n' ' ' <<<"$RV")" \
         "All layers must pin the same exact version. Reconcile against VERSIONS.md."
  elif [ "$RV" != "$WANT" ]; then
    fail "required_version pins ${RV} but .terraform-version says ${WANT}" \
         "These must match (D-36). Update both, plus VERSIONS.md, in one commit."
  else
    ok "required_version (= ${RV}) agrees with .terraform-version"
  fi
fi

# --------------------------------------------------------- 6. Required tfvars
TFVARS="$ROOT/layers/00-bootstrap/terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  fail "layers/00-bootstrap/terraform.tfvars is missing" \
       "Copy the template and fill it in: cp layers/00-bootstrap/terraform.tfvars.example ${TFVARS#$ROOT/}
       → It is gitignored; it holds alert_email, github_owner and github_repo (D-24/D-26)."
else
  for KEY in alert_email github_owner github_repo; do
    VAL="$(grep -E "^[[:space:]]*${KEY}[[:space:]]*=" "$TFVARS" 2>/dev/null \
           | head -1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d '[:space:]')"
    if [ -z "$VAL" ]; then
      fail "tfvars key '${KEY}' is missing or empty" \
           "Set ${KEY} in ${TFVARS#$ROOT/} — required by $( [ "$KEY" = alert_email ] && echo 'the SNS cost-alert subscription (D-24)' || echo 'the OIDC trust policy sub claim (D-26)' )"
    else
      case "$KEY" in
        alert_email)
          if [[ ! "$VAL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
            fail "alert_email '${VAL}' is not a valid email address" \
                 "SNS will silently never deliver. Fix it in ${TFVARS#$ROOT/}."
          else
            ok "alert_email set (${VAL%%@*}@…)"
          fi ;;
        *) ok "${KEY} = ${VAL}" ;;
      esac
    fi
  done
fi

# ------------------------------------------------------------- 7. gitignore safety
for PAT in 'backend.hcl' '*.tfstate' '*.tfvars'; do
  if ! grep -qF -- "$PAT" "$ROOT/.gitignore" 2>/dev/null; then
    fail ".gitignore does not cover '${PAT}'" \
         "This risks committing the AWS account ID or the alert email (D-16/D-24). Add it before running 'make bootstrap'."
  fi
done
grep -qF 'backend.hcl' "$ROOT/.gitignore" 2>/dev/null && ok ".gitignore covers generated/secret files"

echo
if [ "$FAILED" -ne 0 ]; then
  echo "doctor: FAILED — fix the items marked ✗ above, then re-run 'make doctor'."
  exit 1
fi
echo "doctor: all checks passed."
```

Wired into the Makefile, and made a hard prerequisite of anything that touches AWS:

```makefile
.PHONY: doctor
doctor:
	@bash scripts/doctor.sh

bootstrap: doctor
verify-teardown: doctor
```

Design notes:
- **`set -uo pipefail`, not `-e`.** The whole point is to report every problem at once.
- **`.aws-account-id`** is a gitignored one-line pin file. It is what turns "credentials work" into "credentials point at the *right* account" — the check that prevents applying a budget and an OIDC provider into an employer's account. It should be written by the first successful `make bootstrap`.
- `terraform version -json | jq -r .terraform_version` is the robust parse; `terraform version` plain-text output has changed format historically and also appends an "out of date" notice line.
- The `required_version` cross-check catches the D-36 failure mode where someone bumps one file and not the other.

---

## Gotchas & Landmines

1. **`use_lockfile` defaults to `false`.** [CITED: s3.mdx:56] Omitting it from `backend.hcl` gives you an unlocked backend with **no warning whatsoever**. Because `backend.hcl` is *generated* (D-16), a bug in the generator silently disables locking across all four layers. **`make doctor` — or better, a post-init assertion — should grep the generated `backend.hcl` for `use_lockfile = true`.**

2. **`-backend-config` paths resolve relative to `-chdir`.** D-16's literal `../backend.hcl` is only correct for one specific layout. Use an absolute path from the Makefile.

3. **`-migrate-state` prompts; `-force-copy` does not.** With `-input=false` and no `-force-copy`, the migration step **fails** rather than proceeding. But `-force-copy` on the wrong branch **overwrites good remote state with stale local state** — the worst outcome available in this phase. Gate it strictly on "remote state does not exist".

4. **`prevent_destroy` only accepts literals.** *"only literal values can be used because the processing happens too early for arbitrary expression evaluation"* [CITED: lifecycle.mdx:31-32]. No `var.allow_nuke`, no `-var`, no environment override. `make nuke-bootstrap` must edit the file.

5. **`prevent_destroy` blocks replacement, not just destruction.** Changing `var.region` changes the bucket name, which is `ForceNew`, which the guard rejects **at plan time**. D-02's "costly reversibility" is now a hard tool-enforced wall. Document it.

6. **Destroying L0 requires migrating state *back* to local first.** You cannot destroy the bucket your state lives in. This is the chicken-and-egg in reverse and is easy to forget when writing `nuke-bootstrap`.

7. **A versioned bucket cannot be destroyed while it holds any version or delete marker.** `force_destroy = true` would fix it but must **not** be set on a state bucket — a stray `terraform destroy` would then eat all state history without complaint. Empty it explicitly instead.

8. **`.tflock` never expires.** No TTL, no lease. A `SIGKILL`ed apply or a cancelled CI job wedges the layer permanently until someone runs `force-unlock` with the exact ID. For a nightly up/down project this **will** happen. Ship `make unlock` in this phase, not after the first incident.

9. **`force-unlock` requires an exact ID match** [VERIFIED: `client.go:540-546`]. A corrupt or truncated `.tflock` makes `force-unlock` itself fail; the fallback is `aws s3api delete-object` on the `.tflock` key.

10. **The `s3:prefix` condition in HashiCorp's own IAM example is wrong** — it includes the bucket name, which `s3:prefix` never does. Copying it produces a `ListBucket` grant that matches nothing, and the failure surfaces as a confusing backend error rather than an AccessDenied on List.

11. **`aws_s3_bucket_lifecycle_configuration` `filter` rules.** Must be `filter {}` **or** exactly one of `prefix` / `tag` / `and` / `object_size_greater_than` / `object_size_less_than`. Two predicates directly inside `filter` is a plan-time error — wrap them in `and {}`. And *"a rule cannot be updated from having a filter … to only having a prefix"* [CITED: provider 6.66.0 docs], so getting this wrong the first time requires destroying and recreating the lifecycle configuration.

12. **`rule.prefix` and `expected_bucket_owner` are Deprecated** on the lifecycle resource in provider 6.66.0 and go away in 7.x. Do not use either.

13. **`terraform validate` requires `init`**, but `init -backend=false` is the credential-free path [CITED: validate.mdx:27-30]. Mixing `-backend=false` and `-backend-config` inits in the same directory needs `-reconfigure`.

14. **A stub layer's state object does not exist after `init`.** Only after a state write. Any Phase 1 verification asserting `head-object` on `infra/terraform.tfstate` will fail — correctly. Assert on `.terraform/terraform.tfstate`'s `.backend.type` instead.

15. **`.gitignore` must land before the first `make bootstrap`**, because step 1 writes a local `terraform.tfstate` containing the AWS account ID into the working tree. Order the tasks accordingly.

16. **SSE-KMS on the state bucket costs $1/month for the key** — 20% of the D-25 budget — before any per-request charges on every state read, write, lock and unlock. Use `AES256` (SSE-S3), which is free.

17. **Restoring an old state version rolls `serial` backwards.** S3 does not stop you. Never restore across a differing `lineage`.

18. **`aws --version` writes to stderr on some versions.** The parse must use `2>&1`, as in the doctor script above.

---

## Open Questions

1. **Where does `backend.hcl` live — repo root or `layers/`?** D-16 writes `-backend-config=../backend.hcl`, which implies `layers/backend.hcl`. This slice recommends the **repo root** with an absolute path from the Makefile, which contradicts the literal text of D-16. *Recommendation: adopt repo-root + absolute path, and have the planner note the D-16 wording as clarified rather than changed.* Needs a one-line ruling before the plan is written.

2. **`noncurrent_days` value.** This slice proposes `30` with `newer_noncurrent_versions = 10`. D-18 does not specify a retention window. Thirty days is a defensible default for a practice account, but it is a **product decision about how far back recovery reaches** and should be confirmed rather than assumed. [ASSUMED — needs user confirmation]

3. **Is `.aws-account-id` acceptable?** The doctor check that prevents applying into the wrong AWS account depends on a gitignored pin file. An alternative is a committed `allowed_account_ids` on the provider block (a first-class Terraform feature) — but that would commit the account ID, which D-16/D-17 explicitly avoid. *Recommendation: `.aws-account-id`, gitignored, written by the first successful bootstrap.* Needs confirmation that the extra untracked file is acceptable.

4. **PROJECT.md still says "S3 + DynamoDB state locking."** ARCHITECTURE.md flags the contradiction; this slice confirms DynamoDB locking is deprecated as of Terraform 1.11 and should not be adopted. **The plan needs an explicit task to amend PROJECT.md's requirement text** — otherwise the phase ships in documented violation of its own requirements. Out of this slice's authority to change.

5. **Which lock-demonstration method becomes the committed evidence artifact for success criterion 2?** This slice recommends Method 1 (`list-object-versions`, post-hoc, race-free) as primary with Method 3 (contention) as the proof of exclusion. Whether that is captured as a script (`scripts/demo-state-lock.sh`) or as a one-time recorded output in the phase artifacts is a planner decision.

6. **`00-bootstrap` CloudWatch log groups (D-23).** Nothing in D-20's L0 contents list (state bucket, OIDC provider + 2 roles, Budget, anomaly monitor, SNS topic) natively emits CloudWatch logs, so there may be **zero** log groups to declare in this phase. D-23 may therefore be establishing a convention with no Phase 1 instance. *Needs confirmation that "no log groups in Phase 1" satisfies D-23, or identification of which resource is expected to produce one.* [ASSUMED]

---

# Part C — OIDC Federation & Teardown Sweep

## GitHub Actions to AWS OIDC Federation

### The OIDC provider resource (D-29)

`thumbprint_list` is **no longer required** — neither by the AWS API nor by the Terraform provider.
The `hashicorp/aws` docs are now explicit that for GitHub specifically AWS uses its own trusted-root
CA store and **ignores any configured thumbprint**:

> `thumbprint_list` - (Optional) List of server certificate thumbprints … For certain OIDC identity
> providers (e.g., Auth0, GitHub, GitLab, Google, or those using an Amazon S3-hosted JWKS endpoint),
> AWS relies on its own library of trusted root certificate authorities (CAs) for validation instead
> of using any configured thumbprints. In these cases, any configured `thumbprint_list` is retained
> in the configuration but not used for verification.

`[VERIFIED: hashicorp/aws website/docs/r/iam_openid_connect_provider.html.markdown — Argument Reference]`
(<https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/iam_openid_connect_provider.html.markdown>)

The provider docs ship an explicit **"Without A Thumbprint"** example, so omitting the argument is a
first-class supported shape, not a workaround. `[VERIFIED: same file — Example Usage]`

AWS's own action README says the same thing about the CLI/console path:

> Prior versions of this documentation gave instructions for specifying the certificate fingerprint,
> but this is no longer necessary. The thumbprint, if specified, will be ignored.
> ```bash
> aws iam create-open-id-connect-provider \
>     --url https://token.actions.githubusercontent.com \
>     --client-id-list sts.amazonaws.com
> ```

`[VERIFIED: aws-actions/configure-aws-credentials README — "Configuring IAM to trust GitHub"]`
(<https://github.com/aws-actions/configure-aws-credentials#readme>)

> **Amendment to D-29 recommended.** D-29 says "a thumbprint is supplied to satisfy the API." That
> premise is now false on both sides: the API accepts creation without one, and the Terraform
> argument is `Optional`. Supplying a dead 40-hex string that is documented as ignored is strictly
> worse than omitting it — it invites exactly the rotation automation D-29 forbids. **Omit
> `thumbprint_list` entirely and put the rationale in a code comment.** The D-29 *intent*
> (no rotation automation) is preserved and strengthened.
>
> Which `hashicorp/aws` minor made it optional was not authoritatively sourced this session.
> The phase pins `= 6.66.0` (D-36), which is far newer than any plausible cutover. `[UNVERIFIED]`

```hcl
# layers/00-bootstrap/oidc.tf

locals {
  gh_oidc_host = "token.actions.githubusercontent.com"

  # Exact literal sub claim values. NEVER a wildcard (D-26).
  gh_sub_main = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
  gh_sub_pr   = "repo:${var.github_owner}/${var.github_repo}:pull_request"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.gh_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list is deliberately omitted. AWS validates token.actions.githubusercontent.com
  # against its own trusted-root CA store; any thumbprint supplied here is retained in config but
  # never used for verification. Do NOT add thumbprint rotation automation (D-29).
}
```

Exports `aws_iam_openid_connect_provider.github.arn`, whose shape is
`arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`.
`[VERIFIED: configure-aws-credentials README — GitHub OIDC Trust Policy block]`

**Always reference the `.arn` attribute, never a hand-built string.** D-17's no-literal-account-ID
rule applies here too, and a typo'd hardcoded ARN produces a trust policy that silently never
matches.

---

### ⚠️ BLOCKING: immutable subject claims changed the `sub` format on 15 July 2026

This is the single highest-risk finding in this slice and it invalidates the naive reading of D-26.

> To help prevent this scenario, repositories created after July 15, 2026 now use an immutable
> default subject format that includes both the owner ID and repository ID. This rollout does not
> include GitHub Enterprise Server.
>
> * Syntax: `repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:refs/heads/BRANCH`
> * Previous format example: `repo:octo-org/octo-repo:ref:refs/heads/main`
> * Immutable format example: `repo:octo-org@123456/octo-repo@456789:ref:refs/heads/main`
>
> Repositories created before July 15, 2026 keep the previous format unless you opt in to immutable
> subject claims. … Repository renames and transfers after July 15, 2026 also move to the immutable
> subject format.

`[VERIFIED: docs.github.com/en/actions/reference/security/oidc — "Immutable subject claims"]`
(<https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims>)

AWS's own action README names the exact failure:

> If your trust policy matches the legacy name-only form and your repository emits the immutable
> claim, `AssumeRoleWithWebIdentity` fails with `Not authorized to perform
> sts:AssumeRoleWithWebIdentity`.

`[VERIFIED: configure-aws-credentials README — "Immutable subject claims"]`

**Consequence for this phase.** Today is 2026-09-25. `microservices-demo` is described in CONTEXT.md
as greenfield; if the GitHub repository backing it was **created on or after 2026-07-15**, or is
renamed/transferred after that date, the literal `sub` strings in D-26 will **never match** and both
CI roles are dead on arrival. Mitigations, in order of preference:

1. **Determine the format empirically before writing the trust policy.** The repo's owner-ID/repo-ID
   prefix is visible in repository Settings, or via the API:
   ```bash
   gh api repos/OWNER/REPO --jq '{owner: .owner.login, owner_id: .owner.id, repo: .name, repo_id: .id, created: .created_at}'
   ```
   If `created_at >= 2026-07-15T00:00:00Z`, the repo emits the immutable form.
2. **Make the format a variable, not a hardcoded string** (see HCL below) so the plan does not have
   to guess.
3. **Verify by running `github/actions-oidc-debugger` once** in the repo before the first real apply.
   GitHub documents this action for exactly this purpose.
   `[VERIFIED: docs.github.com/en/actions/reference/security/oidc — "Debugging your OIDC claims"]`
   Run it in a private repo only — the claim values may be sensitive.

> **This must be a `checkpoint:human-verify` task in the plan**, sequenced *before* the IAM roles are
> applied. It is a one-line lookup that prevents a debugging session with a completely opaque error.

---

### `pull_request` sub claim — verified

The `pull_request` sub value D-26 assumes is **correct**, with one documented precondition:

> The subject claim includes the `pull_request` string when the workflow is triggered by a pull
> request event, **but only if the job doesn't reference an environment.**
>
> * Syntax: `repo:ORG-NAME/REPO-NAME:pull_request`
> * Example: `repo:octo-org/octo-repo:pull_request`

`[VERIFIED: docs.github.com/en/actions/reference/security/oidc — "Filtering for `pull_request` events"]`

And the branch form, with the symmetric precondition:

> The subject claim includes the branch name of the workflow, **but only if the job doesn't reference
> an environment, and if the workflow is not triggered by a pull request event.**
>
> * Syntax: `repo:ORG-NAME/REPO-NAME:ref:refs/heads/BRANCH-NAME`

`[VERIFIED: same page — "Filtering for a specific branch"]`

**The precedence rule, stated plainly:** `environment` wins over `pull_request`, which wins over
`ref`. A job with `environment: prod` emits `repo:O/R:environment:prod` **regardless of trigger** —
so the moment someone adds an `environment:` key to the apply job for a manual-approval gate, the
`refs/heads/main` condition stops matching and the apply role breaks. This is a realistic future
regression for this project (a deploy-approval gate is a natural Phase 3+ addition).

> **Plan action:** put a one-line comment above the `environment:`-free apply job stating that adding
> `environment:` requires updating the trust policy `sub` in the same PR.

**Do NOT combine both sub values into one role's trust policy.** D-27's two-role split is the whole
point: a single `StringEquals` list containing both strings would let a PR assume the apply role.

---

## OIDC Trust Policy — Exact Shapes

Canonical AWS-published shape, for reference:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:ref:refs/heads/<BRANCH>"
        }
      }
    }
  ]
}
```

`[VERIFIED: configure-aws-credentials README — "GitHub OIDC Trust Policy"]` and
`[VERIFIED: docs.github.com/…/oidc-in-aws — "Configuring the role and trust policy"]`

### Terraform — both roles

```hcl
# layers/00-bootstrap/variables.tf
variable "github_owner" { type = string }
variable "github_repo"  { type = string }

# Set BOTH to null for repos created before 2026-07-15 that have not opted in to immutable
# subject claims. Set BOTH to the numeric IDs for repos created on/after that date.
# See: https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims
variable "github_owner_id" {
  type    = string
  default = null
}
variable "github_repo_id" {
  type    = string
  default = null
}
```

```hcl
# layers/00-bootstrap/oidc.tf (continued)

locals {
  # Immutable-subject-aware repo segment. Emits "octo-org/octo-repo" for legacy repos and
  # "octo-org@123456/octo-repo@456789" for repos created on or after 2026-07-15.
  gh_owner_seg = var.github_owner_id == null ? var.github_owner : "${var.github_owner}@${var.github_owner_id}"
  gh_repo_seg  = var.github_repo_id == null ? var.github_repo : "${var.github_repo}@${var.github_repo_id}"
  gh_repo_ref  = "repo:${local.gh_owner_seg}/${local.gh_repo_seg}"

  gh_sub_main = "${local.gh_repo_ref}:ref:refs/heads/main"
  gh_sub_pr   = "${local.gh_repo_ref}:pull_request"
}

# ---- Trust: plan role. Pull requests ONLY. ----
data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    sid     = "GitHubOIDCPullRequestOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # StringEquals, not StringLike. Exact literal. No wildcard anywhere. (D-26)
    condition {
      test     = "StringEquals"
      variable = "${local.gh_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.gh_oidc_host}:sub"
      values   = [local.gh_sub_pr]
    }
  }
}

# ---- Trust: apply role. refs/heads/main pushes ONLY. ----
data "aws_iam_policy_document" "gha_apply_trust" {
  statement {
    sid     = "GitHubOIDCMainBranchOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.gh_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.gh_oidc_host}:sub"
      values   = [local.gh_sub_main]
    }
  }
}

resource "aws_iam_role" "gha_terraform_plan" {
  name                 = "gha-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.gha_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "gha_terraform_apply" {
  name                 = "gha-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.gha_apply_trust.json
  max_session_duration = 3600
}
```

**Do not name either role `GitHubActions`.** AWS's own README:

> _Note_: Naming your role "GitHubActions" has been reported to not work.
> See [#953](https://github.com/aws-actions/configure-aws-credentials/issues/953).

`[VERIFIED: configure-aws-credentials README — "OIDC Configuration Details"]`
`gha-terraform-plan` / `gha-terraform-apply` (D-27) are already clear of this.

### Plan role permissions — the `.tflock` trap

D-27 says the plan role gets "read-only + **state read/lock**". Those are in tension, and the
project's S3-native locking (`use_lockfile = true`, per PROJECT.md) is why:

`terraform plan` acquires a state lock by default. With `use_lockfile`, that lock is a real S3
object at `<state-key>.tflock` that must be **written** and then **deleted**. `ReadOnlyAccess` alone
cannot do this, so a plan job under a pure read-only role fails at lock acquisition, not at any
interesting place. Two viable resolutions:

```hcl
# Option A (matches D-27 literally): grant narrowly-scoped write on the lock object only.
data "aws_iam_policy_document" "gha_plan_state" {
  statement {
    sid       = "TerraformStateRead"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid       = "TerraformStateListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "TerraformNativeS3Lock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}
```

```yaml
# Option B: keep the role strictly read-only, never lock during plan.
- run: terraform plan -lock=false -no-color
```

Recommend **Option A** — it honours D-27 as written, the `*.tflock` suffix scoping is tight, and it
keeps `-lock=false` (a habit that is genuinely dangerous if it leaks into `apply`) out of the repo.

If the state bucket ends up SSE-**KMS** rather than SSE-S3, the plan role additionally needs
`kms:Decrypt` + `kms:GenerateDataKey` on the key. SSE-S3 (`AES256`) needs nothing extra. Confirm
which D-15 lands on. `[ASSUMED]`

Also attach `arn:aws:iam::aws:policy/ReadOnlyAccess` to the plan role — it is what makes the D-12
scheduled sweep work "with no new permissions". Whether `ReadOnlyAccess` covers
`tag:GetResources` was not verified this session; if the sweep returns `AccessDenied` on the tag
layer, add an explicit `tag:GetResources` / `tag:GetTagKeys` allow. `[ASSUMED]`

### Apply role permissions (D-28) — the deny list that must not eat its own budget

```hcl
data "aws_iam_policy_document" "gha_apply_guardrails" {
  statement {
    sid    = "DenyOrgsAccountClosureAndBillingConfig"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:CloseAccount",
      "account:DisableRegion",
      "account:EnableRegion",
      "account:PutAlternateContact",
      "account:DeleteAlternateContact",
      "billing:*",
      "payments:*",
      "invoicing:*",
      "consolidatedbilling:*",
      "purchase-orders:*",
      "tax:*",
      "freetier:*",
      "aws-portal:*",
      # Enforces the no-long-lived-credentials rule structurally, not by convention:
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }
}
```

> **Landmine:** do **not** add `budgets:*` or `ce:*` to this deny list. This very phase's Terraform
> creates an `aws_budgets_budget` and an `aws_ce_anomaly_monitor`/`aws_ce_anomaly_subscription`.
> "Billing configuration" in D-28 must be read as *payment method / invoicing / tax settings*, not
> *cost controls*. A deny on `budgets:*` makes the apply role unable to manage the guardrail it
> exists to protect, and the failure is a confusing `AccessDenied` on a resource the same role just
> created.

Explicit `Deny` beats any `Allow`, including `AdministratorAccess`, so attaching both is safe:

```hcl
resource "aws_iam_role_policy_attachment" "gha_apply_admin" {
  role       = aws_iam_role.gha_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "gha_apply_guardrails" {
  name   = "phase1-broad-apply-guardrails"
  role   = aws_iam_role.gha_terraform_apply.id
  policy = data.aws_iam_policy_document.gha_apply_guardrails.json

  # TEMPORARY (D-28). Phase 10 replaces AdministratorAccess with a CloudTrail /
  # IAM Access Analyzer-derived least-privilege policy. This is a scheduled posture,
  # not an oversight.
}
```

The `aws-portal:*` prefix is legacy; AWS split it into the fine-grained `billing`/`payments`/`tax`/
`consolidatedbilling`/`invoicing`/`account` prefixes. Keeping both costs nothing. The exact
migration date was not sourced this session. `[ASSUMED]`

---

## Pitfall 36 — Loose Trust Failure Modes

Every broken policy below is copy-pasteable into a review checklist. All five have been observed in
the wild; the first and last are catastrophic.

### 36a — No `sub` condition at all: "any GitHub repo on Earth"

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" }
  }
}
```

**Impact:** any workflow in **any repository owned by anyone** can mint a token with
`aud=sts.amazonaws.com` and assume this role. `aud` is a constant string shared by every AWS user of
GitHub OIDC — it is not an identity. GitHub states this as a hard requirement, not advice:

> To control how your cloud provider issues access tokens, you **must** define at least one
> condition, so that untrusted repositories can’t request access tokens for your cloud resources.

`[VERIFIED: docs.github.com/…/oidc — "OIDC claims used to define trust conditions on cloud roles"]`

**Reviewer tell:** the `Condition` block mentions `:aud` but never `:sub`.

### 36b — Wildcard owner: `repo:owner/*`

```json
"StringLike": { "token.actions.githubusercontent.com:sub": "repo:my-org/*" }
```

**Impact:** every repository under the org — including a brand-new repo any org member can create,
and including repos whose workflows are not reviewed — gets the apply role. For a *personal* account
(D-03) this is worse than it sounds: creating a new repo under your own username is a two-click
operation, and any workflow you paste into it inherits production AWS.

**Reviewer tell:** a `*` anywhere to the right of the org name.

### 36c — Missing `aud` condition

```json
"StringEquals": { "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main" }
```

**Impact:** subtler than 36a and often waved through. The `aud` claim is workflow-controllable —
`core.getIDToken(audience)` and the action's `audience:` input both set it freely. Omitting the `aud`
condition means a token minted for a *different* audience (e.g. an Azure or Vault integration living
in the same repo) is accepted by AWS. It widens the set of workflow steps that can produce an
AWS-usable token from "the ones that call configure-aws-credentials" to "any step that can reach the
OIDC endpoint". `[VERIFIED: docs.github.com/…/oidc — "Customizing the `audience` value"]`

**Reviewer tell:** `:sub` present, `:aud` absent.

### 36d — `StringLike` where `StringEquals` belongs

```json
"StringLike": { "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main" }
```

**Impact:** functionally identical *today* — `StringLike` with no metacharacter behaves like
`StringEquals`. The damage is cultural: the operator is now the "normal" one in this codebase, and
the next person who edits the string adds a `*` without a second thought. D-26 locks `StringEquals`
precisely to make adding a wildcard an operator change that shows up in review.

**Reviewer tell:** `StringLike` with a literal value. Flag it even though it currently works.

### 36e — Branch wildcard: fork and feature-branch escalation

```json
"StringLike": { "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/*" }
```

**Impact:** anyone who can push a branch — which on a public repo with collaborators, or via a
`workflow_dispatch` on a feature branch, is a wide set — gets the **apply** role. The whole purpose
of D-27's two-role split is that `main` is protected and PR branches are not. A `refs/heads/*`
wildcard collapses that distinction and restores the exact risk the split was created to remove.

Its sibling, `repo:my-org/my-repo:*`, additionally matches `:pull_request` and
`:environment:<anything>`, so it hands the apply role to every PR as well. GitHub's own docs show
this wildcard form as an *example of breadth*, not a recommendation:

> In the following example, `StringLike` is used with a wildcard operator (`*`) to allow any branch,
> pull request merge branch, or environment from the `octo-org/octo-repo` organization and repository
> to assume a role in AWS.

`[VERIFIED: docs.github.com/…/oidc-in-aws — "Configuring the role and trust policy"]`

**Reviewer tell:** `*` after `:ref:refs/heads/` or immediately after the repo name.

### 36f — `ForAllValues:` in an `Allow` (bonus, AWS-flagged)

> **Warning:** Avoid `ForAllValues:` in `Allow` statements. These operators return true when the
> claim is absent or misspelled, which can lead to unintended access. Instead, use `StringEquals` or
> `StringLike` operators to check for specific claim values.

`[VERIFIED: configure-aws-credentials README — "Claims and scoping permissions"]`

**Reviewer tell:** any `ForAllValues:` / `ForAnyValue:` prefix in a trust policy. Also note that a
**misspelled condition key** (`token.actions.githubusercontent.com:subject`) silently never matches
under `StringEquals` (fails closed, annoying) but can fail *open* under set operators (dangerous).

### Review checklist (paste into the PR template)

- [ ] `Action` is exactly `sts:AssumeRoleWithWebIdentity` — not `sts:AssumeRole`.
- [ ] `Principal.Federated` is the `.arn` attribute of the OIDC provider resource, not a literal.
- [ ] `:aud` condition present, `StringEquals`, value `sts.amazonaws.com`.
- [ ] `:sub` condition present, `StringEquals`, **zero** `*` characters.
- [ ] The `sub` string's repo segment matches the repo's actual (legacy vs immutable) format.
- [ ] The plan role's `sub` ends `:pull_request`; the apply role's ends `:ref:refs/heads/main`.
- [ ] No `ForAllValues:` / `ForAnyValue:` anywhere.
- [ ] Neither role is named `GitHubActions`.

---

## Workflow-side requirements

Current action version: **`aws-actions/configure-aws-credentials@v6.3.0`**, floating major tag `v6`.

> Starting with version 5.0.0, this action uses semantic-style release tags and immutable releases.
> A floating version tag (vN) is also provided for convenience: this tag will move to the latest
> major version.

`[VERIFIED: configure-aws-credentials README — "Versioning"]`

Because D-36 mandates exact pins, use the **full `v6.3.0` tag** (or better, a commit SHA — GitHub's
own AWS example pins `@e3dd6a429d7300a6a4c196c26e071d42e0343502`
`[VERIFIED: docs.github.com/…/oidc-in-aws]`). Immutable releases mean a version tag cannot be
re-pointed, so `@v6.3.0` is now a genuinely strong pin; SHA-pinning is belt-and-braces.

```yaml
# .github/workflows/terraform-plan.yml
name: terraform-plan
on:
  pull_request:

permissions:
  contents: read     # required for actions/checkout
  id-token: write    # required to mint the OIDC JWT

jobs:
  plan:
    runs-on: ubuntu-latest
    # NOTE: do NOT add `environment:` here. Doing so changes the OIDC `sub` claim to
    # repo:<owner>/<repo>:environment:<name> and the gha-terraform-plan trust policy
    # will stop matching. Update the trust policy in the same PR if you ever need one.
    steps:
      - uses: actions/checkout@v6

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6.3.0
        with:
          role-to-assume: ${{ vars.AWS_PLAN_ROLE_ARN }}
          aws-region: us-east-1
          role-session-name: gha-plan-${{ github.run_id }}
          allowed-account-ids: ${{ vars.AWS_ACCOUNT_ID }}

      - run: aws sts get-caller-identity
```

- `permissions: id-token: write` is mandatory. Without it the JWT cannot be requested at all.
  `[VERIFIED: docs.github.com/…/oidc — "Workflow permissions for requesting the OIDC token"]`
  GitHub is explicit that it is not a privilege escalation: *"This setting only enables fetching and
  setting the OIDC token; it does not grant write access to other resources."*
- `contents: read` is needed for `actions/checkout`. `[VERIFIED: same]`
- `aws-region` is **always required**, for every auth mode. `[VERIFIED: README — Non-OIDC options table]`
- `role-session-name` defaults to `"GitHubActions"`. The README recommends
  `${{ github.run_id }}` *"so as to clarify in audit logs which AWS actions were performed by which
  workflow run"* `[VERIFIED: README — "Session Naming and Policies"]` — worth adopting given D-28's
  broad apply role, since CloudTrail session names are the only thing distinguishing runs.
- `allowed-account-ids` — *"The action will fail if we receive credentials for the wrong account"*
  `[VERIFIED: README — options table]`. Cheap defence-in-depth; complements `make doctor` (D-33).
- **No session tags with OIDC.** *"The action will use session tagging by default unless you are
  using OIDC or a Web Identity Token File."* `[VERIFIED: README]` So `role-skip-session-tagging`
  and `custom-tags` are irrelevant here — ignore any blog post telling you to set them.
- Set `role-to-assume` from a **repo variable** (`vars.`), not a secret. Role ARNs are not secrets,
  and keeping the secrets store literally empty is what makes success criterion 5 auditable.

**Recent breaking changes:** none affecting `role-to-assume`/`aws-region`/`role-session-name`; those
inputs are stable across v4→v6. The v5.0.0 change was release-tagging/immutability. A full v5 and v6
breaking-change list was not enumerated this session. `[UNVERIFIED]`

### The apply workflow

```yaml
name: terraform-apply
on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

concurrency:
  group: terraform-apply
  cancel-in-progress: false   # never cancel a half-applied state

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: aws-actions/configure-aws-credentials@v6.3.0
        with:
          role-to-assume: ${{ vars.AWS_APPLY_ROLE_ARN }}
          aws-region: us-east-1
          role-session-name: gha-apply-${{ github.run_id }}
          allowed-account-ids: ${{ vars.AWS_ACCOUNT_ID }}
```

**Never use `pull_request_target`** in this repo. It runs with the base repo's full token context and
is called out by name in AWS's security recommendations:

> Be especially careful about running Actions in non-ephemeral environments, or triggering workflows
> on `pull_request_target` events.

`[VERIFIED: configure-aws-credentials README — "Security Recommendations"]`

---

## Proving No Long-Lived Credentials

Success criterion 5 has two halves: nothing in AWS, nothing in GitHub. Both are scriptable; both
belong in `make doctor` (D-33) or a dedicated `make verify-no-keys` so the proof is repeatable rather
than a one-time screenshot.

### Half 1 — no IAM user access keys in the account

```bash
#!/usr/bin/env bash
# scripts/verify-no-access-keys.sh
set -euo pipefail

rc=0

# --- Root account access keys. get-account-summary is the crisp, one-call check. ---
root_keys=$(aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text)
if [[ "$root_keys" != "0" ]]; then
  echo "FAIL: root account has ${root_keys} access key(s). Delete them from the root user's" >&2
  echo "      Security Credentials page — this cannot be done via the CLI." >&2
  rc=1
else
  echo "OK: no root access keys (AccountAccessKeysPresent=0)"
fi

# --- IAM users and their keys. ---
mapfile -t users < <(aws iam list-users --query 'Users[].UserName' --output text | tr '\t' '\n' | grep -v '^$' || true)

if [[ ${#users[@]} -eq 0 ]]; then
  echo "OK: zero IAM users in the account"
else
  echo "NOTE: ${#users[@]} IAM user(s) exist; checking each for access keys"
  for u in "${users[@]}"; do
    keys=$(aws iam list-access-keys --user-name "$u" \
             --query 'AccessKeyMetadata[].{id:AccessKeyId,status:Status,created:CreateDate}' \
             --output json)
    n=$(jq 'length' <<<"$keys")
    if [[ "$n" -gt 0 ]]; then
      echo "FAIL: user '$u' has $n access key(s):" >&2
      jq -r '.[] | "  \(.id)  \(.status)  created \(.created)"' <<<"$keys" >&2
      rc=1
    else
      echo "OK: user '$u' has no access keys"
    fi
  done
fi

exit "$rc"
```

The credential report is the belt-and-braces cross-check — it covers the root user and every IAM
user in one artifact, including keys `list-users` could somehow miss:

```bash
aws iam generate-credential-report >/dev/null
# The report is generated asynchronously; retry until State=COMPLETE.
until aws iam generate-credential-report --query State --output text | grep -q COMPLETE; do :; done

aws iam get-credential-report --query Content --output text \
  | base64 --decode > /tmp/credential-report.csv

# Columns of interest: user, access_key_1_active, access_key_2_active.
# The root user appears as the literal string "<root_account>".
awk -F, 'NR==1 {for(i=1;i<=NF;i++) h[$i]=i; next}
         $h["access_key_1_active"]=="true" || $h["access_key_2_active"]=="true" {print "ACTIVE KEY: " $1}' \
  /tmp/credential-report.csv
```

`generate-credential-report` returning asynchronously and the `<root_account>` literal are from
training knowledge, not verified this session. `[ASSUMED]` The
`SummaryMap.AccountAccessKeysPresent` check above is the one to rely on for the root case.

**Also assert the negative stays true.** The `iam:CreateAccessKey` / `iam:CreateUser` denies in the
apply role (above) mean CI structurally cannot reintroduce a key. That converts a point-in-time check
into an invariant, which is what a success criterion should be.

### Half 2 — no AWS secrets in GitHub

```bash
# Repository secrets (Actions)
gh secret list --repo "$OWNER/$REPO" --app actions

# Dependabot and Codespaces have SEPARATE secret stores — check all three.
gh secret list --repo "$OWNER/$REPO" --app dependabot
gh secret list --repo "$OWNER/$REPO" --app codespaces

# Environment secrets live in yet another store, one per environment.
gh api "repos/$OWNER/$REPO/environments" --jq '.environments[].name' 2>/dev/null \
  | while read -r env; do
      echo "== environment: $env"
      gh secret list --repo "$OWNER/$REPO" --env "$env"
    done

# Variables are not secrets, but a role ARN lives here — confirm the ARNs are vars, not secrets.
gh variable list --repo "$OWNER/$REPO"
```

Assertion form — fail if any secret name looks AWS-shaped:

```bash
if gh secret list --repo "$OWNER/$REPO" --json name --jq '.[].name' \
     | grep -Eiq 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)|^AWS_'; then
  echo "FAIL: AWS-shaped secret present in GitHub repo secrets" >&2
  exit 1
fi
echo "OK: no AWS-shaped secrets in GitHub"
```

**The stronger assertion for this project: the secrets store should be _empty_**, not merely
AWS-free. Phase 1 introduces no secrets at all — role ARNs and the account ID are repo *variables*.
So assert `length == 0` and let a later phase relax it with a documented reason.

A `gh secret list --json name --jq` invocation shape and the exact `--app` enum values are from
training knowledge; `gh secret list --help` should be run once to confirm against the installed CLI
version. `[ASSUMED]`

---

## Teardown Sweep — Per-Class Enumeration

**Framing that governs every subsection below.** D-04 establishes a pre-flight **baseline
inventory**: run this exact sweep *before* anything is provisioned, and put every survivor on
`scripts/teardown-allowlist.txt`. That baseline is what turns "exclude AWS-managed noise" from an
open-ended heuristic problem into a closed one. Heuristics below are still worth implementing —
they keep the allowlist short and make a *new* AWS-managed resource self-explanatory rather than a
mystery orphan — but the allowlist is the backstop that guarantees a clean account reports zero.

Shared helper assumed available (defined in the architecture section):

```bash
# aws_json <region-or-GLOBAL> <args...>  — returns JSON on stdout, classifies failures
```

### ALBs / NLBs

```bash
aws elbv2 describe-load-balancers --region "$region" --output json \
  --query 'LoadBalancers[].{id:LoadBalancerName,arn:LoadBalancerArn,state:State.Code,type:Type,vpc:VpcId,created:CreatedTime}'
```

**Exclusions:** name/ARN on the allowlist. Nothing else — there is no AWS-managed default load
balancer, so on a genuinely empty account this returns `[]`.

**False-positive risk: very low.** The realistic wrinkle is `State.Code == "provisioning"` on a
just-created LB, which is a true orphan in a teardown context, not a false positive — report it.

**Gap to note:** `elbv2` does **not** cover Classic Load Balancers. D-07's list says "ALBs", so this
is in scope as written, but a Classic ELB created by an old console session would be invisible. One
extra call closes it:

```bash
aws elb describe-load-balancers --region "$region" --output json \
  --query 'LoadBalancerDescriptions[].{id:LoadBalancerName,dns:DNSName,vpc:VPCId}'
```
Recommend adding it — it is one call and Classic ELB is ~$16/mo. Flag as a scope note against D-07.

### Target groups

```bash
aws elbv2 describe-target-groups --region "$region" --output json \
  --query 'TargetGroups[].{id:TargetGroupName,arn:TargetGroupArn,proto:Protocol,vpc:VpcId,lbs:LoadBalancerArns}'
```

**Why this class exists separately:** deleting a load balancer does **not** delete its target groups.
They persist with `LoadBalancerArns: []` and are invisible in the EC2 console's load-balancer view.
They are free, so they never show on a bill — which is exactly why they accumulate, and why a
subsequent `terraform apply` can collide on a duplicate target-group name.

**Exclusions:** allowlist only. Optionally classify:
```bash
jq -r '.[] | . + {reason: (if (.lbs | length) == 0 then "orphaned: no load balancer attached" else "attached to live LB \(.lbs[0])" end)}'
```

**False-positive risk: very low** on an empty account.

### Security groups — the `default` SG trap

**This is the #1 false-positive generator in a naive sweep.** Every VPC — including the default VPC
that AWS pre-creates in every region of every new account — has exactly one `default` security group
that **cannot be deleted**. Enumerate SGs without excluding it and a pristine account reports one
"orphan" per region per VPC, forever. The sweep cries wolf on day one and everyone learns to ignore
it.

```bash
aws ec2 describe-security-groups --region "$region" --output json \
  --query 'SecurityGroups[?GroupName!=`default`].{id:GroupId,name:GroupName,vpc:VpcId,desc:Description,tags:Tags}'
```

Note the JMESPath backticks around `` `default` `` — that is a JSON literal. `'default'` (raw-string
quotes) also works in modern JMESPath but backticks are unambiguous.

Belt-and-braces: do the exclusion in `jq` too, so a JMESPath quoting regression cannot silently
disable it:

```bash
jq '[ .[] | select(.name != "default") ]'
```

**Controller-created SG heuristics.** The AWS Load Balancer Controller and Karpenter create SGs that
carry no `Project` tag unless propagation was configured — that is the entire reason D-07 has a
blind-spot layer. Discriminators, in descending order of reliability:

| Signal | Shape | Reliability |
|---|---|---|
| Tag key `elbv2.k8s.aws/cluster` | present on LB-controller-managed SGs | high `[ASSUMED]` |
| Tag key `kubernetes.io/cluster/<name>` | value `owned` or `shared` | high `[ASSUMED]` |
| `GroupName` prefix `k8s-` | `k8s-<namespace>-<ingress>-<hash>` | medium `[ASSUMED]` |
| `Description` contains the cluster name | controller-authored text | low |

Practical rule: **report every non-`default` SG not on the allowlist**, and use the tag/name signals
only to populate the `reason` field so the human table says *"ALB controller leftover"* instead of
*"unknown SG"*. Do not use the heuristics as the *filter* — an SG created by a console session has
none of these signals and is still an orphan. The `k8s-*`/tag shapes above are from training
knowledge, not verified against controller source this session. `[ASSUMED]`

**False-positive risk: HIGH if `default` is not excluded, low once it is.**

### EC2 instances — terminated instances are not orphans

Terminated instances remain visible in `describe-instances` for roughly an hour after termination
(and `shutting-down` for minutes). Neither costs anything. Including them means every teardown
reports phantom orphans for an hour after a *successful* teardown — which breaks Phase 2's
"two consecutive zero-orphan round-trips" gate outright, because the second round-trip runs inside
that window. The ~1h retention figure is training knowledge. `[ASSUMED]`

Filter server-side so the exclusion cannot be forgotten downstream:

```bash
aws ec2 describe-instances --region "$region" --output json \
  --filters 'Name=instance-state-name,Values=pending,running,stopping,stopped' \
  --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name,az:Placement.AvailabilityZone,launched:LaunchTime,tags:Tags}'
```

`stopped` and `stopping` are deliberately **included**: a stopped instance charges nothing for
compute but its root EBS volume bills continuously, and it is unambiguously a teardown failure.

**Exclusions:** allowlist. L0 creates no instances, so a clean account returns `[]`.

**False-positive risk: HIGH without the state filter, near-zero with it.**

### EBS volumes

```bash
aws ec2 describe-volumes --region "$region" --output json \
  --filters 'Name=status,Values=available' \
  --query 'Volumes[].{id:VolumeId,size:Size,type:VolumeType,az:AvailabilityZone,created:CreateTime,tags:Tags}'
```

`available` means detached. Attached (`in-use`) volumes belong to a live instance and are already
reported via the instance class — reporting both double-counts and muddies the table.

This class is the one D-13's test exercises: an untagged 1 GiB `gp3` volume lands here, which is why
this check must be reliable enough to be a test oracle.

**Exclusions:** allowlist. **False-positive risk: very low.**

### Snapshots — `--owner-ids self` is not optional

```bash
aws ec2 describe-snapshots --region "$region" --owner-ids self --output json \
  --query 'Snapshots[].{id:SnapshotId,size:VolumeSize,start:StartTime,desc:Description,volume:VolumeId,tags:Tags}'
```

**Omitting `--owner-ids self` enumerates every public snapshot on AWS** — hundreds of thousands of
AMI-backing snapshots, paginated, in every region. The script does not "find false positives", it
hangs for minutes and then floods the report with garbage. Treat the flag as load-bearing and put a
comment on the line saying so.

**Genuine false positive to handle: AMI-backing snapshots.** If the account owns a private AMI, its
backing snapshots are owned by `self` and appear here, but deleting them is wrong — they belong to
the image. Discriminators:

- `Description` begins `Created by CreateImage(i-...) for ami-...`
- Cross-reference: `aws ec2 describe-images --owners self --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId'`

Both are training knowledge. `[ASSUMED]` On the empty account of D-04 neither applies, but the
cross-reference is three lines and makes the check honest:

```bash
ami_snaps=$(aws ec2 describe-images --region "$region" --owners self --output json \
  --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' | jq -r '.[] // empty' | sort -u)
```

**False-positive risk: catastrophic without `--owner-ids self`; low with it.**

### Elastic IPs

```bash
aws ec2 describe-addresses --region "$region" --output json \
  --query 'Addresses[].{id:AllocationId,ip:PublicIp,assoc:AssociationId,instance:InstanceId,eni:NetworkInterfaceId,tags:Tags}'
```

Then filter for unassociated in `jq`, **not** JMESPath:

```bash
jq '[ .[] | select(.assoc == null) | . + {reason: "unassociated Elastic IP — billed hourly"} ]'
```

JMESPath's `[?AssociationId==`null`]` does work (an absent key evaluates to `null`), but the
semantics of absent-vs-null are subtle enough that hiding the most cost-relevant predicate in a
`--query` string is a bad trade. Emit the full shape, decide in `jq`, and the decision is visible in
the report.

**On the billing note:** since the 2024 change, *all* public IPv4 addresses are charged hourly,
associated or not — so an EIP attached to a live NAT gateway also costs money. But an *associated*
EIP is a symptom of its parent resource still existing, and that parent is already reported by its
own class. Only unassociated EIPs are orphans in their own right. The February 2024 effective date
and the per-hour rate are training knowledge, not sourced this session. `[ASSUMED]`

**False-positive risk: low.** Watch for an EIP associated to a NAT gateway that is itself mid-delete.

### ENIs — excluding AWS-managed interfaces

```bash
aws ec2 describe-network-interfaces --region "$region" --output json \
  --filters 'Name=status,Values=available' \
  --query 'NetworkInterfaces[].{id:NetworkInterfaceId,type:InterfaceType,managed:RequesterManaged,requester:RequesterId,desc:Description,vpc:VpcId,subnet:SubnetId,owner:Attachment.InstanceOwnerId,tags:TagSet}'
```

`status` valid values are `available | associated | attaching | in-use | detaching`.
`[VERIFIED: docs.aws.amazon.com/AWSEC2/latest/APIReference/API_NetworkInterface.html — `status`]`
`available` = detached. An attached ENI is reported via its parent.

**The three discriminators, verbatim from the API reference** `[VERIFIED: same page]`:

- **`requesterManaged`** — *"Indicates whether the network interface is being managed by AWS."*
  Boolean. If `true`, AWS owns it and deleting it is not your call. **Exclude.** The field may be
  absent, so default it: `(.managed // false)`.
- **`requesterId`** — *"The alias or AWS account ID of the principal or service that created the
  network interface."* A service alias here (`amazon-elb`, `amazon-rds`, …) identifies the creating
  service and makes a good `reason` string. Alias values are `[ASSUMED]`.
- **`interfaceType`** — valid values are exactly:
  `api_gateway_managed | aws_codestar_connections_managed | branch | ec2_instance_connect_endpoint |
  efa | efa-only | efs | evs | gateway_load_balancer | gateway_load_balancer_endpoint |
  global_accelerator_managed | interface | iot_rules_managed | lambda | load_balancer | nat_gateway |
  network_load_balancer | quicksight | transit_gateway | trunk | vpc_endpoint`

  Only `interface` is a plain user/EC2 ENI. Every other value denotes a service-managed interface —
  `vpc_endpoint`, `nat_gateway`, `lambda`, `load_balancer`, `network_load_balancer` being the ones
  this project will actually produce.

- **`Attachment.InstanceOwnerId`** — on a *detached* ENI there is no `Attachment` at all, so this
  discriminator is only useful for the `in-use` case (where `amazon-aws` / `amazon-elb` in that field
  marks a service-owned attachment). Since this class filters to `available`, **do not rely on it
  here**; `requesterManaged` + `interfaceType` are the operative two. `[ASSUMED]` for the
  `amazon-*` owner-ID values.

```bash
jq '[ .[]
      | select((.managed // false) == false)
      | select(.type == "interface")
      | . + {reason: "detached ENI (\(.desc // "no description"))"} ]'
```

**Why the double filter matters:** a `vpc_endpoint` ENI left behind by a half-deleted VPC endpoint
shows `status: available` and is genuinely not yours to delete directly — you delete the endpoint.
Reporting it as an orphan sends the operator down a dead end (`You are not allowed to manage
'ela-attach' attachments`). Report the *parent* instead, or at minimum set a `reason` that names the
owning service.

**False-positive risk: MEDIUM-HIGH without both filters.**

### CloudWatch log groups — the hardest exclusion problem

```bash
aws logs describe-log-groups --region "$region" --output json \
  --query 'logGroups[].{name:logGroupName,arn:arn,retention:retentionInDays,bytes:storedBytes,created:creationTime}'
```

**Why prefix-based exclusion does not work here.** The obvious instinct — "skip anything starting
`/aws/`" — is wrong for this project specifically: `/aws/eks/<cluster>/cluster` and
`/aws/containerinsights/<cluster>/...` are **exactly the groups this project creates and must clean
up**. Meanwhile `/aws/lambda/<fn>` from an unrelated experiment genuinely is someone else's. The
`/aws/` namespace is not a reliable ownership boundary in either direction.

**Recommended approach — allowlist-from-baseline, matching D-04/D-09.** This is one of the two
classes (log groups and S3 buckets) where the baseline inventory is not a nicety but the primary
mechanism:

1. At baseline (before any provisioning), record every existing log group name into
   `scripts/teardown-allowlist.txt`.
2. On every sweep, report any log group **not** on the allowlist and **not** tagged
   `Layer=00-bootstrap`.
3. Use name prefixes only to populate `reason`, never to filter.

Supplementary signals worth putting in `reason`:

- `retentionInDays` **absent** ⇒ "never expire" — this is the Pitfall 4 / D-23 default and is the
  single most common silent-accrual line item. Flag it prominently even for allowlisted groups.
- `storedBytes == 0` ⇒ group exists but has never been written; cosmetic, still a teardown failure.

**Tags are a weak signal here:** `describe-log-groups` does not return tags, so establishing tag
ownership costs one `aws logs list-tags-for-resource --resource-arn <arn>` call *per group* — an N+1
that is fine for a handful of groups and bad for hundreds. Use it only to resolve ambiguity, not as
the primary filter. (`list-tags-log-group` is the older, deprecated form; prefer
`list-tags-for-resource`. `[ASSUMED]`)

```bash
jq --slurpfile allow <(jq -R -s 'split("\n")|map(select(length>0))' scripts/teardown-allowlist.txt) '
  [ .[]
    | select(.name as $n | ($allow[0] | index($n)) | not)
    | . + {reason: (if .retention == null
                    then "log group with NEVER-EXPIRE retention"
                    else "log group (retention \(.retention)d)" end)} ]'
```

**False-positive risk: HIGH without a baseline allowlist.** This class is the one most likely to make
the sweep noisy and therefore ignored.

### EKS clusters (tier 3)

```bash
aws eks list-clusters --region "$region" --output json --query 'clusters'
```

Returns bare names. One control plane is ~$0.10/hr — roughly $73/mo — which makes this the single
most expensive thing a stray-region session can leave behind, and the reason tier 3 exists at all.
Rate is training knowledge. `[ASSUMED]`

If non-empty, enrich for the report:
```bash
aws eks describe-cluster --region "$region" --name "$c" --output json \
  --query 'cluster.{id:name,arn:arn,status:status,version:version,created:createdAt}'
```

**Exclusions:** allowlist. L0 creates no clusters, so a clean account returns `[]` in every region.
**False-positive risk: negligible.**

### RDS (tier 3)

```bash
aws rds describe-db-instances --region "$region" --output json \
  --query 'DBInstances[].{id:DBInstanceIdentifier,arn:DBInstanceArn,class:DBInstanceClass,engine:Engine,status:DBInstanceStatus}'
```

**Gaps worth one extra call each** (this project may never use them, but tier 3 is about the
mis-targeted console session, which by definition did something unplanned):

```bash
aws rds describe-db-clusters  --region "$region" --query 'DBClusters[].{id:DBClusterIdentifier,arn:DBClusterArn,status:Status}'
aws rds describe-db-snapshots --region "$region" --snapshot-type manual \
  --query 'DBSnapshots[].{id:DBSnapshotIdentifier,arn:DBSnapshotArn}'
```

`--snapshot-type manual` matters for the same reason `--owner-ids self` matters for EBS: automated
snapshots are managed by AWS and vanish with the instance. `[ASSUMED]`

**Exclusions:** allowlist. **False-positive risk: negligible.**

---

## Tag Layer & Region Enumeration

### `resourcegroupstaggingapi get-resources` — syntax

```bash
aws resourcegroupstaggingapi get-resources \
  --region "$region" \
  --tag-filters 'Key=Project' \
  --resources-per-page 100 \
  --output json \
  --query '{token: PaginationToken, items: ResourceTagMappingList[].{arn: ResourceARN, tags: Tags}}'
```

Filter semantics, verbatim: *"If you don't specify a value for a key, the response returns all
resources that are tagged with that key, with any or no value."*
`[VERIFIED: docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/API_GetResources.html — TagFilters]`
So bare `Key=Project` is correct for "everything this project tagged", whatever the value.

Limits: `ResourcesPerPage` min 1, max 100; up to 50 keys per request, 20 values per key.
`[VERIFIED: same page]`

### Pagination

Manual token loop, using the service-level `--pagination-token`:

```bash
tag_layer_scan() {
  local region="$1" token="" page
  : > "$TMPDIR/tagged-$region.ndjson"
  while :; do
    if [[ -z "$token" ]]; then
      page=$(aws_json "$region" resourcegroupstaggingapi get-resources \
        --region "$region" --tag-filters 'Key=Project' --resources-per-page 100 \
        --no-paginate --output json) || return 1
    else
      page=$(aws_json "$region" resourcegroupstaggingapi get-resources \
        --region "$region" --tag-filters 'Key=Project' --resources-per-page 100 \
        --pagination-token "$token" --no-paginate --output json) || return 1
    fi
    jq -c '.ResourceTagMappingList[] | {arn: .ResourceARN, tags: .Tags}' <<<"$page" \
      >> "$TMPDIR/tagged-$region.ndjson"
    token=$(jq -r '.PaginationToken // ""' <<<"$page")
    # A null OR EMPTY-STRING token means done. Empty string is the common case.
    [[ -n "$token" ]] || break
  done
}
```

Three things the API reference pins down that a hand-rolled loop usually gets wrong
`[VERIFIED: same page]`:

1. **Terminator is `null` *or* empty string.** *"A null value for `PaginationToken` indicates that
   there are no more results."* The documented sample response shows `"PaginationToken": ""` on the
   final page. Test for both, as above — testing only for `null` loops forever.
2. **Tokens expire after 15 minutes.** `PaginationTokenExpiredException`, HTTP 400. On an empty
   account this never fires, but the error must be classified as a script error (exit 2), not
   silently swallowed as "no more results".
3. **The operation is rate-limited.** Combined with tier 3 iterating ~17 enabled regions, add a
   retry-with-backoff on `ThrottledException` or set `AWS_MAX_ATTEMPTS`/`AWS_RETRY_MODE=adaptive`
   in the environment.

`--no-paginate` is used above to keep the CLI from merging pages behind your back while you are also
managing tokens yourself. Whether `get-resources` is registered in the CLI's paginator config (and
thus supports `--starting-token`/`--max-items`) was not verified this session; the manual
`--pagination-token` loop avoids depending on the answer. `[UNVERIFIED]`

### What the tag layer does NOT cover — the justification for D-07's blind-spot layer

The decisive, documented gap:

> `GetResources` does not return untagged resources. To find untagged resources in your account, use
> AWS Resource Explorer with a query that uses `tag:none`.

`[VERIFIED: docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/API_GetResources.html]`

That one sentence is the whole case for D-07. Concretely, for this project:

| Gap | Why it bites here |
|---|---|
| **Untagged resources are invisible, full stop** | Every orphan class in D-07's blind-spot list is characteristically *untagged* — that is what makes it an orphan. D-13's test volume is deliberately untagged, so a tag-only sweep would score it clean and the hard gate would pass on a broken verifier. |
| **Controller-created resources carry no `Project` tag** | The AWS Load Balancer Controller and Karpenter tag with their own keys; `Project` propagation must be configured explicitly and usually isn't. ALBs, `k8s-*` SGs and controller ENIs therefore fall straight through the tag layer. |
| **Regional operation** | *"Returns all the tagged or previously tagged resources that are located in the specified AWS Region"* `[VERIFIED: same page]` — one call per region, always. There is no account-wide mode. |
| **Previously-tagged resources return with `"Tags": []`** | `[VERIFIED: same page]` — a resource whose tags were stripped still appears, with an empty tag set. Handle it or your `jq` indexing throws. |
| **Not every service is covered** | The API reference points at a separate "Services that support the Resource Groups Tagging API" page; services absent from it are only reachable via their native tagging operations. The specific list of excluded services was not retrieved this session. `[UNVERIFIED]` — which is itself the argument for not depending on coverage you cannot enumerate. |

**Design conclusion:** treat the tag layer as *enrichment* (it tells you which resources are
project-owned and gives you ARNs cheaply), and the blind-spot layer as the *authority* on whether the
account is clean. If the two disagree, the blind-spot layer wins.

### Region enumeration

```bash
# ENABLED regions only. This is the default behaviour — NO flag needed.
mapfile -t regions < <(aws ec2 describe-regions --output text --query 'Regions[].RegionName' | tr '\t' '\n')
```

> *"Describes the Regions that are enabled for your account, or all Regions."* … `--all-regions`:
> *"Indicates whether to display all Regions, including Regions that are disabled for your account."*
>
> Example 1: To describe all of your **enabled** Regions — `aws ec2 describe-regions`

`[VERIFIED: docs.aws.amazon.com/cli/latest/reference/ec2/describe-regions.html — Options, Examples 1 & 3]`

**Use the bare form. Do NOT use `--all-regions`** — it includes `not-opted-in` regions, and calling a
service API in a disabled region returns `OptInRequired`/`AuthFailure`, which your credential-error
detector will (correctly, from its point of view) escalate to exit 2. That turns a clean account into
a "verifier is broken" report, which D-10 exists to prevent.

The equivalent explicit form, if you prefer the intent to be legible:

```bash
aws ec2 describe-regions \
  --filters 'Name=opt-in-status,Values=opt-in-not-required,opted-in' \
  --query 'Regions[].RegionName' --output text
```

`opt-in-status` valid values are `opt-in-not-required | opted-in | not-opted-in`.
`[VERIFIED: same page — `--filters`]`

`aws account list-regions --region-opt-status-contains ENABLED ENABLED_BY_DEFAULT` is the newer
Account-API equivalent; it requires `account:ListRegions`, which `ReadOnlyAccess` may or may not
grant, and it adds a dependency for no benefit here. **Prefer `ec2 describe-regions`** — the plan
role can already call it, and it is the same answer. `[ASSUMED]` for the exact `list-regions`
parameter spelling.

**Tier-3 cost/time.** ~17 enabled-by-default commercial regions × 5 calls (EC2 instances, EKS, ELBv2,
RDS, EIPs) = ~85 API calls. All are `Describe*`/`List*`, all free of charge. Serially at ~0.3–0.8 s
each that is roughly 30–60 s; run them with `xargs -P 8` or backgrounded subshells writing per-region
NDJSON and it drops to a few seconds. **Parallelise tier 3** — `make down` runs this on every
teardown and a 60-second tax on the daily loop is exactly the kind of friction that gets a check
commented out.

Do **not** extend tier 3 beyond D-08's five types. The value is bounded (catch the expensive
mistake) and every added type multiplies by 17.

### Global vs regional

| Class | Scope | Endpoint handling |
|---|---|---|
| EC2 instances, EBS volumes, snapshots, EIPs, ENIs, security groups | **Regional** | `--region "$r"` per region |
| ALB/NLB/Classic ELB, target groups | **Regional** | `--region "$r"` |
| CloudWatch log groups | **Regional** | `--region "$r"` |
| EKS clusters | **Regional** | `--region "$r"` |
| RDS instances/clusters | **Regional** | `--region "$r"` |
| `resourcegroupstaggingapi get-resources` | **Regional** | `--region "$r"`, once per region |
| **IAM** (users, roles, policies, OIDC providers) | **Global** | single call; `--region us-east-1` |
| **CloudFront** | **Global** | single call; **must** use `--region us-east-1` |
| **S3** — `list-buckets` | **Global** | single call, no region |
| **S3** — per-bucket ops | Bucket has a home region | resolve via `get-bucket-location` |
| **Route 53** | **Global** | `--region us-east-1` — *gap*, see below |

**Global-pass mechanics:**

```bash
global_scan() {
  local R=us-east-1   # canonical endpoint region for global services in the aws partition

  # IAM — roles and users not on the allowlist. L0's own roles ARE allowlisted.
  aws_json GLOBAL iam list-roles --region "$R" --output json \
    --query 'Roles[].{id:RoleName,arn:Arn,created:CreateDate}'

  aws_json GLOBAL iam list-users --region "$R" --output json \
    --query 'Users[].{id:UserName,arn:Arn,created:CreateDate}'

  # CloudFront — global; the API is only served from us-east-1.
  aws_json GLOBAL cloudfront list-distributions --region "$R" --output json \
    --query 'DistributionList.Items[].{id:Id,arn:ARN,domain:DomainName,enabled:Enabled,status:Status}'

  # S3 — list-buckets is global; resolve each bucket's region for the report.
  aws_json GLOBAL s3api list-buckets --output json \
    --query 'Buckets[].{id:Name,created:CreationDate}'
}
```

Three specifics that matter:

- **CloudFront returns `null`, not `[]`, when empty.** `DistributionList.Items` is absent on an
  account with no distributions, so `--query 'DistributionList.Items[]...'` yields `null` and
  `jq '.[]'` throws `Cannot iterate over null`. Normalise: `jq '. // []'`. This is a real and common
  crash. `[ASSUMED]` on the exact absent-vs-empty behaviour — normalise defensively either way.
- **IAM will never be empty.** Every account has AWS service-linked roles (`AWSServiceRoleFor*`) that
  cannot be deleted and appear in `list-roles` from day one. This is the IAM analogue of the default
  security group: **without a baseline allowlist the global pass reports a dozen phantom orphans on a
  pristine account.** D-04's baseline inventory is what makes IAM checkable at all. Additionally
  skip anything under path `/aws-service-role/` as a cheap structural filter. `[ASSUMED]`
- **S3 buckets need a region for the report.** `list-buckets` is region-free but each bucket lives
  somewhere: `aws s3api get-bucket-location --bucket "$b" --query LocationConstraint --output text`,
  which returns the literal `None`/`null` for `us-east-1`. Map that to `us-east-1` before it lands in
  the JSON report. The state bucket `tfstate-<account-id>-<region>` (D-17) is permanently
  allowlisted. `[ASSUMED]` on the `None` sentinel.

**Named global gaps** (out of D-07's explicit scope, worth one line in Open Questions rather than
silent omission): **Route 53 hosted zones** (~$0.50/mo each, survive everything, global), **ACM
certificates** (free but regional and easy to strand), and **ECR repositories** (Phase 3's concern,
but storage bills). None are in D-07's list; do not add them to Phase 1 scope, but do record that
the sweep does not cover them so a later phase can.

---

## Sweep Script Architecture (exit contract, error handling, JSON report)

### The core tension

`set -euo pipefail` (D-06) says *abort on the first non-zero*. D-07 says *always run both layers*.
D-11 says *report all orphan classes*. D-10 says *distinguish dirty from broken*. Resolve it by
never letting a checked command's exit status reach the `ERR` trap:

- Every AWS call goes through **one wrapper** that captures stdout, stderr, and status explicitly.
  Nothing else in the script calls `aws` directly.
- The wrapper **classifies** the failure: credential/permission ⇒ hard error (exit 2); everything
  else ⇒ hard error too, because a sweep that half-ran and reported "clean" is the failure mode D-10
  was written to prevent.
- Findings accumulate in a file, not in `$?`.
- `set -e` stays on for genuine programming errors (typo'd variable under `set -u`, a `jq` syntax
  error), which is the only thing it is good at.

**Do not use the `|| true` idiom broadly.** It is the obvious answer and it is wrong here: it
converts a credential failure into "this class found zero orphans", which reports a broken verifier
as a clean account. Use it only where the non-zero status is genuinely expected and meaningless
(`grep` with no match, `mapfile` on empty input).

**The `set -e` subtlety to know:** when a function is invoked as the condition of `if`, `&&`, `||`,
or `!`, `set -e` is **disabled throughout its entire body**, recursively. So `if ! check_volumes;
then …; fi` silently disarms error handling inside `check_volumes`. Given the wrapper does explicit
status checking anyway this is survivable — but it means you cannot lean on `set -e` inside checks,
and the wrapper is not optional.

### Skeleton

```bash
#!/usr/bin/env bash
# scripts/verify-teardown.sh
#
# Exit contract (D-10):
#   0 = clean            — no orphans outside the allowlist
#   1 = orphans found    — the account is dirty
#   2 = script/cred error — the verifier could not complete; result is UNKNOWN
#
# 2 is NOT "worse than 1". It means "no answer". `make down` must treat it as a
# hard stop, never as clean.

set -euo pipefail

readonly EXIT_CLEAN=0
readonly EXIT_ORPHANS=1
readonly EXIT_ERROR=2

readonly PROJECT_TAG_KEY="Project"
readonly IMMORTAL_TAG="Layer=00-bootstrap"
readonly ALLOWLIST="${ALLOWLIST:-scripts/teardown-allowlist.txt}"
readonly REPORT="${REPORT:-.teardown-report.json}"
readonly HOME_REGION="${AWS_REGION:-us-east-1}"
readonly GLOBAL_REGION="us-east-1"

# Expensive-only types for the tier-3 all-regions pass (D-08).
readonly TIER3_CLASSES=(ec2_instances eks_clusters load_balancers rds_instances elastic_ips)

TMPDIR="$(mktemp -d)"
FINDINGS="$TMPDIR/findings.ndjson"   # one JSON object per orphan
ERRORS="$TMPDIR/errors.ndjson"       # one JSON object per failed check
: > "$FINDINGS"; : > "$ERRORS"

HARD_ERROR=0   # set to 1 by fail_hard(); forces exit 2 regardless of findings

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Unexpected non-zero that escaped the wrapper = programming error, not a dirty account.
on_err() {
  local rc=$? line=$1
  echo "verify-teardown: INTERNAL ERROR at line ${line} (rc=${rc})" >&2
  cleanup
  exit "$EXIT_ERROR"
}
trap 'on_err $LINENO' ERR

fail_hard() {  # fail_hard <scope> <message>
  HARD_ERROR=1
  jq -nc --arg scope "$1" --arg msg "$2" '{scope:$scope, message:$msg}' >> "$ERRORS"
  echo "verify-teardown: ERROR [$1] $2" >&2
}

record() {  # record <class> <region> <id> <arn> <reason>
  jq -nc --arg class "$1" --arg region "$2" --arg id "$3" \
         --arg arn "$4" --arg reason "$5" \
    '{class:$class, region:$region, id:$id, arn:$arn, reason:$reason}' >> "$FINDINGS"
}

# ---------------------------------------------------------------------------
# The ONE place `aws` is invoked. Captures stdout/stderr/status; classifies.
# Returns 0 with JSON on stdout, or non-zero having already recorded the error.
# ---------------------------------------------------------------------------
aws_json() {
  local scope="$1"; shift
  local out err rc=0
  err="$TMPDIR/stderr.$$"

  set +e
  out=$(aws "$@" 2>"$err")
  rc=$?
  set -e

  if (( rc == 0 )); then
    printf '%s' "${out:-null}"
    return 0
  fi

  local msg; msg=$(tr -d '\r' < "$err" | tail -3 | tr '\n' ' ')

  case "$msg" in
    # Credential / authz problems => the verifier cannot answer the question.
    *AccessDenied*|*UnauthorizedOperation*|*AuthFailure*|*ExpiredToken*|\
    *InvalidClientTokenId*|*SignatureDoesNotMatch*|*"Unable to locate credentials"*|\
    *"The security token included in the request is expired"*)
      fail_hard "$scope" "credential/permission failure: ${msg}"
      return 1 ;;

    # Region enabled but service not offered there. Tolerable during tier 3 ONLY.
    *OptInRequired*|*"Could not connect to the endpoint URL"*|*EndpointConnectionError*|\
    *UnsupportedOperation*|*InvalidAction*)
      if [[ "$scope" == tier3:* ]]; then
        echo "verify-teardown: note [$scope] service unavailable in region; skipping" >&2
        printf 'null'
        return 0
      fi
      fail_hard "$scope" "endpoint/service unavailable: ${msg}"
      return 1 ;;

    *Throttl*|*RequestLimitExceeded*)
      fail_hard "$scope" "throttled (set AWS_RETRY_MODE=adaptive): ${msg}"
      return 1 ;;

    *) fail_hard "$scope" "unclassified AWS error (rc=${rc}): ${msg}"
       return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Preflight: fail fast and unambiguously on bad credentials, BEFORE any check.
# ---------------------------------------------------------------------------
preflight() {
  command -v aws >/dev/null || { echo "aws CLI v2 not found" >&2; exit "$EXIT_ERROR"; }
  command -v jq  >/dev/null || { echo "jq not found" >&2;          exit "$EXIT_ERROR"; }

  local ident
  if ! ident=$(aws sts get-caller-identity --output json 2>"$TMPDIR/pre.err"); then
    echo "verify-teardown: cannot authenticate to AWS:" >&2
    sed 's/^/  /' "$TMPDIR/pre.err" >&2
    cleanup
    exit "$EXIT_ERROR"     # exit 2, never 1 — we learned nothing about the account
  fi
  ACCOUNT_ID=$(jq -r '.Account' <<<"$ident")
  CALLER_ARN=$(jq -r '.Arn'     <<<"$ident")
  echo "verify-teardown: account ${ACCOUNT_ID} as ${CALLER_ARN}"

  [[ -f "$ALLOWLIST" ]] || { echo "allowlist not found: $ALLOWLIST" >&2; cleanup; exit "$EXIT_ERROR"; }
}

# Allowlist: '#' comments and blanks stripped; one id/ARN/name per line (D-09).
load_allowlist() {
  mapfile -t ALLOW < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$ALLOWLIST" | grep -v '^$' || true)
}
is_allowlisted() {
  local needle="$1" a
  for a in "${ALLOW[@]}"; do [[ "$needle" == "$a" ]] && return 0; done
  return 1
}
# An immortal resource is allowlisted OR tagged Layer=00-bootstrap (D-09).
is_immortal() {  # is_immortal <id> <tags-json>
  is_allowlisted "$1" && return 0
  jq -e --arg k "Layer" --arg v "00-bootstrap" \
     'any(.[]?; .Key == $k and .Value == $v)' <<<"${2:-[]}" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Driver. Every check runs; none can abort the run.
# ---------------------------------------------------------------------------
main() {
  preflight
  load_allowlist

  # Tier 1: full enumeration in the home region.
  tag_layer_scan            "$HOME_REGION"
  check_load_balancers      "$HOME_REGION"
  check_target_groups       "$HOME_REGION"
  check_security_groups     "$HOME_REGION"
  check_ec2_instances       "$HOME_REGION"
  check_ebs_volumes         "$HOME_REGION"
  check_snapshots           "$HOME_REGION"
  check_elastic_ips         "$HOME_REGION"
  check_enis                "$HOME_REGION"
  check_log_groups          "$HOME_REGION"

  # Tier 2: global services.
  check_iam
  check_cloudfront
  check_s3_buckets

  # Tier 3: expensive types only, every enabled region except the home region.
  local r
  for r in $(enabled_regions); do
    [[ "$r" == "$HOME_REGION" ]] && continue
    check_ec2_instances  "$r" "tier3"
    check_eks_clusters   "$r" "tier3"
    check_load_balancers "$r" "tier3"
    check_rds_instances  "$r" "tier3"
    check_elastic_ips    "$r" "tier3"
  done

  write_report
  print_table

  if (( HARD_ERROR )); then
    echo "verify-teardown: RESULT UNKNOWN — $(wc -l < "$ERRORS") check(s) failed." >&2
    echo "verify-teardown: do NOT treat this as a clean account." >&2
    exit "$EXIT_ERROR"
  fi

  if [[ -s "$FINDINGS" ]]; then
    echo "verify-teardown: $(wc -l < "$FINDINGS") orphan(s) found. Account is DIRTY." >&2
    exit "$EXIT_ORPHANS"
  fi

  echo "verify-teardown: account is CLEAN."
  exit "$EXIT_CLEAN"
}

main "$@"
```

### Why this shape, specifically

| Requirement | Mechanism |
|---|---|
| Continue past a failed class | `aws_json` returns non-zero; the caller `return`s early from *that check only*; `main` calls the next one unconditionally. |
| Never mistake broken for clean | `HARD_ERROR` is checked **before** `-s "$FINDINGS"`. Exit 2 always wins over both 0 and 1. |
| Detect credential failure specifically | `sts get-caller-identity` preflight (fails fast, before any partial result exists) **plus** per-call stderr classification, because a role can authenticate fine and still be denied one specific API. |
| `set -e` still catches real bugs | `aws` is the only expected-to-fail command, and it is wrapped. Everything else aborting is genuinely a bug. |
| Tolerate service-not-in-region during tier 3 | `scope` prefix `tier3:` narrows the tolerance so it cannot mask a real `AccessDenied` in the home region. |
| Cleanup on any path | `trap cleanup EXIT` fires on normal exit, `ERR` exit, and signals. |

> **The single most important line in the script** is `if (( HARD_ERROR ))` executing *before* the
> findings check. Get the order backwards and a credentials expiry during the sweep produces
> "account is CLEAN" — exactly the failure D-10 names as the worst available.

**`make down` contract, to document in the Makefile:**

```make
verify-teardown:
	@scripts/verify-teardown.sh; rc=$$?; \
	 case $$rc in \
	   0) echo "clean" ;; \
	   1) echo "ORPHANS FOUND — see .teardown-report.json" >&2; exit 1 ;; \
	   2) echo "VERIFIER ERROR — teardown state UNKNOWN. Do not assume clean." >&2; exit 2 ;; \
	   *) echo "unexpected exit $$rc" >&2; exit 2 ;; \
	 esac
```

**D-13's test must assert all three arms**, not just 1 and 0. Add a third case: run with
`AWS_ACCESS_KEY_ID=bogus AWS_SECRET_ACCESS_KEY=bogus AWS_SESSION_TOKEN=` and assert exit 2. That is
the arm most likely to silently rot, because nothing else ever exercises it.

### `.teardown-report.json` schema (D-11)

Sweep-scoped `exit_code` is embedded so the artifact is self-describing — Phase 2's
"two consecutive zero-orphan round-trips" gate can be evaluated from two files with no shell history.

```json
{
  "schema_version": 1,
  "generated_at": "2026-09-25T14:03:11Z",
  "account_id": "123456789012",
  "caller_arn": "arn:aws:sts::123456789012:assumed-role/gha-terraform-plan/gha-plan-1234567890",
  "home_region": "us-east-1",
  "regions_scanned": {
    "full":   ["us-east-1"],
    "global": ["iam", "cloudfront", "s3"],
    "tier3":  ["us-east-2", "us-west-1", "us-west-2", "eu-west-1"]
  },
  "allowlist_file": "scripts/teardown-allowlist.txt",
  "allowlist_entries": 7,
  "exit_code": 1,
  "verdict": "orphans",
  "summary": {
    "total_orphans": 3,
    "by_class": {
      "ebs_volumes": 2,
      "security_groups": 1,
      "load_balancers": 0,
      "target_groups": 0,
      "ec2_instances": 0,
      "snapshots": 0,
      "elastic_ips": 0,
      "enis": 0,
      "log_groups": 0,
      "eks_clusters": 0,
      "rds_instances": 0,
      "iam": 0,
      "cloudfront": 0,
      "s3_buckets": 0,
      "tagged": 0
    },
    "by_region": { "us-east-1": 3 }
  },
  "orphans": {
    "ebs_volumes": [
      {
        "id": "vol-0a1b2c3d4e5f67890",
        "arn": "arn:aws:ec2:us-east-1:123456789012:volume/vol-0a1b2c3d4e5f67890",
        "region": "us-east-1",
        "reason": "available (detached) gp3 volume, 1 GiB, untagged",
        "tags": {},
        "discovered_by": "blind-spot"
      }
    ],
    "security_groups": [
      {
        "id": "sg-0123456789abcdef0",
        "arn": "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0123456789abcdef0",
        "region": "us-east-1",
        "reason": "non-default SG 'k8s-default-demo-1a2b3c4d' — AWS Load Balancer Controller leftover",
        "tags": { "elbv2.k8s.aws/cluster": "demo" },
        "discovered_by": "blind-spot"
      }
    ]
  },
  "errors": []
}
```

Notes on the shape:

- `orphans` is keyed by class (D-11's "grouped by orphan class") with an array per class. Emit
  **every** class key even when empty — a consumer diffing two reports should not have to
  distinguish "zero" from "not checked". `errors[]` is what distinguishes "not checked".
- `reason` is the human string that also drives the stdout table; keep it one line and lead with
  *why it is an orphan*, not what it is.
- `discovered_by` is `"tag"` | `"blind-spot"`. Over time, blind-spot-only findings tell you exactly
  where tag propagation is missing — a free feedback loop into the tagging strategy.
- `verdict` is `"clean" | "orphans" | "error"`, mirroring `exit_code`. Redundant on purpose: JSON
  consumers should not have to memorise the integer contract.
- `errors[]` non-empty ⇒ `exit_code: 2` ⇒ the counts in `summary` are a **lower bound**, not a
  result. Say so in the field docs.
- **Gitignore `.teardown-report.json`** (D-11) — it contains the account ID and ARNs.
- The schema and filename are explicitly the agent's discretion per CONTEXT.md, so this is a
  proposal, not a constraint.

Human table, same data, stdout:

```
verify-teardown: account 123456789012 as arn:aws:sts::…/gha-terraform-plan/…
                 home us-east-1 | global IAM,CloudFront,S3 | tier3 16 regions

ORPHANS (3)

  ebs_volumes (2)                                    usual cause: node group deleted, volumes retained
    us-east-1  vol-0a1b2c3d4e5f67890   available gp3 1GiB, untagged
    us-east-1  vol-0f9e8d7c6b5a43210   available gp3 20GiB, untagged

  security_groups (1)                                usual cause: ALB controller SG not cleaned up
    us-east-1  sg-0123456789abcdef0    k8s-default-demo-1a2b3c4d

RESULT: DIRTY (exit 1) — report written to .teardown-report.json
```

---

## Gotchas & Landmines

1. **Immutable `sub` claims (2026-07-15).** The highest-severity item in this slice. If the GitHub
   repo was created on or after that date, D-26's literal `sub` strings never match and both roles
   fail with `Not authorized to perform sts:AssumeRoleWithWebIdentity` — an error that names nothing
   useful. **Check `gh api repos/OWNER/REPO --jq .created_at` before writing the trust policy.**
   `[VERIFIED: docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims]`

2. **`environment:` silently rewrites the `sub` claim.** Adding an environment to a job — the natural
   way to add a manual approval gate — changes `sub` to `:environment:<name>` regardless of trigger,
   breaking both `ref:` and `pull_request` conditions.
   `[VERIFIED: docs.github.com/…/oidc — "Filtering for a specific environment"]`

3. **`thumbprint_list` is dead weight.** Optional in the provider, ignored by AWS for GitHub.
   Supplying one invites the rotation automation D-29 forbids. Omit it.
   `[VERIFIED: hashicorp/aws provider docs; configure-aws-credentials README]`

4. **Do not name a role `GitHubActions`.** Documented as "reported to not work."
   `[VERIFIED: configure-aws-credentials README, issue #953]`

5. **The plan role needs write on `*.tflock`.** `terraform plan` takes a state lock by default, and
   with `use_lockfile` that lock is an S3 object. `ReadOnlyAccess` alone makes every plan job fail at
   lock acquisition.

6. **Do not `Deny` `budgets:*` or `ce:*` in the D-28 apply guardrails.** This phase's own Terraform
   creates the budget and the anomaly monitor. "Billing configuration" means payment/invoicing/tax
   settings, not cost controls.

7. **`ec2 describe-security-groups` without excluding `GroupName == "default"`** reports one
   permanent, undeletable false positive per VPC per region — including the pre-created default VPC
   in every region of a brand-new account. Worse than no sweep.

8. **`ec2 describe-snapshots` without `--owner-ids self`** enumerates every public snapshot on AWS.
   Not a false positive — a hang.

9. **`ec2 describe-instances` without a state filter** reports `terminated` instances for ~an hour
   after a *successful* teardown, which directly breaks Phase 2's consecutive-clean-round-trips gate.
   `[ASSUMED]` on the retention window.

10. **`describe-network-interfaces` needs both `requesterManaged` and `interfaceType` filters.** A
    `vpc_endpoint` or `nat_gateway` ENI in `available` state is not yours to delete and sends the
    operator to a dead end.
    `[VERIFIED: docs.aws.amazon.com/AWSEC2/latest/APIReference/API_NetworkInterface.html]`

11. **`GetResources` does not return untagged resources.** The one-sentence justification for the
    entire blind-spot layer, and the reason D-13's untagged test volume would score clean under a
    tag-only sweep. `[VERIFIED: AWS API reference]`

12. **`GetResources` pagination terminates on `null` *or* empty string.** The documented sample
    response returns `""` on the final page. Testing only for `null` loops forever.
    `[VERIFIED: AWS API reference]`

13. **`--all-regions` includes disabled regions**, whose API calls return `OptInRequired`/
    `AuthFailure` — which your credential detector escalates to exit 2. Use the bare
    `aws ec2 describe-regions`. `[VERIFIED: AWS CLI reference]`

14. **`set -e` is disabled inside a function called as an `if` condition**, recursively through its
    whole body. Never rely on `set -e` inside a check function; the `aws_json` wrapper's explicit
    status handling is what actually works.

15. **`|| true` on an AWS call converts a credential failure into "found nothing".** This is the
    exact inversion D-10 exists to prevent. Use the classifying wrapper instead.

16. **Check `HARD_ERROR` before checking findings.** Reversing the order makes a mid-sweep credential
    expiry print "account is CLEAN".

17. **`cloudfront list-distributions` returns `null` (not `[]`) on an empty account**, so
    `jq '.[]'` throws `Cannot iterate over null`. Normalise with `// []`. `[ASSUMED]`

18. **`iam list-roles` is never empty** — service-linked roles under `/aws-service-role/` exist from
    day one and cannot be deleted. Without the D-04 baseline allowlist the global pass reports
    phantom orphans on a pristine account. `[ASSUMED]`

19. **`get-bucket-location` returns `None`/`null` for `us-east-1`**, not the region string. Map it
    before it reaches the report. `[ASSUMED]`

20. **CloudWatch log groups cannot be filtered by the `/aws/` prefix** — `/aws/eks/...` is *yours*
    while `/aws/lambda/...` may not be. Baseline allowlist is the only reliable mechanism.

21. **Run tier 3 in parallel.** ~85 serial calls is 30–60 s of tax on every `make down`, which is how
    checks get commented out.

22. **`gh secret list` has three separate stores** (`--app actions|dependabot|codespaces`) plus
    per-environment secrets. Checking only the default one proves less than it appears to.

23. **Never use `pull_request_target`** in this repo — it runs with the base repo's context and full
    secret access. AWS calls it out by name. `[VERIFIED: configure-aws-credentials README]`

---

## Open Questions

1. **Was the GitHub repository created on or after 2026-07-15?** Determines whether `sub` uses the
   legacy or immutable format. **Blocking for the OIDC tasks.** Resolve with
   `gh api repos/OWNER/REPO --jq '{created: .created_at, owner_id: .owner.id, repo_id: .id}'` and
   confirm empirically with `github/actions-oidc-debugger` before the first apply. Recommend a
   `checkpoint:human-verify` task sequenced ahead of the IAM role tasks.

2. **Can a `pull_request` from a fork obtain `id-token: write`?** Believed **no** — fork PRs get a
   read-only token and no secrets, so the plan role is structurally unreachable from a fork. If true
   that is a security *property* worth documenting; it also means fork PRs will fail the plan job and
   need a documented fallback. Not verified this session. `[ASSUMED]` — resolve before writing the
   plan workflow's fork-handling behaviour.

3. **Does `ReadOnlyAccess` grant `tag:GetResources`?** The D-12 scheduled sweep assumes the plan role
   needs "no new permissions". If the tag layer returns `AccessDenied`, an explicit
   `tag:GetResources` / `tag:GetTagKeys` allow is needed. `[ASSUMED]` — cheap to resolve on first
   run, but the sweep's exit-2 handling makes it loud rather than silent, which is correct.

4. **Is the state bucket SSE-S3 or SSE-KMS (D-15)?** SSE-KMS adds `kms:Decrypt` +
   `kms:GenerateDataKey` to the plan role's policy. Determined by the bootstrap task, not by this
   research.

5. **Which services does `resourcegroupstaggingapi` not cover?** The specific exclusion list was not
   retrieved this session. `[UNVERIFIED]` Low impact — the blind-spot layer is authoritative by
   design and the "does not return untagged resources" gap already justifies it — but worth a single
   fetch of <https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/supported-services.html>
   during planning if a specific service's coverage becomes load-bearing.

6. **Is `get-resources` registered in the AWS CLI's paginator config?** Determines whether
   `--starting-token`/`--max-items` are available as an alternative to the manual
   `--pagination-token` loop. `[UNVERIFIED]` The manual loop given above works either way.

7. **Out-of-scope global classes.** Route 53 hosted zones (~$0.50/mo, survive everything), ACM
   certificates, and ECR repositories are not in D-07's list. Recommend recording the omission
   explicitly in `verify-teardown.sh`'s header comment rather than leaving it implicit — and
   revisiting in Phase 3 (ECR) and Phase 11 (CloudFront/SPA, likely Route 53).

8. **Classic ELB coverage.** `elbv2 describe-load-balancers` does not see Classic Load Balancers.
   One extra call (`elb describe-load-balancers`) closes a ~$16/mo blind spot. Recommend adding it
   and noting it as a deliberate extension of D-07's list.

9. **Exact `hashicorp/aws` version that made `thumbprint_list` optional.** `[UNVERIFIED]` — moot at
   the pinned `= 6.66.0`, but worth one line in `VERSIONS.md` if the pin is ever lowered.
