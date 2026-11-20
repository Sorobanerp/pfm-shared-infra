# =============================================================================
# AWS Well-Architected Shared Landing Zone (us-east-2 Ohio) — FinOps Pilot Profile
# ADR-008: Amazon ECS Fargate Spot Arm64 + RDS PostgreSQL 16 + Upstash Kafka/Redis
# Target cost: ~US$ 11,50–24,00/mo (Eliminates US$ 73/mo EKS Control Plane)
# =============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.45"
    }
  }
}

variable "aws_region" {
  description = "Primary AWS Region (Ohio)"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Target environment name"
  type        = string
  default     = "prod"
}

variable "enable_datadog_monitors" {
  description = "Enable Datadog Unified Dashboard and Critical Security/SLO Monitors (ADR-010)"
  type        = bool
  default     = false
}

variable "datadog_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "datadog_app_key" {
  type      = string
  default   = ""
  sensitive = true
}

provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.us3.datadoghq.com/"
  validate = false
}

variable "enable_nat_gateway" {
  description = "Keep false in FinOps MVP to save ~US$ 32/mo; set true when scaling to private-subnet NAT"
  type        = bool
  default     = false
}

variable "upstash_kafka_url" {
  description = "Upstash Kafka broker REST/Bootstrap URL (Serverless)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "upstash_redis_url" {
  description = "Upstash Redis REST/TCP URL (Serverless)"
  type        = string
  default     = ""
  sensitive   = true
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source             = "../../modules/aws-network"
  environment        = var.environment
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-2a", "us-east-2b"]
  enable_nat_gateway = var.enable_nat_gateway
}

module "security_kms" {
  source      = "../../modules/aws-security-kms"
  environment = var.environment
  alias_name  = "alias/pfm-master-key"
}

# Single Shared RDS PostgreSQL 16 (hosts logical DBs/schemas: pfm_core_ledger + pfm_ai_rules with RLS)
# + Single Valkey cache.t4g.micro (0 AWS MSK clusters; Kafka via Upstash Serverless Secret)
module "database_per_service" {
  source             = "../../modules/aws-database-per-service"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  kms_master_key_arn = module.security_kms.kms_master_key_arn
}

# =============================================================================
# Amazon S3 Encrypted Bucket (PDF Statements & Attachments)
# =============================================================================
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
  bucket = "pfm-statements-encrypted-${var.environment}"

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.security_kms.kms_master_key_arn
      sse_algorithm     = "aws:kms"
    }
  }

  depends_on = [aws_s3_bucket.statements]
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = "pfm-statements-encrypted-${var.environment}"

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.statements]
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket = "pfm-statements-encrypted-${var.environment}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket.statements]
}

# =============================================================================
# AWS Secrets Manager for Upstash Kafka & Redis Serverless
# =============================================================================
resource "aws_secretsmanager_secret" "upstash_kafka" {
  name_prefix             = "pfm/upstash/kafka-"
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
  name_prefix             = "pfm/upstash/redis-"
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

# =============================================================================
# Compute: Amazon ECS Fargate Spot & Cloud Map Pilot (ADR-008)
# =============================================================================
module "ecs_pilot" {
  source             = "../../modules/aws-ecs-pilot"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
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

# =============================================================================
# Shared Outputs (Consumed via terraform_remote_state by *-infra repositories)
# =============================================================================

output "vpc_id" {
  description = "Shared VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Shared public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Shared private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "kms_key_arn" {
  description = "Shared KMS Master Key ARN"
  value       = module.security_kms.kms_master_key_arn
}

output "kms_master_key_arn" {
  description = "Shared KMS Master Key ARN"
  value       = module.security_kms.kms_master_key_arn
}

output "kms_master_key_id" {
  description = "Shared KMS Master Key ID"
  value       = module.security_kms.kms_master_key_id
}

output "rds_endpoint" {
  description = "Shared PostgreSQL 16 RDS endpoint (pfm_core_ledger + pfm_ai_rules)"
  value       = module.database_per_service.rds_endpoint
}

output "rds_resource_id" {
  description = "Shared PostgreSQL 16 RDS resource ID for IAM DB authentication"
  value       = module.database_per_service.rds_resource_id
}

output "redis_endpoint" {
  description = "ElastiCache Valkey primary endpoint"
  value       = module.database_per_service.redis_endpoint
}

# ECS Pilot Outputs (ADR-008)
output "ecs_cluster_id" {
  description = "ECS Cluster ID (Pilot)"
  value       = module.ecs_pilot.ecs_cluster_id
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name (Pilot)"
  value       = module.ecs_pilot.ecs_cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN (Pilot)"
  value       = module.ecs_pilot.ecs_cluster_arn
}

output "ecs_tasks_security_group_id" {
  description = "Security Group ID for ECS tasks"
  value       = module.ecs_pilot.ecs_tasks_security_group_id
}

output "service_discovery_namespace_id" {
  description = "Cloud Map / Service Connect Namespace ID"
  value       = module.ecs_pilot.cloud_map_namespace_id
}

output "cloud_map_namespace_id" {
  description = "Cloud Map / Service Connect Namespace ID"
  value       = module.ecs_pilot.cloud_map_namespace_id
}

output "cloud_map_namespace_arn" {
  description = "Cloud Map / Service Connect Namespace ARN"
  value       = module.ecs_pilot.cloud_map_namespace_arn
}

output "cloud_map_namespace_name" {
  description = "Cloud Map / Service Connect Namespace Name"
  value       = module.ecs_pilot.cloud_map_namespace_name
}

output "s3_statements_bucket" {
  description = "Encrypted S3 bucket for statement PDFs"
  value       = aws_s3_bucket.statements.id
}

output "s3_statements_bucket_id" {
  description = "Encrypted S3 bucket for statement PDFs"
  value       = aws_s3_bucket.statements.id
}

output "s3_statements_bucket_arn" {
  description = "Encrypted S3 bucket ARN for statement PDFs"
  value       = aws_s3_bucket.statements.arn
}

output "secrets_arn" {
  description = "Secrets Manager ARNs for Upstash Kafka and Redis"
  value = {
    upstash_kafka = aws_secretsmanager_secret.upstash_kafka.arn
    upstash_redis = aws_secretsmanager_secret.upstash_redis.arn
  }
}

output "upstash_kafka_secret_arn" {
  description = "Secrets Manager ARN for Upstash Kafka Serverless"
  value       = aws_secretsmanager_secret.upstash_kafka.arn
}

output "upstash_redis_secret_arn" {
  description = "Secrets Manager ARN for Upstash Redis Serverless"
  value       = aws_secretsmanager_secret.upstash_redis.arn
}
