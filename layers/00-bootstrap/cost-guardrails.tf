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
    # Deliberately unconditioned to match the canonical AWS/provider example.
  }

  # aws_sns_topic_policy replaces the whole policy; preserve account-owner access.
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

resource "aws_sns_topic" "cost_alerts" {
  name = "cost-alerts"

  # Do not enable topic encryption: AWS Budgets alerts need extra permissions,
  # and a KMS key would consume a fifth of the monthly cost ceiling.
}

resource "aws_sns_topic_policy" "cost_alerts" {
  arn    = aws_sns_topic.cost_alerts.arn
  policy = data.aws_iam_policy_document.cost_alerts.json
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # The ARN remains "pending confirmation" until a human clicks the email link.
  # Do not make other resources depend on this attribute.
}

output "cost_alerts_topic_arn" {
  description = "SNS topic ARN for cost and anomaly alerts."
  value       = aws_sns_topic.cost_alerts.arn
}