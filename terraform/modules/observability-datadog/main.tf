terraform {
  required_version = ">= 1.8.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.45"
    }
  }
}

variable "datadog_site" {
  type        = string
  default     = "us3.datadoghq.com"
  description = "Datadog intake site"
}

variable "api_key_existing_secret" {
  type        = string
  default     = "datadog-secret"
  description = "Kubernetes secret containing the Datadog API key"
}

variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Kubernetes namespace for observability agents"
}

variable "enable_helm_agent" {
  type        = bool
  default     = false
  description = "Enable Datadog Helm Agent inside EKS"
}

resource "helm_release" "datadog_agent" {
  count            = var.enable_helm_agent ? 1 : 0
  name             = "datadog-agent"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  version          = "3.74.0"
  namespace        = var.namespace
  create_namespace = true
  wait             = false

  set {
    name  = "datadog.site"
    value = var.datadog_site
  }

  set {
    name  = "datadog.apiKeyExistingSecret"
    value = var.api_key_existing_secret
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.http.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }
}

output "otlp_http_endpoint" {
  value = "http://datadog-agent.${var.namespace}.svc.cluster.local:4318"
}

output "otlp_grpc_endpoint" {
  value = "http://datadog-agent.${var.namespace}.svc.cluster.local:4317"
}
