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

variable "vpc_id" {
  description = "VPC ID where database and cache security groups are created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block allowed to reach PostgreSQL and Valkey/Redis"
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS and ElastiCache subnet groups"
  type        = list(string)
}

variable "kms_master_key_arn" {
  description = "KMS Master Key ARN for storage and encryption at rest"
  type        = string
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Project     = "pfm-platform"
  }
}

# =============================================================================
# 1. RDS PostgreSQL 16 (pfm_core_ledger) - FinOps db.t4g.micro + KMS Encrypted
# =============================================================================

resource "aws_db_subnet_group" "core_ledger" {
  name        = "pfm-core-ledger-db-subnets-${var.environment}"
  description = "Private subnets for PFM Core Ledger PostgreSQL"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "pfm-core-ledger-db-subnets-${var.environment}"
  })
}

resource "aws_security_group" "rds_core_ledger" {
  name        = "pfm-core-ledger-rds-sg-${var.environment}"
  description = "Restrict PostgreSQL 5432 access exclusively to PFM VPC CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL access from internal VPC workloads"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow internal VPC responses only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "pfm-core-ledger-rds-sg-${var.environment}"
  })
}

resource "aws_db_instance" "core_ledger" {
  identifier                            = "pfm-core-ledger-${var.environment}"
  engine                                = "postgres"
  engine_version                        = "16.4"
  instance_class                        = "db.t4g.micro"
  allocated_storage                     = 20
  max_allocated_storage                 = 50
  storage_type                          = "gp3"
  storage_encrypted                     = true
  kms_key_id                            = var.kms_master_key_arn
  db_name                               = "pfm_core_ledger"
  username                              = "pfm_ledger_admin"
  manage_master_user_password           = true
  master_user_secret_kms_key_id         = var.kms_master_key_arn
  iam_database_authentication_enabled   = true
  publicly_accessible                   = false
  db_subnet_group_name                  = aws_db_subnet_group.core_ledger.name
  vpc_security_group_ids                = [aws_security_group.rds_core_ledger.id]
  backup_retention_period               = 7
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_master_key_arn
  performance_insights_retention_period = 7
  auto_minor_version_upgrade            = true
  skip_final_snapshot                   = true

  tags = merge(local.common_tags, {
    Name    = "pfm-core-ledger-${var.environment}"
    Service = "pfm-core-ledger-java"
  })
}

# =============================================================================
# 2. ElastiCache Valkey (Single-node FinOps cache.t4g.micro + KMS + TLS)
# =============================================================================

resource "aws_elasticache_subnet_group" "cache" {
  name        = "pfm-cache-subnets-${var.environment}"
  description = "Private subnets for PFM ElastiCache Valkey"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "pfm-cache-subnets-${var.environment}"
  })
}

resource "aws_security_group" "cache" {
  name        = "pfm-cache-sg-${var.environment}"
  description = "Restrict Valkey/Redis 6379 access exclusively to PFM VPC CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "Valkey/Redis access from internal VPC workloads"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow internal VPC responses only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "pfm-cache-sg-${var.environment}"
  })
}

resource "aws_elasticache_replication_group" "cache" {
  replication_group_id       = "pfm-forecast-valkey-${var.environment}"
  description                = "PFM Forecast Engine & BFF Valkey Cache (FinOps single-node)"
  engine                     = "valkey"
  engine_version             = "7.2"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  parameter_group_name       = "default.valkey7"
  subnet_group_name          = aws_elasticache_subnet_group.cache.name
  security_group_ids         = [aws_security_group.cache.id]
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_master_key_arn
  transit_encryption_enabled = true
  automatic_failover_enabled = false

  tags = merge(local.common_tags, {
    Name    = "pfm-forecast-valkey-${var.environment}"
    Service = "pfm-forecast-engine-go"
  })
}

output "rds_endpoint" {
  description = "PostgreSQL RDS endpoint for pfm_core_ledger"
  value       = aws_db_instance.core_ledger.endpoint
}

output "rds_resource_id" {
  description = "PostgreSQL RDS resource ID for IAM DB authentication"
  value       = aws_db_instance.core_ledger.resource_id
}

output "redis_endpoint" {
  description = "ElastiCache Valkey primary endpoint"
  value       = aws_elasticache_replication_group.cache.primary_endpoint_address
}
