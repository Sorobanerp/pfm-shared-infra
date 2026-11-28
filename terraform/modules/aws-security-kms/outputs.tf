output "kms_master_key_arn" {
  description = "ARN of the PFM master KMS key"
  value       = aws_kms_key.master.arn
}

output "kms_master_key_id" {
  description = "ID of the PFM master KMS key"
  value       = aws_kms_key.master.key_id
}

output "cloudtrail_arn" {
  description = "ARN of the PFM governance AWS CloudTrail"
  value       = try(aws_cloudtrail.pfm_governance[0].arn, "")
}

output "github_actions_oidc_trust_policy_json" {
  description = "Least-privilege GitHub Actions OIDC trust policy JSON (Sorobanerp/pfm-* on refs/heads/develop and refs/heads/main)"
  value       = data.aws_iam_policy_document.github_actions_oidc_trust.json
}

output "tfstate_bucket_guardrail_policy_json" {
  description = "Bucket policy JSON denying DeleteBucket/DeleteObject on OpenTofu state bucket"
  value       = data.aws_iam_policy_document.tfstate_bucket_guardrail.json
}
