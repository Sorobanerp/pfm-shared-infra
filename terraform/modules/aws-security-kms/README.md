# Module `aws-security-kms`

Provisiona a Customer Managed Key (CMK) no AWS KMS com rotação automática (`alias/pfm-master-key`), bucket S3 e trilha de auditoria AWS CloudTrail (Zero-CloudWatch `ADR-010`) e políticas de guardrails OIDC GitHub Actions (`develop` e `main`) e S3 State Lock.

## Inputs

| Name | Description | Type | Default |
| :--- | :--- | :---: | :---: |
| `environment` | Deployment environment identifier (`dev` or `prod`) | `string` | `"prod"` |
| `alias_name` | KMS key alias name | `string` | `"alias/pfm-master-key"` |
| `enable_cloudtrail_trail` | Enable AWS CloudTrail resource creation | `bool` | `false` |

## Outputs

| Name | Description | Sensitive |
| :--- | :--- | :---: |
| `kms_master_key_arn` | ARN of the PFM master KMS key | `false` |
| `kms_master_key_id` | ID of the PFM master KMS key | `false` |
| `cloudtrail_arn` | ARN of the PFM governance AWS CloudTrail | `false` |
| `github_actions_oidc_trust_policy_json` | GitHub Actions OIDC trust policy JSON | `false` |
| `tfstate_bucket_guardrail_policy_json` | Bucket policy JSON for OpenTofu state bucket | `false` |
