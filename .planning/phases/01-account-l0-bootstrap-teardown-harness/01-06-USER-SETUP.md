# Phase 1: User Setup Required

**Generated:** 2026-10-09
**Phase:** 01-account-l0-bootstrap-teardown-harness
**Status:** Complete

## Environment Variables

| Status | Variable | Source | Add to |
|--------|----------|--------|--------|
| [x] | `alert_email` | `layers/00-bootstrap/terraform.tfvars` (gitignored) | `layers/00-bootstrap/terraform.tfvars` |

The address is intentionally not repeated in this tracked file.

## Dashboard Configuration

- [x] **Confirm the cost-alert email subscription**
  - Location: Operator inbox; the message is sent by AWS Notifications for the `cost-alerts` topic.
  - Action: Open the subscription message and click **Confirm subscription**.
  - If no message arrived: verify `alert_email` in the gitignored tfvars file, then re-apply the bootstrap layer to request a new subscription.

## Verification

After confirming the email, run from the repository root:

```bash
TOPIC_ARN=$(AWS_PROFILE=microservices-demo terraform -chdir=layers/00-bootstrap output -raw cost_alerts_topic_arn)
AWS_PROFILE=microservices-demo aws sns list-subscriptions-by-topic \
  --topic-arn "$TOPIC_ARN" \
  --query "length(Subscriptions[?Protocol=='email' && SubscriptionArn!='PendingConfirmation'])" \
  --output text
```

Expected result: at least `1` confirmed email subscription.

Verify the topic is tagged for the bootstrap layer without displaying the subscriber address:

```bash
AWS_PROFILE=microservices-demo aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Layer,Values=00-bootstrap \
  --query "ResourceTagMappingList[?ResourceARN=='$TOPIC_ARN'].[ResourceARN,Tags[?Key=='Layer'].Value|[0]]" \
  --output text
```

Expected result: the cost-alert topic ARN and a non-empty `00-bootstrap` layer value.

---

**Once confirmed:** mark the status as `Complete` and check the confirmation item above.
