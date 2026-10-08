# AWS Pricing and Cost Model

All regional prices below are for `us-east-1`. The source account is a dedicated AWS Organizations
member account. Published list prices are used for planning; consolidated-billing discounts, credits,
Billing Conductor settings, and payer-side adjustments can change the final invoice. The management
account controls organization-level Cost Explorer access; this member account can see only its own
cost and usage data.

## Verification method

The `[VERIFIED]` AWS rates below were pulled on **2026-09-25** from the credential-free AWS Price List
Bulk API. The dates in the source column are the offer `pubDate` or object `Last-Modified` values
observed during that check. Re-verify before changing budget limits.

```bash
# Regional per-service price list (JSON)
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<SERVICE_CODE>/current/us-east-1/index.json"

# Global (non-regional) services
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<SERVICE_CODE>/current/index.json"

# EC2 is about 303 MB; stream-grep the CSV instead of downloading the full JSON index.
curl -sS --compressed \
  "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/us-east-1/index.csv" \
  | grep -E 'NatGateway|VolumeUsage\.gp3|BoxUsage:t4g\.nano'
```

The AWS Pricing Query API was not used; the AWS CLI Pricing operation was unavailable during the
research pass. AWS marketing pricing pages are JavaScript-rendered and were not scraped. The Bulk
API is the machine-readable source used here.

## Prior-art verification

| Existing claim | Source in the research corpus | Result |
|---|---|---|
| EKS control plane `$0.10/cluster-hr` | `research/PITFALLS.md`, `research/STACK.md` | Confirmed. |
| EKS extended support `$0.60/cluster-hr` | `research/PITFALLS.md` | Corrected: `$0.50/hr` is an additive surcharge; `$0.10 + $0.50 = $0.60/hr` total. |
| Interface VPC endpoint `$0.01/endpoint-ENI-hr` | `research/PITFALLS.md`, `research/STACK.md` | Confirmed. |
| Public IPv4 `~$0.005/hr` | `research/PITFALLS.md` | Confirmed and upgraded to high confidence for both idle and in-use addresses. |
| EBS gp3 `~$0.08/GB-mo` | `research/PITFALLS.md` | Confirmed. |
| CloudWatch Logs `$0.50/GB` ingestion and `$0.03/GB-mo` storage | `research/PITFALLS.md` | Confirmed and upgraded to high confidence. |
| ECR `$0.10/GB-mo` | `research/PITFALLS.md` | Confirmed and upgraded to high confidence. |
| NAT Gateway `$0.045/hr + $0.045/GB` | `research/STACK.md` | Confirmed. |
| `t4g.nano` `~$0.0042/hr` | `research/STACK.md` | Confirmed. |
| Cross-AZ `$0.01/GB` each direction | `research/PITFALLS.md` | Confirmed; first 1 GB/month is free. |
| S3 + DynamoDB state lock costs `<$0.10` | `research/PITFALLS.md` | S3 is `<$0.02` in this model; the DynamoDB line is absent because native S3 `use_lockfile` is used. |

## Verified unit pricing

Every row carries its confidence and dated source. `[ASSUMED]` means the price-list scan did not establish a
price; it is not presented as a verified zero.

