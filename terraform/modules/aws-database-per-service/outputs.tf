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
