# Module `aws-ecs-pilot`

Provisiona o Cluster Amazon ECS Fargate Spot Arm64 (`pfm-ecs-pilot`), namespace AWS Cloud Map (`pfm.internal`), Application Load Balancer público (`80 -> 301 -> 443`) com S3 Access Logs e Security Groups encadeados com `create_before_destroy = true`.

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :---: | :---: |
| `environment` | Target environment name (`dev` or `prod`) | `string` | `"prod"` |
| `cluster_name` | ECS Fargate Spot Cluster Name | `string` | `"pfm-ecs-pilot"` |
| `vpc_id` | VPC ID where ECS cluster and Cloud Map operate | `string` | *(required)* |
| `vpc_cidr` | VPC CIDR block for internal security group rules | `string` | *(required)* |
| `private_subnet_ids` | List of private subnet IDs | `list(string)` | `[]` |
| `public_subnet_ids` | List of public subnet IDs | `list(string)` | `[]` |
| `kms_master_key_arn` | KMS Master Key ARN | `string` | `""` |
| `enable_cloudwatch_logs` | Disable CloudWatch Logs by default (`ADR-010`) | `bool` | `false` |
| `desired_count` | Scale-to-Zero Bootstrap desired count | `number` | `0` |
| `min_capacity` | Scale-to-Zero Bootstrap min capacity | `number` | `0` |
| `max_capacity` | Scale-to-Zero Bootstrap max capacity | `number` | `0` |

## Outputs

| Name | Description | Sensitive |
| :--- | :--- | :---: |
| `ecs_cluster_id` | ECS Cluster ID | `false` |
| `ecs_cluster_name` | ECS Cluster Name | `false` |
| `ecs_cluster_arn` | ECS Cluster ARN | `false` |
| `cloud_map_namespace_id` | Cloud Map Namespace ID | `false` |
| `cloud_map_namespace_arn` | Cloud Map Namespace ARN | `false` |
| `cloud_map_namespace_name` | Cloud Map Namespace Name (`pfm.internal`) | `false` |
| `ecs_tasks_security_group_id` | Security Group ID for ECS tasks | `false` |
| `alb_security_group_id` | Public ALB Security Group ID | `false` |
| `alb_access_logs_bucket_id` | S3 Bucket ID for ALB Access Logs | `false` |
| `alb_dns_name` | Public ALB DNS Name | `false` |
