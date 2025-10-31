#!/bin/bash

# Rebuild and redeploy Docker image using Dockerfile-fixed
# This script skips Terraform deployment and only rebuilds the Docker image

# Exit on error
set -e

# Load environment variables
source .env

# Configure AWS credentials (use AWS SSO, environment variables, or AWS CLI profile)
# Example: aws sso login --profile your-profile-name
# Or set AWS_PROFILE environment variable in .env

echo "========================================="
echo "Rebuilding Docker Image (Dockerfile-fixed)"
echo "========================================="

# Get outputs from existing Terraform deployment
cd terraform
ECR_REPO=$(terraform output -raw ecr_repository_url)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
echo "ECR Repository: $ECR_REPO"
echo "Task Definition: $TASK_DEF_ARN"
echo "Cluster Name: $CLUSTER_NAME"

# Build and push Docker image
echo ""
echo "Building and pushing Docker image..."
cd ../docker
IMAGE_TAG="latest"

# Build the image
docker build -f Dockerfile-fixed --platform linux/arm64 -t ${ECR_REPO}:${IMAGE_TAG} .

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO

# Push the image
echo "Pushing image to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo ""
echo "Stopping any existing running tasks..."

# Get list of running tasks in the cluster
RUNNING_TASKS=$(aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --desired-status RUNNING \
  --query 'taskArns[*]' \
  --output text)

if [ -n "$RUNNING_TASKS" ]; then
  echo "Found running tasks. Stopping them..."
  for TASK in $RUNNING_TASKS; do
    echo "Stopping task: $TASK"
    aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK > /dev/null
  done
  echo "All existing tasks stopped. Waiting for cleanup..."
  sleep 5
else
  echo "No running tasks found."
fi

echo ""
echo "Running ECS task with bind mount..."

# Get default VPC configuration
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

echo "VPC: $DEFAULT_VPC"
echo "Subnets: $SUBNETS"
echo "Security Group: $SECURITY_GROUP"

# Run ECS task with bind mount (no additional volume configuration needed)
echo ""
echo "Starting ECS task with bind mount..."

# Note: Bind mounts don't require volume-configurations parameter
# The volume is defined in the task definition itself
TASK_RUN_OUTPUT=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
  --output json)

echo ""
echo "Task started successfully!"
echo ""

# Get task ARN from the output
TASK_ARN=$(echo $TASK_RUN_OUTPUT | jq -r '.tasks[0].taskArn')
echo "Task ARN: $TASK_ARN"

# Wait a moment for task to initialize
echo ""
echo "Waiting for task to start..."
sleep 5

# Describe the task
echo ""
echo "Task Status:"
aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --query 'tasks[0].{TaskArn:taskArn,Status:lastStatus,DesiredStatus:desiredStatus,Cpu:cpu,Memory:memory,StoppedReason:stoppedReason,Containers:containers[*].{Name:name,Status:lastStatus,ExitCode:exitCode,Reason:reason}}' \
  --output json

echo ""
echo "========================================="
echo "Demo environment setup complete!"
echo "========================================="
echo ""
echo "IMPORTANT: Bind mount data is ephemeral!"
echo "All data will be lost when the task stops or restarts."
echo ""
echo "Next steps:"
echo "1. Check CloudWatch logs: /ecs/azp-agent-demo-bind-mounts"
echo "2. Verify agents in Azure DevOps portal"
echo "3. Run the pipeline: azure-pipelines/pipeline-bind-mounts.yml"
echo ""
echo "To check task status:"
echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN"
echo ""
echo "To stop the task:"
echo "  aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN"
echo ""
echo "To destroy the environment:"
echo "  cd terraform && terraform destroy --auto-approve"
