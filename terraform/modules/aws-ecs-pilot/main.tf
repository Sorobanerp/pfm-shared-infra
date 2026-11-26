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

resource "aws_security_group" "alb" {
  name        = "pfm-alb-public-sg-${var.environment}"
  description = "Public ALB Security Group exposing only TCP 80 (HTTP->HTTPS 301 redirect) and TCP 443"
  vpc_id      = var.vpc_id

  # trivy:ignore:AVD-AWS-0107 Public internet-facing ALB requires 80 (strictly for 301 redirect to 443) and 443
  ingress {
    description = "Allow HTTP 80 exclusively for 301 redirect to HTTPS 443"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # trivy:ignore:AVD-AWS-0107 Public internet-facing ALB HTTPS entrypoint
  ingress {
    description = "Allow HTTPS 443 from internet clients"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward North-South traffic to ECS Fargate tasks inside VPC"
    from_port   = 3000
    to_port     = 18080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "pfm-alb-public-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "pfm-ecs-tasks-sg-${var.environment}"
  description = "Security Group for ECS Fargate Spot tasks (ingress strictly from ALB SG and self Service Connect)"
  vpc_id      = var.vpc_id

  # Ingress: North-South traffic exclusively from the Public ALB Security Group (zero 0.0.0.0/0)
  ingress {
    description     = "Allow North-South HTTP from Public ALB to Web Next.js (3000) and Ingestion BFF (18080)"
    from_port       = 3000
    to_port         = 18080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Ingress: East-West traffic exclusively between ECS tasks in this Security Group (Cloud Map Service Connect)
  ingress {
    description = "Allow East-West HTTP/gRPC traffic exclusively between ECS tasks (Service Connect)"
    from_port   = 18080
    to_port     = 18200
    protocol    = "tcp"
    self        = true
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

  # Egress: Valkey/Redis within VPC
  egress {
    description = "Allow Valkey connection within VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress: East-West microservices within ECS tasks Security Group
  egress {
    description = "Allow east-west traffic between microservices within ECS tasks SG"
    from_port   = 18080
    to_port     = 18200
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name        = "pfm-ecs-tasks-sg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

# =============================================================================
# Domain 4 & 7: Public ALB (80->301->443) + S3 Access Logs with Lifecycle
# =============================================================================
resource "aws_s3_bucket" "alb_access_logs" {
  bucket = "pfm-alb-access-logs-${var.environment}"

  tags = {
    Name        = "pfm-alb-access-logs-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

# trivy:ignore:AVD-AWS-0132 ALB access logs require AES256 or KMS; uses KMS when kms_master_key_arn is provided
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_master_key_arn != "" ? var.kms_master_key_arn : null
      sse_algorithm     = var.kms_master_key_arn != "" ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    id     = "expire-alb-access-logs-30d"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

# trivy:ignore:AVD-AWS-0053 Intentional public internet-facing ALB entrypoint (exposing only TCP 80->301->443 and TCP 443)
resource "aws_lb" "public" {
  count                      = length(var.public_subnet_ids) > 0 ? 1 : 0
  name                       = "pfm-public-alb-${var.environment}"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_access_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name        = "pfm-public-alb-${var.environment}"
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

resource "aws_lb_listener" "http_80_redirect" {
  count             = length(var.public_subnet_ids) > 0 ? 1 : 0
  load_balancer_arn = aws_lb.public[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
