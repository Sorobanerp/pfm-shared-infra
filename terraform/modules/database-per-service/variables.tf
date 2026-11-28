variable "service_domain" {
  description = "Bounded context owner (e.g., core-ledger, ai-rules)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "kms_key_alias" {
  description = "KMS Master Key alias for storage and envelope encryption"
  type        = string
  default     = "alias/pfm-tenant-master-key"
}
