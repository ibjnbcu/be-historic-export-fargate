#!/bin/bash
set -euo pipefail

# -----------------------------------------------
# Trigger the BE Historic Export Fargate task
#
# Usage: ./trigger-export.sh
#
# This kicks off the export. It runs in the
# background on Fargate — no need to wait.
# Check CloudWatch logs for progress.
# -----------------------------------------------

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="be-historic-export-cluster"
TASK_DEF="be-historic-export-task"

# !! Update these with your actual values after terraform apply !!
SUBNETS="${SUBNET_IDS:-subnet-XXXXXXXXX}"
SECURITY_GROUP="${SG_ID:-sg-XXXXXXXXX}"

echo "=== Triggering BE Historic Export ==="

TASK_ARN=$(aws ecs run-task \
    --cluster "${CLUSTER}" \
    --task-definition "${TASK_DEF}" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=ENABLED}" \
    --region "${REGION}" \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: ${TASK_ARN}"
echo ""
echo "Monitor logs:"
echo "  aws logs tail /ecs/be-historic-export --follow --region ${REGION}"
echo ""
echo "Or check in the AWS Console:"
echo "  ECS > Clusters > ${CLUSTER} > Tasks"
