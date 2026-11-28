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
  name_prefix = "pfm-core-ledger-rds-sg-${var.environment}-"
  description = "Restrict PostgreSQL 5432 access exclusively to ECS Tasks Security Group"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "pfm-core-ledger-rds-sg-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_core_ledger_from_ecs" {
  count                        = var.ecs_tasks_security_group_id != "" ? 1 : 0
  security_group_id            = aws_security_group.rds_core_ledger.id
  description                  = "PostgreSQL 5432 access exclusively from ECS Fargate Tasks Security Group"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ecs_tasks_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "rds_core_ledger_to_ecs" {
  count                        = var.ecs_tasks_security_group_id != "" ? 1 : 0
  security_group_id            = aws_security_group.rds_core_ledger.id
  description                  = "Allow responses exclusively to ECS Fargate Tasks Security Group"
  ip_protocol                  = "-1"
  referenced_security_group_id = var.ecs_tasks_security_group_id
}

resource "aws_db_instance" "core_ledger" {
  identifier                            = "pfm-core-ledger-${var.environment}"
  engine                                = "postgres"
  engine_version                        = "16.15"
  instance_class                        = var.db_instance_class
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

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "pfm-cache-sg-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_ecs" {
  count                        = var.ecs_tasks_security_group_id != "" ? 1 : 0
  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey/Redis 6379 access exclusively from ECS Fargate Tasks Security Group"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ecs_tasks_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "cache_to_ecs" {
  count                        = var.ecs_tasks_security_group_id != "" ? 1 : 0
  security_group_id            = aws_security_group.cache.id
  description                  = "Allow responses exclusively to ECS Fargate Tasks Security Group"
  ip_protocol                  = "-1"
  referenced_security_group_id = var.ecs_tasks_security_group_id
}

resource "aws_elasticache_replication_group" "cache" {
  replication_group_id       = "pfm-forecast-valkey-${var.environment}"
  description                = "PFM Forecast Engine & BFF Valkey Cache (FinOps single-node)"
  engine                     = "valkey"
  engine_version             = "8.0"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  parameter_group_name       = "default.valkey8"
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
