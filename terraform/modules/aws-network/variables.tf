variable "environment" {
  description = "Deployment environment identifier (dev or prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones in us-east-2 (Ohio)"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "cluster_name" {
  description = "Cluster name for subnet discovery tags"
  type        = string
  default     = "pfm-ecs-pilot"
}

variable "enable_nat_gateway" {
  description = "FinOps switch: false avoids ~US$ 32/mo NAT Gateway cost; set true for private-subnet NAT scale-out"
  type        = bool
  default     = false
}
