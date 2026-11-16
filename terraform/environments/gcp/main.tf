# =============================================================================
# GCP Well-Architected Shared Landing Zone (southamerica-east1 Primary / us-east1 DR)
# =============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

module "network" {
  source      = "../../modules/network"
  environment = "gcp-prod"
}

module "security_kms" {
  source = "../../modules/security-kms"
}

module "db_core_ledger" {
  source         = "../../modules/database-per-service"
  service_domain = "pfm-core-ledger-java"
}

module "db_ai_rules" {
  source         = "../../modules/database-per-service"
  service_domain = "pfm-ai-worker-python"
}

module "event_backbone" {
  source = "../../modules/event-backbone"
}
