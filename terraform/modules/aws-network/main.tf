terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones in us-east-2 (Ohio)"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "cluster_name" {
  description = "EKS cluster name for subnet discovery tags"
  type        = string
  default     = "pfm-eks-prod"
}

locals {
  public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]

  common_tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Project     = "pfm-platform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "pfm-vpc-${var.environment}"
  })
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "pfm-default-sg-restricted-${var.environment}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "pfm-igw-${var.environment}"
  })
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                        = "pfm-public-${var.availability_zones[count.index]}-${var.environment}"
    Tier                                        = "public"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                        = "pfm-private-${var.availability_zones[count.index]}-${var.environment}"
    Tier                                        = "private"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# FinOps MVP: Single NAT Gateway in the first public subnet
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "pfm-nat-eip-${var.environment}"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "pfm-nat-gw-${var.environment}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "pfm-rt-public-${var.environment}"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "pfm-rt-private-${var.environment}"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

output "vpc_id" {
  description = "Provisioned AWS VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Provisioned AWS VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs across us-east-2a and us-east-2b"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs across us-east-2a and us-east-2b"
  value       = aws_subnet.private[*].id
}