| Item | Unit | Price | Confidence / source and date |
|---|---|---:|---|
| S3 Standard storage, first 50 TB | GB-month | $0.023 | HIGH `[VERIFIED]`; `AmazonS3/us-east-1`, pubDate 2026-09-18; checked 2026-09-25. |
| S3 Standard storage, next 450 TB | GB-month | $0.022 | HIGH `[VERIFIED]`; `AmazonS3/us-east-1`, pubDate 2026-09-18; checked 2026-09-25. |
| S3 Standard storage, above 500 TB | GB-month | $0.021 | HIGH `[VERIFIED]`; `AmazonS3/us-east-1`, pubDate 2026-09-18; checked 2026-09-25. |
| S3 PUT/COPY/POST/LIST (Tier 1) | request | $0.000005 ($0.005/1,000) | HIGH `[VERIFIED]`; `AmazonS3/us-east-1`, pubDate 2026-09-18; checked 2026-09-25. |
| S3 GET and other requests (Tier 2) | request | $0.0000004 ($0.004/10,000) | HIGH `[VERIFIED]`; `AmazonS3/us-east-1`, pubDate 2026-09-18; checked 2026-09-25. |
| S3 versioning | - | No separate charge; every retained version is billed as a full object | HIGH `[CITED]`; [S3 versioning workflows](https://docs.aws.amazon.com/AmazonS3/latest/userguide/versioning-workflows.html), accessed 2026-09-25. |
| CloudWatch Logs ingestion, Standard | GB | $0.50 | HIGH `[VERIFIED]`; `AmazonCloudWatch/us-east-1`, pubDate 2026-09-22, `USE1-DataProcessing-Bytes`; checked 2026-09-25. |
| CloudWatch Logs ingestion, Infrequent Access | GB | $0.25 | HIGH `[VERIFIED]`; `AmazonCloudWatch/us-east-1`, pubDate 2026-09-22; checked 2026-09-25. |
| CloudWatch Logs storage | GB-month | $0.03 | HIGH `[VERIFIED]`; `AmazonCloudWatch/us-east-1`, pubDate 2026-09-22, `USE1-TimedStorage-ByteHrs`; checked 2026-09-25. |
| AWS Budgets, standard action-free budget | budget-day | $0.00 in the full listed range `0-Inf` | HIGH `[VERIFIED]`; `AWSBudgets/current`, pubDate 2026-09-11, `BudgetsUsage`; checked 2026-09-25. See discrepancy below. |
| AWS Budgets, action-enabled budget | budget-day | $0.00 for first 62/month, then $0.10 | HIGH `[VERIFIED]`; `AWSBudgets/current`, pubDate 2026-09-11, `ActionEnabledBudgetsUsage`; checked 2026-09-25. |
| AWS Budgets report | message | $0.01 | HIGH `[VERIFIED]`; `AWSBudgets/current`, pubDate 2026-09-11; checked 2026-09-25. |
| Cost Anomaly Detection | - | No offer code found in the Price List index | LOW `[ASSUMED]`; `AWSBudgets` and `AWSCostExplorer` offers inspected 2026-09-25; see deferred Q1. |
| Cost Explorer console | - | No positive price-list line found | LOW `[ASSUMED]`; Price List index inspected 2026-09-25; see deferred Q1. |
| Cost Explorer API (`GetCostAndUsage`, etc.) | request | $0.01 | HIGH `[VERIFIED]`; `AWSCostExplorer/current`, pubDate 2026-09-11, `USE1-APIRequest`; checked 2026-09-25. |
| Cost Explorer granular hourly data storage | 1,000 UsageRecord-months | $0.01 | HIGH `[VERIFIED]`; `AWSCostExplorer/current`, pubDate 2026-09-11; checked 2026-09-25. |
| SNS email / Email-JSON delivery | notification | First 1,000/month free, then $2.00/100,000 | HIGH `[VERIFIED]`; `AmazonSNS/us-east-1`, pubDate 2026-09-15, `DeliveryAttempts-SMTP`; checked 2026-09-25. |
| SNS API requests, including Publish | request | First 1,000,000/month free, then $0.50/1M | HIGH `[VERIFIED]`; `AmazonSNS/us-east-1`, pubDate 2026-09-15, `Requests-Tier1`; checked 2026-09-25. |
| Standard SNS topic existence | - | No topic-hours charge line | HIGH `[VERIFIED]`; `AmazonSNS/us-east-1` offer inspected 2026-09-25. |
| IAM roles, policies, OIDC provider, STS | - | $0.00 | HIGH `[CITED]`; [IAM introduction](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html), accessed 2026-09-25. |
| ECR storage | GB-month | $0.10 | HIGH `[VERIFIED]`; `AmazonECR/us-east-1`, pubDate 2026-09-11; checked 2026-09-25. |
| ECR archive storage / retrieval | GB-month / GB | $0.10 (0-150 TB) / $0.03 retrieval | HIGH `[VERIFIED]`; `AmazonECR/us-east-1`, pubDate 2026-09-11; checked 2026-09-25. |
| EBS gp3 storage | GB-month | $0.08 | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24, `EBS:VolumeUsage.gp3`; checked 2026-09-25. |
| EBS gp3 provisioned IOPS above baseline | IOPS-month | $0.005 | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24, `EBS:VolumeP-IOPS.gp3`; checked 2026-09-25. |
| EBS gp3 throughput above baseline | MiBps-month | $0.04 | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24, `EBS:VolumeP-Throughput.gp3`; checked 2026-09-25. |
| EBS gp3 included baseline | - | 3,000 IOPS + 125 MiB/s included | LOW `[ASSUMED]`; incremental SKUs checked 2026-09-25; baseline not stated by the inspected price list, see Q4. |
| EC2 `t4g.nano`, Linux on-demand, shared tenancy | hour | $0.0042 ($3.07/month) | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24; checked 2026-09-25. |
| Public IPv4, in-use | hour | $0.005 ($3.65/month) | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1`, pubDate 2026-09-17, `USE1-PublicIPv4:InUseAddress`; checked 2026-09-25. |
| Public IPv4, idle/unattached EIP | hour | $0.005 ($3.65/month) | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1`, pubDate 2026-09-17, `USE1-PublicIPv4:IdleAddress`; checked 2026-09-25. |
| Public IPv4, contiguous BYOIP block | hour/IP | $0.008 | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1`, pubDate 2026-09-17, `USE1-PublicIPv4:ContiguousBlock`; checked 2026-09-25. |
| EKS control plane | cluster-hour | $0.10 ($73.00/month) | HIGH `[VERIFIED]`; `AmazonEKS/us-east-1`, pubDate 2026-09-18, `USE1-AmazonEKS-Hours:perCluster`; checked 2026-09-25. |
| EKS extended support surcharge | cluster-hour | +$0.50 (total $0.60/hour, $438/month) | HIGH `[VERIFIED]`; `AmazonEKS/us-east-1`, pubDate 2026-09-18, `USE1-AmazonEKS-Hours:extendedSupport`; checked 2026-09-25. The surcharge is additive, not a flat replacement. |
| Interface VPC endpoint | endpoint-ENI-hour | $0.01 ($7.30/AZ-month) | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1`, pubDate 2026-09-17, `USE1-VpcEndpoint-Hours`; checked 2026-09-25. |
| Interface VPC endpoint data processed | GB | $0.01 (<=1 PB), $0.006 (1-5 PB), $0.004 (>5 PB) | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1`, pubDate 2026-09-17, `USE1-VpcEndpoint-Bytes`; checked 2026-09-25. |
| S3/DynamoDB gateway VPC endpoint | - | No charge line found | HIGH `[VERIFIED]`; `AmazonVPC/us-east-1` offer inspected 2026-09-25. |
| Internet data transfer out, free tier | GB/month | First 100 GB/month free, aggregated globally | HIGH `[VERIFIED]`; `AWSDataTransfer/us-east-1`, pubDate 2026-09-16, `Global-DataTransfer-Out-Bytes`; checked 2026-09-25. |
| Internet data transfer out, beyond free tier | GB | $0.090 (first 10 TB), then $0.085/$0.070/$0.050 | HIGH `[VERIFIED]`; `AWSDataTransfer/us-east-1`, pubDate 2026-09-16; checked 2026-09-25. |
| Cross-AZ/regional data transfer | GB | $0.010 each direction ($0.02/GB round trip) | HIGH `[VERIFIED]`; `AWSDataTransfer/us-east-1`, pubDate 2026-09-16, `DataTransfer-Regional-Bytes`; checked 2026-09-25. |
| Cross-AZ/regional data transfer, free tier | GB/month | First 1 GB/month free | HIGH `[VERIFIED]`; `AWSDataTransfer/us-east-1`, pubDate 2026-09-16, `Global-DataTransfer-Regional-Bytes`; checked 2026-09-25. |
| NAT Gateway | hour | $0.045 ($32.85/month) | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24, `NatGateway-Hours`; checked 2026-09-25. |
| NAT Gateway data processed | GB | $0.045 | HIGH `[VERIFIED]`; EC2 `index.csv`, Last-Modified 2026-09-24, `NatGateway-Bytes`; checked 2026-09-25. |
| Classic ALB/NLB base rates | hour | Not re-verified; not used by L0 | MEDIUM `[ASSUMED]`; prior research `PITFALLS.md`, last checked 2026-09-25. |
| Route 53 public hosted zone | zone-month | $0.50; not used by L0 | MEDIUM `[ASSUMED]`; prior research `PITFALLS.md`, last checked 2026-09-25. |

### AWS Budgets pricing discrepancy

The Price List Bulk API reports `BudgetsUsage = $0.00` over the full range `0-Inf`, while the long-standing
model is two free budgets then `$0.02/budget-day`. The `$0.02` SKU was absent; the only nonzero budget SKU
was `ActionEnabledBudgetsUsage` at `$0.10/budget-day` after 62 free action-enabled budget-days/month, matching
the documented two free action-enabled budgets per account. This phase creates action-free `COST` budgets,
so the cost model is `$0.00` under either model. Do not propagate `$0.02/budget-day` to later phases without
rechecking. Source: `AWSBudgets/current`, pubDate 2026-09-11; checked 2026-09-25. Q2 remains deferred.

### Not applicable to L0

- Route 53 public hosted zones: prior research estimates `$0.50/zone-month`; not created in Phase 1 and
  not re-verified on 2026-09-25. The 12-hour deletion grace claim remains `[ASSUMED]`.
- ALB/NLB: prior research estimates a `$0.0225/hour` base rate; Phase 4+, not re-verified on 2026-09-25.

## Phase 1 idle cost model

**Scope (D-20):** after Phase 1, `layers/00-bootstrap` contains the S3 state bucket, GitHub OIDC provider and
two CI roles, and cost guardrails (Budget, Cost Anomaly Detection monitor, SNS topic, and email subscription).
No other resources live in this L0 layer. Usage assumptions:

- About 200 Terraform backend operations/month; each uses approximately four Tier 1 (PUT/LIST, including the
  native S3 lock object) and six Tier 2 (GET/HEAD) requests.
- L0 state is about 50 KB. With versioning, about 200 noncurrent versions accrue in month one (about 10 MB).
- No more than 20 alert emails/month.

| # | Line item | Driver | Rate | Monthly |
|---|---|---:|---:|---:|
| 1 | S3 Standard state + noncurrent versions | 0.010 GB | $0.023/GB-month | $0.0002 |
| 2 | S3 Tier 1 requests (PUT/COPY/POST/LIST + lock object) | ~800 requests | $0.000005/request | $0.0040 |
| 3 | S3 Tier 2 requests (GET and other) | ~1,200 requests | $0.0000004/request | $0.0005 |
| 4 | DynamoDB state lock table | - | - | $0.00; absent by design because native S3 `use_lockfile` is used. |
| 5 | IAM OIDC provider | 1 | $0.00 | $0.00 |
| 6 | IAM roles and policies | 2 | $0.00 | $0.00 |
| 7 | AWS Budgets, one monthly action-free COST budget | 1 budget | $0.00/budget-day | $0.00 |
| 8 | Cost Anomaly Detection monitor + subscription | 1 + 1 | No offer code found | $0.00 `[ASSUMED]` |
| 9 | Standard SNS topic | 1 | No topic-hours SKU | $0.00 `[VERIFIED]` |
| 10 | SNS Publish API requests | ~20 | First 1M/month free | $0.00 |
| 11 | SNS email deliveries | ~20 | First 1,000/month free | $0.00 |
| 12 | Cost Explorer console | - | No positive price-list line | $0.00 `[ASSUMED]` |
| 13 | KMS key for SNS/S3 SSE | - | None; SSE-S3 (`AES256`) is free | $0.00 |
| | **TOTAL** | | | **~$0.005; round to $0.01/month** |

The model is below the `$5/month` ceiling with **$4.99 of headroom (99.9%)**. L0 is effectively free; the
ceiling exists to catch leakage from later phases, not to constrain the bootstrap layer. There is no
DynamoDB lock-table cost because state locking uses S3 `use_lockfile`.

**Future leakage scale, at verified us-east-1 list prices:**

| Future leak | Rate | Monthly if left up | Share of $5 ceiling |
|---|---:|---:|---:|
| One forgotten EKS control plane | $0.10/hour | $73.00 | 1,460% |
| One orphaned NAT Gateway | $0.045/hour | $32.85 | 657% |
| One orphaned ALB, base | $0.0225/hour | $16.43 | 329% |
| One interface VPC endpoint, one AZ | $0.01/hour | $7.30 | 146% |
| One orphaned/idle Elastic IP | $0.005/hour | $3.65 | 73% |
| fck-nat `t4g.nano`, always on | $0.0042/hour | $3.07 | 61% |
| 10 GB of stale ECR images | $0.10/GB-month | $1.00 | 20% |

An idle Elastic IP alone consumes 73% of the monthly ceiling and crosses `$1` in about 8.3 days, reinforcing
the need for the teardown verifier and the daily actual-spend budget.

## Alerting cold-start windows

### AWS Budgets forecast history

AWS Budgets needs roughly **five weeks of spend history** before producing a forecast. The monthly budget's
50/80/100% forecast notifications are therefore inert for about five weeks on a new member account; the
100%-of-actual notification is live. Keep the forecast notifications for later use and rely on the daily
`ACTUAL`/`ABSOLUTE_VALUE` `$1` budget from plan 01-06 for deterministic first-day coverage. Source:
`01-RESEARCH.md` F-03; verified against AWS documentation during research on 2026-09-25.

### Cost Anomaly Detection history and blind spots

Cost Anomaly Detection requires **10 days of per-service history**, plus up to 24 hours of monitor warm-up and
up to 24 hours of Cost Explorer data lag. A new service's first reliable anomaly alert is therefore around
day 11-12 after its first spend. The alert detector also scores only usage-type charges and does not monitor
Route 53, ACM, Support, AWS Budgets, or Cost Explorer; a leaked hosted zone can be invisible to the detector,
so the actual-spend budget is the early proxy. Source: `01-RESEARCH.md` F-02; verified against AWS
documentation during research on 2026-09-25.

## Deferred observations

None of these observations gates Phase 1. Each phase-sealing proxy is named in
`.planning/phases/01-account-l0-bootstrap-teardown-harness/01-VALIDATION.md`.

| Observation | Why it cannot be observed now | Testable from | Recorded on |
|---|---|---|---|
| Cost Explorer per-layer attribution in a real billing period | Requires tagged spend, management-account tag activation, and a complete billing period; tags never backfill. | Earliest 2026-12-01 if tags activate by 2026-10-31; otherwise after one full calendar month following activation and the next Cost Explorer refresh. | |
| First real Cost Anomaly Detection alert | Requires 10 days of per-service history, up to 24 hours of warm-up, and up to 24 hours of data lag. | Earliest 12 days after first billable service usage; if first usage is 2026-10-08, earliest 2026-10-20. Recalculate from actual first-use date. | |
| Whether Cost Anomaly Detection is genuinely free (Research Q1) | No offer code exists in the Price List index; absence is not proof of `$0`. The pricing page is JavaScript-rendered and not machine-scrapable. Impact if wrong is negligible (cents at worst). | Earliest 2026-11-01 after the first full billing cycle if the monitor exists during October; inspect whether the cycle shows an `AWSCostExplorer`-family line item. | |

Phase 2 appends measured `make up` and `make down` wall-clock times to this same file (COST-09).