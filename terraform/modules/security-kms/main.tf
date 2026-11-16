# =============================================================================
# PFM Shared Infrastructure — OpenTofu / Terraform Module: KMS & Secrets Manager
# =============================================================================

variable "tenant_master_key_alias" {
  type    = string
  default = "alias/pfm-tenant-master-key"
}

output "kms_alias" {
  value = var.tenant_master_key_alias
}
