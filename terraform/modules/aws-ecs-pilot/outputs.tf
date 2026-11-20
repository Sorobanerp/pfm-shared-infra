output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.pfm_pilot.id
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.pfm_pilot.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.pfm_pilot.arn
}

output "cloud_map_namespace_id" {
  description = "Cloud Map / Service Connect Namespace ID"
  value       = aws_service_discovery_private_dns_namespace.pfm_internal.id
}

output "cloud_map_namespace_arn" {
  description = "Cloud Map / Service Connect Namespace ARN"
  value       = aws_service_discovery_private_dns_namespace.pfm_internal.arn
}

output "cloud_map_namespace_name" {
  description = "Cloud Map / Service Connect Namespace Name (pfm.internal)"
  value       = aws_service_discovery_private_dns_namespace.pfm_internal.name
}

output "ecs_tasks_security_group_id" {
  description = "Security Group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}
