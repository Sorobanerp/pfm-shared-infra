# =============================================================================
# AWS Well-Architected Shared Landing Zone (us-east-2 Ohio)
# Real AWS Infrastructure: VPC, KMS, RDS PostgreSQL 16, ElastiCache Valkey,
# EKS 1.31 (Graviton t4g.medium) + OIDC IRSA + Datadog Agent Helm Release
# =============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "aws_region" {
  description = "Primary AWS Region (Ohio)"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Target environment name"
  type        = string
  default     = "prod"
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source             = "../../modules/aws-network"
  environment        = var.environment
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-2a", "us-east-2b"]
  cluster_name       = "pfm-eks-${var.environment}"
}

module "security_kms" {
  source      = "../../modules/aws-security-kms"
  environment = var.environment
  alias_name  = "alias/pfm-master-key"
}

module "database_per_service" {
  source             = "../../modules/aws-database-per-service"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  kms_master_key_arn = module.security_kms.kms_master_key_arn
}

module "eks" {
  source             = "../../modules/aws-eks"
  environment        = var.environment
  cluster_name       = "pfm-eks-${var.environment}"
  kubernetes_version = "1.31"
  private_subnet_ids = module.network.private_subnet_ids
  kms_master_key_arn = module.security_kms.kms_master_key_arn
}

module "event_backbone" {
  source = "../../modules/event-backbone"
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.eks_cluster_name
}

provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca_data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

module "observability_datadog" {
  source                  = "../../modules/observability-datadog"
  namespace               = "monitoring"
  datadog_site            = "us3.datadoghq.com"
  api_key_existing_secret = "datadog-secret"

  depends_on = [module.eks]
}

# =============================================================================
# Shared Outputs (Consumed via terraform_remote_state by *-infra repositories)
# =============================================================================

output "vpc_id" {
  description = "Shared VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Shared public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Shared private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "kms_master_key_arn" {
  description = "Shared KMS Master Key ARN"
  value       = module.security_kms.kms_master_key_arn
}

output "kms_master_key_id" {
  description = "Shared KMS Master Key ID"
  value       = module.security_kms.kms_master_key_id
}

output "rds_endpoint" {
  description = "PostgreSQL 16 RDS endpoint for pfm_core_ledger"
  value       = module.database_per_service.rds_endpoint
}

output "rds_resource_id" {
  description = "PostgreSQL 16 RDS resource ID for IAM DB authentication"
  value       = module.database_per_service.rds_resource_id
}

output "redis_endpoint" {
  description = "ElastiCache Valkey primary endpoint"
  value       = module.database_per_service.redis_endpoint
}

output "eks_cluster_name" {
  description = "EKS Cluster name"
  value       = module.eks.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = module.eks.eks_cluster_endpoint
}

output "oidc_provider_arn" {
  description = "EKS IAM OIDC Provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_issuer_url" {
  description = "EKS IAM OIDC Issuer URL without https://"
  value       = module.eks.oidc_issuer_url
}
