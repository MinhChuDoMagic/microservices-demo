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

## 2. Confirm centralized member-root security and non-root administration

Use IAM Identity Center for day-to-day access. AWS recommends centrally removing root credentials
from Organizations member accounts; newly created organization accounts have no root credentials by
default. Confirm in the management account's IAM **Root access management** view that this member's
root credentials are centrally managed/removed. Do not create a member root password or enable root
MFA merely to make `AccountMFAEnabled` equal `1`; in a credential-less member account that flag is
expected to be `0`. If root credentials are present instead, enable MFA before continuing. See
[AWS root user best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html)
and [Centrally manage root access for member accounts](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html#id_root-user-access-management).

```bash
aws iam get-credential-report --profile microservices-demo --query Content --output text |
python3 -c 'import base64,csv,io,sys; rows=csv.DictReader(io.StringIO(base64.b64decode(sys.stdin.read()).decode())); root=next(row for row in rows if row["user"] == "<root_account>"); fields=("password_enabled", "access_key_1_active", "access_key_2_active", "cert_1_active", "cert_2_active"); present=any(root[key] == "true" for key in fields); assert not present or root["mfa_active"] == "true", "root credentials exist without MFA"; print({"root_credentials_present": present, "mfa_active": root["mfa_active"]})'
CALLER_ARN="$(aws sts get-caller-identity --profile microservices-demo --query Arn --output text)"
case "$CALLER_ARN" in *:root) printf '%s\n' 'Use the non-root IAM Identity Center administrator' >&2; exit 1 ;; esac
```

## 3. Activate member-account IAM access to billing pages

In the **member account**, use the management account's authorized centralized root task or the
member's supported account-recovery process to open Account settings -> **IAM user and role access
to Billing information** -> **Activate IAM Access**. Do not create persistent member root
credentials if centralized root access management is in use. This is separate from IAM policy permissions:
the administrator role must also have the required Cost Management and Billing actions. This toggle
applies to the member account's console pages; it does not grant access to other organization
accounts or override management-account Cost Explorer restrictions.

```bash
aws ce get-cost-and-usage \
  --time-period "Start=$(date -u -v-2d +%F),End=$(date -u +%F)" \
  --granularity DAILY --metrics UnblendedCost
```

This confirms member-account Cost Explorer data access, but it does not directly test the
console-only toggle. Verify **Activate IAM Access** by signing into the Billing and Cost Management
console as the non-root administrator and confirming the Cost Explorer page loads. If the CLI query
is denied, verify the role policy and management-account member-access setting in step 4.

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

Repository `MinhChuDoMagic/microservices-demo` was created on 2026-09-23. Its owner ID is `82219047`
and repository ID is `1383184443`, so it uses immutable ID-qualified subjects. The trust policy
subjects are `repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:pull_request` for plans and
`repo:MinhChuDoMagic@82219047/microservices-demo@1383184443:ref:refs/heads/develop` for applies. This
format is selected from the repository creation date; no claim-debugger workflow was run because
this repository is public.

The apply role is scoped to the repository's `develop` default branch. Do not add a GitHub Actions
`environment:` to the apply job without updating the trust policy in the same change. Environment
claims take precedence over branch refs and would stop the develop-branch subject from matching.

```bash
gh api repos/OWNER/REPO \
  --jq '{owner: .owner.login, owner_id: .owner.id, repo: .name, repo_id: .id, created: .created_at}'
```

## Deferred observations

The following observations do not gate Phase 1. Their phase-sealing proxies and testable-from dates
are tracked in `COSTS.md` and `01-VALIDATION.md`.

- Per-layer Cost Explorer attribution against a real billing period.
- The first real Cost Anomaly Detection alert after its history and warm-up windows.