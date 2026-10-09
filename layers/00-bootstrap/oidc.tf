locals {
  gh_oidc_host = "token.actions.githubusercontent.com"

  gh_owner_seg = var.github_owner_id == null ? var.github_owner : "${var.github_owner}@${var.github_owner_id}"
  gh_repo_seg  = var.github_repo_id == null ? var.github_repo : "${var.github_repo}@${var.github_repo_id}"
  gh_repo_ref  = "repo:${local.gh_owner_seg}/${local.gh_repo_seg}"

  gh_sub_develop = "${local.gh_repo_ref}:ref:refs/heads/develop"
  gh_sub_pr      = "${local.gh_repo_ref}:pull_request"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.gh_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub tokens against its trusted-root store and ignores supplied thumbprints.
  # Do not add thumbprint rotation automation.
}

data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    sid     = "GitHubOIDCPullRequestOnly"
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
      values   = [local.gh_sub_pr]
    }
  }
}

resource "aws_iam_role" "gha_terraform_plan" {
  name                 = "gha-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.gha_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

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

resource "aws_iam_role_policy" "gha_plan_state" {
  name   = "terraform-state-read-lock"
  role   = aws_iam_role.gha_terraform_plan.id
  policy = data.aws_iam_policy_document.gha_plan_state.json
}

output "gha_plan_role_arn" {
  description = "GitHub Actions plan role ARN; trusted only for pull requests."
  value       = aws_iam_role.gha_terraform_plan.arn
}

data "aws_iam_policy_document" "gha_sweep_trust" {
  statement {
    sid     = "GitHubOIDCDevelopSweepOnly"
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
      values   = [local.gh_sub_develop]
    }
  }
}

resource "aws_iam_role" "gha_terraform_sweep" {
  name                 = "gha-terraform-sweep"
  assume_role_policy   = data.aws_iam_policy_document.gha_sweep_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_sweep_readonly" {
  role       = aws_iam_role.gha_terraform_sweep.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "gha_sweep_state_guard" {
  statement {
    sid       = "DenyTerraformStateObjectReads"
    effect    = "Deny"
    actions   = ["s3:GetObject*"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "gha_sweep_state_guard" {
  name   = "deny-terraform-state-object-reads"
  role   = aws_iam_role.gha_terraform_sweep.id
  policy = data.aws_iam_policy_document.gha_sweep_state_guard.json
}

output "gha_sweep_role_arn" {
  description = "GitHub Actions teardown sweep role ARN; trusted only for develop."
  value       = aws_iam_role.gha_terraform_sweep.arn
}

data "aws_iam_policy_document" "gha_apply_trust" {
  statement {
    sid     = "GitHubOIDCDevelopBranchOnly"
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
      values   = [local.gh_sub_develop]
    }
  }
}

resource "aws_iam_role" "gha_terraform_apply" {
  name                 = "gha-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.gha_apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_apply_admin" {
  role       = aws_iam_role.gha_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

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
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gha_apply_guardrails" {
  name   = "phase1-broad-apply-guardrails"
  role   = aws_iam_role.gha_terraform_apply.id
  policy = data.aws_iam_policy_document.gha_apply_guardrails.json

  # TEMPORARY (D-28). Phase 10 replaces AdministratorAccess with an IAM Access Analyzer-derived
  # least-privilege policy based on recorded CloudTrail activity.
}

# Do not add a GitHub Actions environment to the apply job without updating this subject:
# environment claims take precedence over branch refs, regardless of the workflow trigger.
output "gha_apply_role_arn" {
  description = "GitHub Actions apply role ARN; trusted only for the develop branch."
  value       = aws_iam_role.gha_terraform_apply.arn
}