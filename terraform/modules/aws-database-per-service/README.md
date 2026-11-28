# Module `aws-database-per-service`

Provisiona a instância Amazon RDS PostgreSQL 16 (`db.t4g.micro`, criptografada via KMS, IAM DB Auth e RLS) e o cluster ElastiCache Valkey 8.0 (`cache.t4g.micro`, KMS + TLS) em subnets privadas com Security Groups encadeados (`create_before_destroy = true`).

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :---: | :---: |
| `environment` | Deployment environment identifier (`dev` or `prod`) | `string` | `"prod"` |
| `vpc_id` | VPC ID where database and cache security groups are created | `string` | *(required)* |
| `vpc_cidr` | VPC CIDR block | `string` | `"10.20.0.0/16"` |
| `private_subnet_ids` | Private subnet IDs for RDS and ElastiCache | `list(string)` | *(required)* |
| `kms_master_key_arn` | KMS Master Key ARN for storage encryption | `string` | *(required)* |
| `ecs_tasks_security_group_id` | ECS Tasks Security Group ID | `string` | `""` |
| `db_instance_class` | RDS PostgreSQL 16 instance class | `string` | `"db.t4g.micro"` |

## Outputs

| Name | Description | Sensitive |
| :--- | :--- | :---: |
| `rds_endpoint` | PostgreSQL RDS endpoint for `pfm_core_ledger` | `false` |
| `rds_resource_id` | PostgreSQL RDS resource ID for IAM DB authentication | `false` |
| `redis_endpoint` | ElastiCache Valkey primary endpoint | `false` |
