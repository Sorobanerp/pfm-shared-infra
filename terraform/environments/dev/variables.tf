variable "aws_region" {
  description = "Primary AWS Region (Ohio)"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Target environment name (dev or prod)"
  type        = string
}

variable "cluster_name" {
  description = "ECS Fargate Spot Cluster Name"
  type        = string
  default     = "pfm-ecs-pilot"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  type        = string
  default     = "10.20.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Keep false in FinOps MVP to save ~US$ 32/mo; set true when scaling to private-subnet NAT"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Disable AWS CloudWatch Logs by default (FinOps ADR-010 Zero-CloudWatch)"
  type        = bool
  default     = false
}

variable "desired_count" {
  description = "Scale-to-Zero Bootstrap desired ECS task count (0 during bootstrap)"
  type        = number
  default     = 0
}

variable "min_capacity" {
  description = "Scale-to-Zero Bootstrap minimum autoscaling capacity (0 during bootstrap)"
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Scale-to-Zero Bootstrap maximum autoscaling capacity (0 during bootstrap)"
  type        = number
  default     = 0
}

variable "enable_datadog_monitors" {
  description = "Enable Datadog Unified Dashboard and Critical Security/SLO Monitors (ADR-010)"
  type        = bool
  default     = false
}

variable "datadog_api_key" {
  description = "Datadog API Key for monitor provisioning"
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application Key for monitor provisioning"
  type        = string
  default     = ""
  sensitive   = true
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
