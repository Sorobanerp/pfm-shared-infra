variable "environment" {
  description = "Deployment environment identifier (dev or prod)"
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

variable "ecs_tasks_security_group_id" {
  description = "ECS Tasks Security Group ID allowed to connect to PostgreSQL 5432 and Valkey 6379"
  type        = string
  default     = ""
}

variable "db_instance_class" {
  description = "RDS PostgreSQL 16 instance class (FinOps Graviton2 db.t4g.micro)"
  type        = string
  default     = "db.t4g.micro"
}
