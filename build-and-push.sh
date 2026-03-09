#!/bin/bash
set -euo pipefail

# -----------------------------------------------
# Build and push the export runner image to ECR
# ECR tags are IMMUTABLE — uses versioned tags
#
# Usage: ./build-and-push.sh [tag]
# Example: ./build-and-push.sh v2
# Default tag: v1
# -----------------------------------------------

TAG="${1:-v1}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/be-historic-export-runner"

echo "=== Building Docker Image (tag: ${TAG}) ==="
cd "$(dirname "$0")/docker"
docker build -t be-historic-export-runner:"${TAG}" .

echo "=== Logging into ECR ==="
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "=== Tagging and Pushing ==="
docker tag be-historic-export-runner:"${TAG}" "${ECR_REPO}:${TAG}"
docker push "${ECR_REPO}:${TAG}"

echo "=== Done ==="
echo "Image pushed to: ${ECR_REPO}:${TAG}"
echo ""
echo "If you used a new tag, update terraform.tfvars:"
echo "  image_tag = \"${TAG}\""
echo "Then run: terraform apply"
echo ""
echo "Trigger the task with: ./trigger-export.sh"
