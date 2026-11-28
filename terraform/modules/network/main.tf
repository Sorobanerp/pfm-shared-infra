locals {
  network_blueprint = {
    environment = var.environment
    vpc_cidr    = var.vpc_cidr
    tiers       = ["edge-public", "k8s-compute-private", "data-isolated-rls"]
  }
}
