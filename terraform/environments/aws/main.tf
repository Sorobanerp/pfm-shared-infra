# =============================================================================
# AWS Well-Architected Shared Landing Zone (us-east-2 Ohio) — FinOps MVP Profile
# Target: ~US$ 41/mo (No NAT GW, 1..3 Graviton SPOT, 1 Shared RDS + 1 Valkey,
# 0 MSK [Upstash Serverless], 1 Shared ALB, Full Autoscale: CA + Metrics + KEDA)
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

variable "enable_nat_gateway" {
  description = "Keep false in FinOps MVP to save ~US$ 32/mo; set true when scaling to private-subnet NAT"
  type        = bool
  default     = false
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
  enable_nat_gateway = var.enable_nat_gateway
}

module "security_kms" {
  source      = "../../modules/aws-security-kms"
  environment = var.environment
  alias_name  = "alias/pfm-master-key"
}

# Single Shared RDS PostgreSQL 16 (hosts logical DBs/schemas: pfm_core_ledger + pfm_ai_rules with RLS)
# + Single Valkey cache.t4g.micro (0 AWS MSK clusters; Kafka via Upstash Serverless Secret)
module "database_per_service" {
  source             = "../../modules/aws-database-per-service"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  kms_master_key_arn = module.security_kms.kms_master_key_arn
}

module "eks" {
  source                   = "../../modules/aws-eks"
  environment              = var.environment
  cluster_name             = "pfm-eks-${var.environment}"
  kubernetes_version       = "1.34"
  vpc_id                   = module.network.vpc_id
  vpc_cidr                 = module.network.vpc_cidr
  control_plane_subnet_ids = module.network.private_subnet_ids
  node_subnet_ids          = module.network.eks_node_subnet_ids
  kms_master_key_arn       = module.security_kms.kms_master_key_arn
  node_instance_types      = ["t4g.small", "t4g.medium"]
  node_capacity_type       = "SPOT"
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

module "eks_addons" {
  source                      = "../../modules/aws-eks-addons"
  cluster_name                = module.eks.eks_cluster_name
  aws_region                  = var.aws_region
  vpc_id                      = module.network.vpc_id
  cluster_autoscaler_role_arn = module.eks.cluster_autoscaler_role_arn
  alb_controller_role_arn     = module.eks.alb_controller_role_arn

  depends_on = [module.eks]
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
  description = "Shared PostgreSQL 16 RDS endpoint (pfm_core_ledger + pfm_ai_rules)"
  value       = module.database_per_service.rds_endpoint
}

output "rds_resource_id" {
  description = "Shared PostgreSQL 16 RDS resource ID for IAM DB authentication"
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

output "shared_ingress_name" {
  description = "Single shared ALB Ingress name"
  value       = module.eks_addons.shared_ingress_name
}
