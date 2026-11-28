output "otlp_http_endpoint" {
  description = "Internal OTLP HTTP collector endpoint"
  value       = "http://datadog-agent.${var.namespace}.svc.cluster.local:4318"
}

output "otlp_grpc_endpoint" {
  description = "Internal OTLP gRPC collector endpoint"
  value       = "http://datadog-agent.${var.namespace}.svc.cluster.local:4317"
}
