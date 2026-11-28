variable "environment" {
  description = "Target environment name (dev or prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "ECS Fargate Spot Cluster Name"
  type        = string
  default     = "pfm-ecs-pilot"
}

variable "vpc_id" {
  description = "VPC ID where ECS cluster and Cloud Map operate"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal security group rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for public ALB"
  type        = list(string)
  default     = []
}

variable "kms_master_key_arn" {
  description = "KMS Master Key ARN for encrypting ALB access logs bucket"
  type        = string
  default     = ""
}

variable "enable_cloudwatch_logs" {
  description = "Disable AWS CloudWatch Logs by default (FinOps ADR-010 Zero-CloudWatch)"
  type        = bool
  default     = false
}

variable "desired_count" {
  description = "Scale-to-Zero Bootstrap desired task count (0 during infra bootstrap)"
  type        = number
  default     = 0
}

variable "min_capacity" {
  description = "Scale-to-Zero Bootstrap minimum autoscaling capacity (0 during infra bootstrap)"
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Scale-to-Zero Bootstrap maximum autoscaling capacity (0 during infra bootstrap)"
  type        = number
  default     = 0
}
