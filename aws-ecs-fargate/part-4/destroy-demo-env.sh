#!/bin/bash

# Exit on error
set -e

# Load environment variables
source .env

# Configure AWS credentials (use AWS SSO, environment variables, or AWS CLI profile)
# Example: aws sso login --profile your-profile-name
# Or set AWS_PROFILE environment variable in .env

echo "========================================="
echo "Destroying ECS Fargate Demo Environment"
echo "========================================="

# Get Terraform outputs first
echo ""
echo "Step 1: Getting infrastructure details..."
cd terraform
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")

if [ -z "$CLUSTER_NAME" ]; then
  echo "Warning: Could not get cluster name from Terraform. Trying default..."
  CLUSTER_NAME="azp-agent-demo-bind-mounts"
fi

if [ -z "$ECR_REPO" ]; then
  echo "Warning: Could not get ECR repository URL from Terraform."
else
  echo "ECR Repository: $ECR_REPO"
  echo "Cluster Name: $CLUSTER_NAME"
fi

# Stop all running tasks
echo ""
echo "Step 2: Stopping all running ECS tasks..."
TASK_ARNS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[]' --output text)

if [ -n "$TASK_ARNS" ]; then
  echo "Found running tasks. Stopping them..."
  for TASK_ARN in $TASK_ARNS; do
    echo "  Stopping task: $TASK_ARN"
    aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN --no-cli-pager
  done

  echo "Waiting for tasks to stop..."
  sleep 10
else
  echo "No running tasks found."
fi

# Delete ECR repository and images
if [ -n "$ECR_REPO" ]; then
  echo ""
  echo "Step 3: Deleting ECR repository and all images..."

  # Extract repository name from URL
  ECR_REPO_NAME=$(echo $ECR_REPO | cut -d'/' -f2)

  echo "Repository name: $ECR_REPO_NAME"

  # Delete the repository (force delete removes all images)
  aws ecr delete-repository \
    --repository-name $ECR_REPO_NAME \
    --force \
    --no-cli-pager 2>/dev/null && echo "ECR repository deleted successfully." || echo "ECR repository may not exist or already deleted."
else
  echo ""
  echo "Step 3: Skipping ECR deletion (repository URL not found)"
fi

# Terraform destroy
echo ""
echo "Step 4: Destroying infrastructure with Terraform..."
terraform destroy --auto-approve

echo ""
echo "========================================="
echo "Demo environment destroyed successfully!"
echo "========================================="
