terraform {
  required_version = ">= 1.8.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS Region (Ohio)"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID for AWS Load Balancer Controller"
  type        = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA Role ARN for Cluster Autoscaler"
  type        = string
}

variable "alb_controller_role_arn" {
  description = "IRSA Role ARN for AWS Load Balancer Controller"
  type        = string
}

variable "api_host" {
  description = "Public API hostname routed to pfm-ingestion-bff-go via shared ALB"
  type        = string
  default     = "api.pfm.sorobanerp.com"
}

variable "app_host" {
  description = "Public Web App hostname routed to pfm-web-nextjs via shared ALB"
  type        = string
  default     = "app.pfm.sorobanerp.com"
}

# =============================================================================
# 1. Metrics Server (Enables HPA CPU/Memory scaling across all microservices)
# =============================================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP"
  }
}

# =============================================================================
# 2. Cluster Autoscaler (Horizontal node scaling: min 1 -> max 3 Graviton nodes)
# =============================================================================

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.43.2"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.cluster_autoscaler_role_arn
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }
}

# =============================================================================
# 3. KEDA (Event-driven Scale-to-Zero for pfm-ai-worker-python on Kafka lag)
# =============================================================================

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.15.2"
  namespace        = "keda"
  create_namespace = true
}

# =============================================================================
# 4. AWS Load Balancer Controller (Single Shared ALB for api.* and app.*)
# =============================================================================

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.10.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_controller_role_arn
  }
}

resource "kubernetes_namespace_v1" "pfm_platform" {
  metadata {
    name = "pfm-platform"
  }
}

resource "kubernetes_ingress_v1" "pfm_shared_edge" {
  metadata {
    name      = "pfm-shared-edge-ingress"
    namespace = kubernetes_namespace_v1.pfm_platform.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/group.name"       = "pfm-shared-edge"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/health"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.api_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "pfm-ingestion-bff-go"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }

    rule {
      host = var.app_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "pfm-web-nextjs"
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

output "shared_ingress_name" {
  description = "Single shared ALB Ingress resource name"
  value       = kubernetes_ingress_v1.pfm_shared_edge.metadata[0].name
}
