# =============================================================================
# Amazon ECS Fargate Spot & Cloud Map Service Connect Module (ADR-008 Pilot)
# Fixed cost: ~US$ 0,00 idle cluster + ~US$ 11,50–24,00/mo Fargate Spot tasks
# Eliminates US$ 73/mo EKS Control Plane while maintaining Graviton Arm64
# =============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

resource "aws_service_discovery_private_dns_namespace" "pfm_internal" {
  name        = "pfm.internal"
  description = "Private DNS and Service Connect namespace for microservices gRPC & HTTP discovery"
  vpc         = var.vpc_id

  tags = {
    Name        = "pfm-cloudmap-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Project     = "PFM-Core-Banking"
  }
}

resource "aws_ecs_cluster" "pfm_pilot" {
  name = "pfm-ecs-pilot"

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.pfm_internal.arn
  }

  setting {
    name  = "containerInsights"
    value = "disabled" # FinOps: keep disabled to save CloudWatch custom metric fees in 3-month pilot
  }

  tags = {
    Name         = "pfm-ecs-pilot"
    Environment  = var.environment
    ManagedBy    = "OpenTofu"
    FinOpsTier   = "Pilot-3-Months"
    Architecture = "ECS-Fargate-Spot-Arm64"
  }
}

resource "aws_ecs_cluster_capacity_providers" "pfm_pilot" {
  cluster_name = aws_ecs_cluster.pfm_pilot.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 100
    base              = 0
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "pfm-ecs-tasks-sg-${var.environment}"
  description = "Security Group for ECS Fargate Spot tasks (least-privilege east-west and egress)"
  vpc_id      = var.vpc_id

  # Ingress: Allow internal microservices traffic within VPC
  ingress {
    description = "Allow internal HTTP and gRPC traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress: HTTPS for AWS APIs (ECR, S3, KMS, Secrets Manager) and Upstash Serverless
  # trivy:ignore:AVD-AWS-0104 HTTPS egress to AWS APIs and Upstash Serverless endpoints
  egress {
    description = "Allow HTTPS to AWS APIs and Upstash Serverless"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: RDS PostgreSQL within VPC
  egress {
    description = "Allow PostgreSQL connection to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress: East-West microservices within VPC
  egress {
    description = "Allow east-west traffic between microservices within VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "pfm-ecs-tasks-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}
