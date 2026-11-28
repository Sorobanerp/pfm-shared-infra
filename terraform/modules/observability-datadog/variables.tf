variable "datadog_site" {
  description = "Datadog intake site (e.g. us3.datadoghq.com)"
  type        = string
  default     = "us3.datadoghq.com"
}

variable "api_key_existing_secret" {
  description = "Kubernetes secret containing the Datadog API key"
  type        = string
  default     = "datadog-secret"
}

variable "namespace" {
  description = "Kubernetes namespace for observability agents"
  type        = string
  default     = "monitoring"
}

variable "enable_helm_agent" {
  description = "Enable Datadog Helm Agent inside EKS"
  type        = bool
  default     = false
}

variable "enable_datadog_monitors" {
  description = "Enable Datadog Dashboard and Critical Monitors provisioning via IaC"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Target deployment environment (dev or prod)"
  type        = string
  default     = "prod"
}
