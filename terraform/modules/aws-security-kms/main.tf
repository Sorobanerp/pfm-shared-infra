data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "kms_master" {
  statement {
    sid    = "EnableAccountRootManagement"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseOfKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AllowAutoScalingServiceLinkedRoleUseOfKey"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAutoScalingServiceLinkedRoleAttachGrants"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      ]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "AllowCloudTrailEncryptAuditLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

# =============================================================================
# Domain 1: GitHub Actions OIDC Least-Privilege Trust Policy (No Wildcard *)
# =============================================================================
locals {
  allowed_github_oidc_subjects = [
    "repo:Sorobanerp/pfm-shared-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-shared-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-core-ledger-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-ingestion-bff-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-forecast-engine-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-ai-worker-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-web-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-finops-manager-infra:ref:refs/heads/develop",
    "repo:Sorobanerp/pfm-shared-infra:environment:production",
    "repo:Sorobanerp/pfm-ingestion-bff-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-ingestion-bff-infra:environment:production",
    "repo:Sorobanerp/pfm-core-ledger-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-core-ledger-infra:environment:production",
    "repo:Sorobanerp/pfm-forecast-engine-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-forecast-engine-infra:environment:production",
    "repo:Sorobanerp/pfm-ai-worker-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-ai-worker-infra:environment:production",
    "repo:Sorobanerp/pfm-web-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-web-infra:environment:production",
    "repo:Sorobanerp/pfm-finops-manager-infra:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-finops-manager-infra:environment:production",
    "repo:Sorobanerp/pfm-ingestion-bff-go:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-ingestion-bff-go:environment:production",
    "repo:Sorobanerp/pfm-core-ledger-java:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-core-ledger-java:environment:production",
    "repo:Sorobanerp/pfm-forecast-engine-go:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-forecast-engine-go:environment:production",
    "repo:Sorobanerp/pfm-ai-worker-python:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-ai-worker-python:environment:production",
    "repo:Sorobanerp/pfm-web-nextjs:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-web-nextjs:environment:production",
    "repo:Sorobanerp/pfm-mobile-android:ref:refs/heads/main",
    "repo:Sorobanerp/pfm-mobile-android:environment:production"
  ]
}

data "aws_iam_policy_document" "github_actions_oidc_trust" {
  statement {
    sid     = "GitHubActionsOidcStrictRepoAndBranchGuard"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_github_oidc_subjects
    }
  }
}

# =============================================================================
# Domain 3: OpenTofu Remote State Bucket & DynamoDB Lock Guardrail Policy Docs
# =============================================================================
data "aws_iam_policy_document" "tfstate_bucket_guardrail" {
  statement {
    sid     = "DenyInsecureTransportOnTfState"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      "arn:aws:s3:::sorobanerp-pfm-tfstate-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}",
      "arn:aws:s3:::sorobanerp-pfm-tfstate-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyTfStateBucketAndObjectDeletion"
    effect  = "Deny"
    actions = ["s3:DeleteBucket", "s3:DeleteObject", "s3:DeleteObjectVersion"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      "arn:aws:s3:::sorobanerp-pfm-tfstate-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}",
      "arn:aws:s3:::sorobanerp-pfm-tfstate-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}/*"
    ]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }
}

resource "aws_kms_key" "master" {
  description             = "PFM Platform Master KMS Key for Envelope Encryption, RDS, ElastiCache and EKS Secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_master.json

  tags = {
    Name        = "pfm-master-key-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Compliance  = "ADR-006-Envelope-Encryption"
  }
}

resource "aws_kms_alias" "master" {
  name          = var.alias_name
  target_key_id = aws_kms_key.master.key_id
}

# =============================================================================
# Domain 7: AWS CloudTrail Governance Audit Trail (Zero-CloudWatch FinOps)
# =============================================================================
resource "aws_s3_bucket" "cloudtrail_audit" {
  bucket        = "pfm-cloudtrail-audit-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name        = "pfm-cloudtrail-audit-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Compliance  = "BACEN-4893-CloudTrail"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_audit" {
  bucket = aws_s3_bucket.cloudtrail_audit.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.master.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_audit" {
  bucket = aws_s3_bucket.cloudtrail_audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_audit" {
  bucket = aws_s3_bucket.cloudtrail_audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_audit" {
  bucket = aws_s3_bucket.cloudtrail_audit.id

  rule {
    id     = "expire-cloudtrail-logs-90d"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_audit_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.cloudtrail_audit.arn]
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.cloudtrail_audit.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.cloudtrail_audit.arn,
      "${aws_s3_bucket.cloudtrail_audit.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_audit" {
  bucket = aws_s3_bucket.cloudtrail_audit.id
  policy = data.aws_iam_policy_document.cloudtrail_audit_bucket.json
}

# trivy:ignore:AVD-AWS-0162 FinOps ADR-010 Zero-CloudWatch policy: CloudTrail logs are stored in KMS-encrypted S3 with log file validation
resource "aws_cloudtrail" "pfm_governance" {
  count                         = var.enable_cloudtrail_trail ? 1 : 0
  name                          = "pfm-governance-trail-${var.environment}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_audit.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.master.arn

  tags = {
    Name        = "pfm-governance-trail-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_audit]
}
