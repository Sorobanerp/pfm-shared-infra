variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the PFM Cloud Network"
  type        = string
  default     = "10.42.0.0/16"
}
