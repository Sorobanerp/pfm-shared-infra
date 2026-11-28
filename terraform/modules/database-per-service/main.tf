locals {
  database_contract = {
    service_domain = var.service_domain
    engine         = "postgresql-${var.engine_version}-pgvector"
    rls_enforced   = true
    kms_key_alias  = var.kms_key_alias
  }
}
