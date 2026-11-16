# =============================================================================
# PFM Shared Infrastructure — OpenTofu / Terraform Module: Shared Network & VPC
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the PFM Cloud Network"
  type        = string
  default     = "10.42.0.0/16"
}

output "network_blueprint" {
  description = "Canonical network topology exported to 1:1 microservice -infra repositories via remote state"
  value = {
    environment = var.environment
    vpc_cidr    = var.vpc_cidr
    tiers       = ["edge-public", "k8s-compute-private", "data-isolated-rls"]
  }
}
