variable "environment" {
  description = "Target environment name (e.g. prod, pilot)"
  type        = string
  default     = "prod"
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
