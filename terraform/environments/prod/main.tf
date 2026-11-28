provider "aws" {
  region = var.aws_region
}

provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.us3.datadoghq.com/"
  validate = false
}

module "network" {
  source             = "../../modules/aws-network"
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  cluster_name       = var.cluster_name
  availability_zones = ["us-east-2a", "us-east-2b"]
  enable_nat_gateway = var.enable_nat_gateway
}

module "security_kms" {
  source      = "../../modules/aws-security-kms"
  environment = var.environment
  alias_name  = var.environment == "prod" ? "alias/pfm-master-key" : "alias/pfm-master-key-${var.environment}"
}

module "database_per_service" {
  source                      = "../../modules/aws-database-per-service"
  environment                 = var.environment
  vpc_id                      = module.network.vpc_id
  vpc_cidr                    = module.network.vpc_cidr
  private_subnet_ids          = module.network.private_subnet_ids
  kms_master_key_arn          = module.security_kms.kms_master_key_arn
  ecs_tasks_security_group_id = module.ecs_pilot.ecs_tasks_security_group_id
}

resource "aws_s3_bucket" "statements" {
  bucket = "pfm-statements-encrypted-${var.environment}"

  tags = {
    Name        = "pfm-statements-encrypted-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Project     = "PFM-Core-Banking"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "statements" {
  bucket = aws_s3_bucket.statements.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.security_kms.kms_master_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = aws_s3_bucket.statements.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket = aws_s3_bucket.statements.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "statements_bucket_guardrail" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.statements.arn,
      "${aws_s3_bucket.statements.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyDeleteBucket"
    effect  = "Deny"
    actions = ["s3:DeleteBucket"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.statements.arn]
  }
}

resource "aws_s3_bucket_policy" "statements_guardrail" {
  bucket = aws_s3_bucket.statements.id
  policy = data.aws_iam_policy_document.statements_bucket_guardrail.json
}

resource "aws_secretsmanager_secret" "upstash_kafka" {
  name_prefix             = "pfm/${var.environment}/upstash/kafka-"
  kms_key_id              = module.security_kms.kms_master_key_id
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

resource "aws_secretsmanager_secret_version" "upstash_kafka" {
  secret_id     = aws_secretsmanager_secret.upstash_kafka.id
  secret_string = var.upstash_kafka_url != "" ? var.upstash_kafka_url : "https://mock-upstash-kafka.internal"
}

resource "aws_secretsmanager_secret" "upstash_redis" {
  name_prefix             = "pfm/${var.environment}/upstash/redis-"
  kms_key_id              = module.security_kms.kms_master_key_id
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

resource "aws_secretsmanager_secret_version" "upstash_redis" {
  secret_id     = aws_secretsmanager_secret.upstash_redis.id
  secret_string = var.upstash_redis_url != "" ? var.upstash_redis_url : "rediss://default:mock@mock-upstash-redis.internal:6379"
}

resource "aws_secretsmanager_secret" "datadog_api_key" {
  name_prefix             = "pfm/${var.environment}/datadog/api-key-"
  description             = "Datadog API Key for Unified Service Tagging & OpenTelemetry OTLP (ADR-010)"
  kms_key_id              = module.security_kms.kms_master_key_id
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    ADR         = "ADR-010"
  }
}

module "ecs_pilot" {
  source                 = "../../modules/aws-ecs-pilot"
  environment            = var.environment
  cluster_name           = var.cluster_name
  vpc_id                 = module.network.vpc_id
  vpc_cidr               = module.network.vpc_cidr
  private_subnet_ids     = module.network.private_subnet_ids
  public_subnet_ids      = module.network.public_subnet_ids
  kms_master_key_arn     = module.security_kms.kms_master_key_arn
  enable_cloudwatch_logs = var.enable_cloudwatch_logs
  desired_count          = var.desired_count
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
}

module "event_backbone" {
  source = "../../modules/event-backbone"
}

module "observability_datadog" {
  count                   = var.enable_datadog_monitors ? 1 : 0
  source                  = "../../modules/observability-datadog"
  namespace               = "monitoring"
  datadog_site            = "us3.datadoghq.com"
  api_key_existing_secret = "datadog-secret"
  enable_helm_agent       = false
  enable_datadog_monitors = var.enable_datadog_monitors
  environment             = var.environment
}
