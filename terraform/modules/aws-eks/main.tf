terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
  default     = "pfm-eks-prod"
}

variable "kubernetes_version" {
  description = "Kubernetes control plane version"
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS control plane and worker nodes"
  type        = list(string)
}

variable "kms_master_key_arn" {
  description = "KMS Master Key ARN for EKS secrets encryption and EBS/logs encryption"
  type        = string
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Project     = "pfm-platform"
  }
}

# =============================================================================
# 1. EKS Control Plane IAM Role & CloudWatch Logs
# =============================================================================

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
  kms_key_id        = var.kms_master_key_arn
  tags              = local.common_tags
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    provider {
      key_arn = var.kms_master_key_arn
    }
    resources = ["secrets"]
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster
  ]
}

# =============================================================================
# 2. EKS Managed Node Group (Arm Graviton t4g.medium, IMDSv2 + KMS EBS)
# =============================================================================

data "aws_iam_policy_document" "eks_nodes_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.cluster_name}-graviton-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_master_key_arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-graviton-node"
    })
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-graviton-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = "AL2023_ARM_64_STANDARD"
  instance_types  = ["t4g.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly
  ]
}

# =============================================================================
# 3. OIDC Provider for IRSA (Least-Privilege ServiceAccounts)
# =============================================================================

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = local.common_tags
}

output "eks_cluster_name" {
  description = "Provisioned EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Provisioned EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_data" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "IAM OIDC Provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  description = "EKS OIDC Issuer URL without https://"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
