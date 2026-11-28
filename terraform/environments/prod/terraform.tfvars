# =============================================================================
# PFM Shared Infra — Environment: prod
# ADR-009: Scale-to-Zero Bootstrap (desired=0, min=0, max=0) & Naming Isolation (-prod)
# =============================================================================
environment             = "prod"
aws_region              = "us-east-2"
cluster_name            = "pfm-ecs-pilot-prod"
enable_nat_gateway      = false
enable_cloudwatch_logs  = false
enable_datadog_monitors = false

# Scale-to-Zero Bootstrap (FEAT-01B):
# Target post-ECR image push (FEAT-02/FEAT-03): desired=1, min=1, max=3
desired_count = 0
min_capacity  = 0
max_capacity  = 0
