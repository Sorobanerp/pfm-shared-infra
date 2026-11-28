locals {
  messaging_backbone = {
    kafka_version  = var.kafka_version
    valkey_version = var.valkey_version
    partition_key  = "tenant_id"
  }
}
