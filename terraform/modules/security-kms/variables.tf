variable "tenant_master_key_alias" {
  description = "Canonical alias for the tenant envelope encryption master key"
  type        = string
  default     = "alias/pfm-tenant-master-key"
}
