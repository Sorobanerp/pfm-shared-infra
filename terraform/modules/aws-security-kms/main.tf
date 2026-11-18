terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "prod"
}

variable "alias_name" {
  description = "KMS key alias name"
  type        = string
  default     = "alias/pfm-master-key"
}

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

output "kms_master_key_arn" {
  description = "ARN of the PFM master KMS key"
  value       = aws_kms_key.master.arn
}

output "kms_master_key_id" {
  description = "ID of the PFM master KMS key"
  value       = aws_kms_key.master.key_id
}
