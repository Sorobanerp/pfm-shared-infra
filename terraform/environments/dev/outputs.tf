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

output "alb_dns_name" {
  description = "Public ALB DNS Name (HTTP 80 -> 301 HTTPS 443)"
  value       = module.ecs_pilot.alb_dns_name
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
  sensitive   = true
  value = {
    upstash_kafka = aws_secretsmanager_secret.upstash_kafka.arn
    upstash_redis = aws_secretsmanager_secret.upstash_redis.arn
  }
}

output "upstash_kafka_secret_arn" {
  description = "Secrets Manager ARN for Upstash Kafka Serverless"
  sensitive   = true
  value       = aws_secretsmanager_secret.upstash_kafka.arn
}

output "upstash_redis_secret_arn" {
  description = "Secrets Manager ARN for Upstash Redis Serverless"
  sensitive   = true
  value       = aws_secretsmanager_secret.upstash_redis.arn
}

output "datadog_api_key_secret_arn" {
  description = "Secrets Manager ARN for Datadog API Key (Plug-and-Play ADR-010)"
  sensitive   = true
  value       = aws_secretsmanager_secret.datadog_api_key.arn
}
