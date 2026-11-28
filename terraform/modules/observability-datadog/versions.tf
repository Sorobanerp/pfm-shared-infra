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
