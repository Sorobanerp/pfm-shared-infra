#!/usr/bin/env bash
set -euo pipefail

echo "=================================================================="
echo " [PFM LocalStack Init] Provisioning AWS S3, KMS & SecretsManager"
echo "=================================================================="

REGION="sa-east-1"

# 1. Create Symmetric KMS Master Key for Tenant Envelope Encryption (ADR-006)
echo "-> Creating KMS Symmetric Master Key (alias/pfm-tenant-master-key)..."
EXISTING_KEY_ID=$(awslocal kms list-aliases --region "${REGION}" \
  --query "Aliases[?AliasName=='alias/pfm-tenant-master-key'].TargetKeyId | [0]" \
  --output text 2>/dev/null || true)

if [ -z "${EXISTING_KEY_ID}" ] || [ "${EXISTING_KEY_ID}" = "None" ]; then
  KEY_ID=$(awslocal kms create-key \
    --region "${REGION}" \
    --description "PFM Core Banking Multitenant Envelope Encryption Master Key (KEK)" \
    --key-usage ENCRYPT_DECRYPT \
    --key-spec SYMMETRIC_DEFAULT \
    --tags TagKey=Platform,TagValue=PFM-Core-Banking TagKey=Compliance,TagValue=LGPD-BACEN \
    --query "KeyMetadata.KeyId" \
    --output text)
  awslocal kms create-alias \
    --region "${REGION}" \
    --alias-name "alias/pfm-tenant-master-key" \
    --target-key-id "${KEY_ID}"
  echo "   Created KMS Key ID: ${KEY_ID} (alias/pfm-tenant-master-key)"
else
  KEY_ID="${EXISTING_KEY_ID}"
  echo "   KMS Alias alias/pfm-tenant-master-key already exists -> Key ID: ${KEY_ID}"
fi

# 2. Create S3 Buckets with Server-Side KMS Encryption
for BUCKET in "pfm-statements-encrypted-local" "pfm-receipts-images-local"; do
  echo "-> Ensuring S3 Bucket: s3://${BUCKET} ..."
  if ! awslocal s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
    awslocal s3 mb "s3://${BUCKET}" --region "${REGION}"
  fi
  awslocal s3api put-bucket-encryption \
    --bucket "${BUCKET}" \
    --server-side-encryption-configuration "{
      \"Rules\": [{
        \"ApplyServerSideEncryptionByDefault\": {
          \"SSEAlgorithm\": \"aws:kms\",
          \"KMSMasterKeyID\": \"alias/pfm-tenant-master-key\"
        },
        \"BucketKeyEnabled\": true
      }]
    }"
done

# 3. Create Secrets Manager Secret (pfm/dev/gemini-api-key)
SECRET_NAME="pfm/dev/gemini-api-key"
echo "-> Ensuring Secrets Manager secret: ${SECRET_NAME} ..."
if ! awslocal secretsmanager describe-secret --region "${REGION}" --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
  awslocal secretsmanager create-secret \
    --region "${REGION}" \
    --name "${SECRET_NAME}" \
    --description "API Key for Tier-3 Cloud LLM Fallback (Gemini API)" \
    --kms-key-id "alias/pfm-tenant-master-key" \
    --secret-string '{"provider":"google-gemini","model":"gemini-2.5-flash","apiKey":"local-dev-mock-gemini-key-000000"}'
else
  awslocal secretsmanager put-secret-value \
    --region "${REGION}" \
    --secret-id "${SECRET_NAME}" \
    --secret-string '{"provider":"google-gemini","model":"gemini-2.5-flash","apiKey":"local-dev-mock-gemini-key-000000"}'
fi

echo "=================================================================="
echo " [PFM LocalStack Init] Completed Successfully!"
echo "=================================================================="
