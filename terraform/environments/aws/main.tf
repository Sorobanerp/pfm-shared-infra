# =============================================================================
# AWS Well-Architected Shared Landing Zone (sa-east-1 Primary / us-east-2 DR)
# Emulated locally via LocalStack on http://localhost:4566
# =============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

module "network" {
  source      = "../../modules/network"
  environment = "aws-prod"
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

module "observability_datadog" {
  source                  = "../../modules/observability-datadog"
  namespace               = "monitoring"
  datadog_site            = "us3.datadoghq.com"
  api_key_existing_secret = "datadog-secret"
}
