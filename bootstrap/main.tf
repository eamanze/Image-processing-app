data "aws_caller_identity" "current" {}

locals {
  repository_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"
  application_state  = "cloud-image-pipeline/production/terraform.tfstate"
  bootstrap_state    = "bootstrap/terraform.tfstate"
  state_objects = [
    "${aws_s3_bucket.terraform_state.arn}/${local.application_state}",
    "${aws_s3_bucket.terraform_state.arn}/${local.application_state}.tflock",
    "${aws_s3_bucket.terraform_state.arn}/${local.bootstrap_state}",
    "${aws_s3_bucket.terraform_state.arn}/${local.bootstrap_state}.tflock",
  ]
  oidc_provider_arn = one(concat(
    aws_iam_openid_connect_provider.github[*].arn,
    data.aws_iam_openid_connect_provider.github[*].arn
  ))
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-noncurrent-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.repository_subject}:pull_request",
        "${local.repository_subject}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "deploy_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.repository_subject}:environment:production",
        "${local.repository_subject}:environment:production-destroy",
      ]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "CloudImagePipelinePlanRole"
  description          = "Read-only AWS planning role assumed by GitHub Actions"
  assume_role_policy   = data.aws_iam_policy_document.plan_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role" "github_deploy" {
  name                 = "CloudImagePipelineDeployRole"
  description          = "Application deployment role assumed by protected GitHub environments"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        local.application_state,
        "${local.application_state}.tflock",
        local.bootstrap_state,
        "${local.bootstrap_state}.tflock",
      ]
    }
  }

  statement {
    sid       = "ReadWriteStateAndLocks"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = local.state_objects
  }

  statement {
    sid     = "DeleteLockFilesOnly"
    actions = ["s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.terraform_state.arn}/${local.application_state}.tflock",
      "${aws_s3_bucket.terraform_state.arn}/${local.bootstrap_state}.tflock",
    ]
  }
}

resource "aws_iam_policy" "state_access" {
  name        = "CloudImagePipelineTerraformStateAccess"
  description = "Access to the image pipeline state and S3-native lock files"
  policy      = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  role       = aws_iam_role.github_plan.name
  policy_arn = aws_iam_policy.state_access.arn
}

resource "aws_iam_role_policy_attachment" "deploy_state" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.state_access.arn
}

data "aws_iam_policy_document" "deployment" {
  statement {
    sid = "ManageApplicationServices"
    actions = [
      "acm:*",
      "apigateway:*",
      "cloudfront:*",
      "cloudwatch:*",
      "lambda:*",
      "logs:*",
      "sqs:*",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ManageApplicationBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::cloud-image-pipeline-dev-*",
      "arn:aws:s3:::cloud-image-pipeline-dev-*/*",
    ]
  }

  statement {
    sid = "ManageApplicationIamRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloud-image-pipeline-*"]
  }

  statement {
    sid = "ReadLambdaBasicExecutionPolicy"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  }

  statement {
    sid = "ManageApplicationDns"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["arn:aws:route53:::hostedzone/Z05717301OIDAACFNTRQO"]
  }

  statement {
    sid       = "DiscoverHostedZones"
    actions   = ["route53:GetChange", "route53:ListHostedZones", "route53:ListHostedZonesByName", "sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deployment" {
  name        = "CloudImagePipelineDeployment"
  description = "Manage the serverless image pipeline application resources"
  policy      = data.aws_iam_policy_document.deployment.json
}

resource "aws_iam_role_policy_attachment" "deployment" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.deployment.arn
}
