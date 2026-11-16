# =============================================================================
# PFM Shared Infrastructure — OpenTofu / Terraform Module: Event Backbone (Kafka + Valkey)
# =============================================================================

variable "kafka_version" {
  type    = string
  default = "3.8.0"
}

variable "valkey_version" {
  type    = string
  default = "8.0"
}

output "messaging_backbone" {
  value = {
    kafka_version  = var.kafka_version
    valkey_version = var.valkey_version
    partition_key  = "tenant_id"
  }
}
