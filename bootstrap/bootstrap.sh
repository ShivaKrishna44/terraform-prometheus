#!/usr/bin/env bash
# =============================================================================
# One-time bootstrap for terraform-prometheus CI/CD.
#
# Creates the prerequisites that MUST exist before GitHub Actions can run
# `terraform init` and assume an AWS role via OIDC. These are intentionally
# NOT managed by the repo's Terraform (they are the backend + auth that the
# Terraform itself depends on — a chicken-and-egg you must break manually).
#
# Creates:
#   1. GitHub OIDC identity provider in IAM
#   2. IAM role the workflow assumes (role-to-assume / vars.AWS_ROLE_ARN)
#   3. S3 bucket for remote state          (shivakrishna-tf-state-dev)
#   4. DynamoDB table for state locking     (vosukula-state-locking)
#
# Run with admin AWS credentials from your laptop. Idempotent: safe to re-run.
#
# Usage:
#   export AWS_REGION=us-east-1
#   ./bootstrap.sh
# =============================================================================
set -euo pipefail

# ─── Config (edit if your names differ) ──────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="github-oidc-terraform-prometheus"
STATE_BUCKET="shivakrishna-tf-state-dev"
LOCK_TABLE="vosukula-state-locking"
GH_REPO="ShivaKrishna44/terraform-prometheus"
OIDC_URL="token.actions.githubusercontent.com"
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "==> AWS Account: ${ACCOUNT_ID}  Region: ${AWS_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 1. GitHub OIDC provider ─────────────────────────────────────────────────
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}" >/dev/null 2>&1; then
  echo "==> [1/4] OIDC provider already exists, skipping."
else
  echo "==> [1/4] Creating GitHub OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "${OIDC_THUMBPRINT}"
fi

# ─── 2. IAM role the workflow assumes ────────────────────────────────────────
# Render the trust policy with the real account ID.
TRUST_JSON="$(sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "${SCRIPT_DIR}/trust-policy.json")"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "==> [2/4] Role ${ROLE_NAME} exists, updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "${TRUST_JSON}"
else
  echo "==> [2/4] Creating role ${ROLE_NAME}..."
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_JSON}"
fi

# Permissions the plan/apply needs. This Terraform creates EC2 + IAM resources,
# so the role needs IAM write access too. PowerUserAccess + IAMFullAccess is a
# pragmatic start — SCOPE THIS DOWN to least privilege once the pipeline works.
echo "    Attaching managed policies (broad — tighten later)..."
aws iam attach-role-policy --role-name "${ROLE_NAME}" \
  --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess"
aws iam attach-role-policy --role-name "${ROLE_NAME}" \
  --policy-arn "arn:aws:iam::aws:policy/IAMFullAccess"

# ─── 3. S3 bucket for remote state ───────────────────────────────────────────
if aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "==> [3/4] State bucket ${STATE_BUCKET} already exists, skipping."
else
  echo "==> [3/4] Creating state bucket ${STATE_BUCKET}..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    # us-east-1 does NOT accept a LocationConstraint
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
  echo "    Enabling versioning + encryption + public access block..."
  aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# ─── 4. DynamoDB table for state locking ─────────────────────────────────────
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
  echo "==> [4/4] Lock table ${LOCK_TABLE} already exists, skipping."
else
  echo "==> [4/4] Creating lock table ${LOCK_TABLE}..."
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"
  aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${AWS_REGION}"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
cat <<EOF

============================================================
Bootstrap complete.

Set this GitHub repository VARIABLE (Settings -> Secrets and
variables -> Actions -> Variables tab -> New repository variable):

    Name:  AWS_ROLE_ARN
    Value: ${ROLE_ARN}

(It must be a VARIABLE, not a secret — the workflow reads vars.AWS_ROLE_ARN.)

Then re-run the failed "Terraform Plan" job.
============================================================
EOF
