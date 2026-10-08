# AWS Account Setup Runbook

This runbook prepares the dedicated AWS Organizations member account used by this repository. The
Organization management account and payer are outside Terraform and this repository. Keep the
account ID in the gitignored `.aws-account-id` file; never copy it into tracked files.

## 1. Pin the project account

Use the newly created dedicated member account confirmed at the Phase 1 account checkpoint. Confirm
that it is effectively empty and that no workload must survive the teardown sweep. The checkpoint
confirmed no survivors. Sign in to the member account using the intended administrator identity,
compare its caller identity to the checkpoint, then save that ID to `.aws-account-id`.

```bash
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
read -r -p 'Enter the verified member account ID from the checkpoint: ' EXPECTED_ACCOUNT_ID
ACTUAL_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
test "$ACTUAL_ACCOUNT_ID" = "$EXPECTED_ACCOUNT_ID"
printf '%s\n' "$ACTUAL_ACCOUNT_ID" > .aws-account-id
git check-ignore -q .aws-account-id
```

If the IDs differ, stop without writing the pin. `make doctor` compares this pin with the active
caller identity before any AWS-touching Make target.

## 2. Confirm root MFA and non-root administration

In the member account, enable MFA for root and create/use a non-root administrator identity for
day-to-day work. Do not create access keys for root or commit long-lived credentials.

Console: member account menu -> **Security credentials** for root MFA; IAM Identity Center or IAM
for the non-root administrator, according to the account's existing access setup.

```bash
test "$(aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text)" = 1
CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
case "$CALLER_ARN" in *:root) printf '%s\n' 'Use a non-root administrator' >&2; exit 1 ;; esac
printf '%s\n' "$CALLER_ARN"
```

## 3. Activate member-account IAM access to billing pages

In the **member account**, sign in as root and open Account settings -> **IAM user and role access to
Billing information** -> **Activate IAM Access**. This is separate from IAM policy permissions:
the administrator role must also have the required Cost Management and Billing actions. This toggle
applies to the member account's console pages; it does not grant access to other organization
accounts or override management-account Cost Explorer restrictions.

```bash
aws ce list-cost-allocation-tags --status Active --output table
```

If this call is denied, verify both the role policy and the member account's **Activate IAM Access**
setting. Cost Explorer must also be enabled for the organization as described in step 4.

## 4. Enable Cost Explorer for the organization and verify member visibility

Cost Explorer has no enablement API. The **Organizations management account** must open Billing and
Cost Management -> Cost Explorer -> **Launch Cost Explorer**. Organization-level enablement grants
member access by default, but the management account can restrict all member accounts through Cost
Management Preferences -> **Member account permissions** -> **Linked account access**. The member
account can see only its own cost and usage data; it cannot inspect the management account or other
members. Management-account IAM/SCP policy can also deny access.

After management confirms Cost Explorer is enabled and this member is allowed, run from the project
member account. Current-month data generally appears in about 24 hours; older history may take a few
days longer.

```bash
ACCOUNT_ID="$(cat .aws-account-id)"
aws ce get-cost-and-usage \
  --time-period "Start=$(date -u -v-2d +%F),End=$(date -u +%F)" \
  --granularity DAILY --metrics UnblendedCost \
  --filter "{\"Dimensions\":{\"Key\":\"LINKED_ACCOUNT\",\"Values\":[\"$ACCOUNT_ID\"]}}"
```

An access-denied response is a management-account permission issue to resolve there, not a reason to
switch accounts or widen the Terraform role. Cost Explorer launch is one-time; it refreshes cost
data at least daily.

## 5. Activate cost-allocation tag keys after the first tagged apply

Only the **Organizations management account** can manage cost-allocation tags for the organization.
Do not activate keys yet: a key must first appear from a tagged resource, which will be the L0 state
bucket created by plan 01-04. After that apply, allow up to 24 hours for keys to appear and up to a
further 24 hours for activation. Activate `Project`, `Layer`, `ManagedBy`, and `Environment` as soon
as they appear; plan 01-10 owns the phase's activation checkpoint.

Cost-allocation tags never backfill: resources created before a key is activated remain permanently
unattributed for that earlier usage. Record the activation date and unattributable window in
`COSTS.md`. When member accounts move between Organizations, AWS requires cost-allocation tags to be
reactivated by the new management account.

```bash
# Run with management-account authorization after the first tagged apply and after the keys appear.
aws ce list-cost-allocation-tags --status Inactive --output table
aws ce update-cost-allocation-tags-status --cost-allocation-tags-status \
  TagKey=Project,Status=Active TagKey=Layer,Status=Active \
  TagKey=ManagedBy,Status=Active TagKey=Environment,Status=Active
aws ce list-cost-allocation-tags --status Active --output table
```

## 6. Confirm the SNS email subscription

After plan 01-06 creates the topic and email subscription, open the confirmation message sent to the
operator-provided alert address and select **Confirm subscription**. Terraform can report a
successful apply while the subscription is inert; its ARN remains the literal pending-confirmation
string until a human accepts it.

```bash
TOPIC_ARN='<cost-alerts SNS topic ARN>'
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn}' \
  --output table
```

Confirm that the email subscription has a real ARN and is `Confirmed`, not `PendingConfirmation`.
If the message was missed, request a new subscription; SNS does not retry confirmation automatically.

## 7. Record the GitHub OIDC subject format

Before plan 01-07 writes the trust policies, check the repository's creation date and immutable
identifiers. Repositories created on or after 2026-07-15 use owner-ID and repository-ID qualified
subjects; the IAM policy must match the observed format exactly. Record the result in this runbook
without recording AWS account IDs or secrets.

```bash
gh api repos/OWNER/REPO \
  --jq '{owner: .owner.login, owner_id: .owner.id, repo: .name, repo_id: .id, created: .created_at}'
```

## Deferred observations

The following observations do not gate Phase 1. Their phase-sealing proxies and testable-from dates
are tracked in `COSTS.md` and `01-VALIDATION.md`.

- Per-layer Cost Explorer attribution against a real billing period.
- The first real Cost Anomaly Detection alert after its history and warm-up windows.