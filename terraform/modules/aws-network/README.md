# Module `aws-network`

Provisiona a VPC Multi-AZ (`us-east-2a`, `us-east-2b`), subnets públicas e privadas, Internet Gateway, Route Tables e NAT Gateway condicional (`enable_nat_gateway = false` por padrão).

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :---: | :---: |
| `environment` | Deployment environment identifier (`dev` or `prod`) | `string` | `"prod"` |
| `vpc_cidr` | Primary VPC CIDR block | `string` | `"10.20.0.0/16"` |
| `availability_zones` | Availability zones in `us-east-2` | `list(string)` | `["us-east-2a", "us-east-2b"]` |
| `cluster_name` | Cluster name for subnet discovery tags | `string` | `"pfm-ecs-pilot"` |
| `enable_nat_gateway` | Enable NAT Gateway (`false` saves ~US$ 32/mo) | `bool` | `false` |

## Outputs

| Name | Description | Sensitive |
| :--- | :--- | :---: |
| `vpc_id` | Provisioned AWS VPC ID | `false` |
| `vpc_cidr` | Provisioned AWS VPC CIDR block | `false` |
| `public_subnet_ids` | List of public subnet IDs | `false` |
| `private_subnet_ids` | List of private subnet IDs | `false` |
