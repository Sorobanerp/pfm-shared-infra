variable "environment" {
  description = "Deployment environment identifier (dev or prod)"
  type        = string
  default     = "prod"
}

variable "alias_name" {
  description = "KMS key alias name"
  type        = string
  default     = "alias/pfm-master-key"
}

variable "enable_cloudtrail_trail" {
  description = "Enable AWS CloudTrail resource creation (false when managed at AWS Organization/Account level)"
  type        = bool
  default     = false
}
