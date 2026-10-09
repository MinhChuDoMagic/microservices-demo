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

resource "aws_budgets_budget" "l0_monthly_ceiling" {
  name         = "l0-monthly-cost-ceiling"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

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

  # Forecast notifications need about five weeks of history; the actual alert
  # is the only monthly notification available during the account cold start.
  # Budgets compares strictly greater-than: exactly $5.00 does not notify;
  # spending above $5.00 crosses the 100%-actual threshold.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = "50"
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = "80"
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = "100"
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = "100"
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

resource "aws_budgets_budget" "l0_daily_tripwire" {
  name         = "l0-daily-tripwire"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "DAILY"

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

  # This deterministic daily budget covers the anomaly monitor's cold start;
  # it is a phase-sealing proxy, not a replacement for anomaly detection.
  # GREATER_THAN means $0.99 and exactly $1.00 do not notify; only spend above
  # $1.00 crosses the threshold, subject to the Budgets refresh interval.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = "1"
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

resource "aws_ce_anomaly_monitor" "account_services" {
  name              = "l0-account-service-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "cost_alerts" {
  name      = "l0-anomaly-1usd"
  frequency = "IMMEDIATE"

  monitor_arn_list = [aws_ce_anomaly_monitor.account_services.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}