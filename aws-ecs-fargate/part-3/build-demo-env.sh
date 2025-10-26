#!/bin/bash

# Exit on error
set -e

export AWS_PROFILE="your-aws-profile"
source .env
aws sso login --sso-session your-sso-session

echo "========================================="
echo "Building ECS Fargate Demo with EFS Storage"
echo "========================================="

# Initialize and apply Terraform
echo ""
echo "Step 1: Deploying infrastructure with Terraform..."
cd terraform
terraform init
terraform apply --auto-approve

# Get outputs
ECR_REPO=$(terraform output -raw ecr_repository_url)
# TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
TASK_DEF_FAMILY=$(terraform output -raw task_definition_family)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
EFS_ID=$(terraform output -raw efs_file_system_id)
EFS_DNS=$(terraform output -raw efs_dns_name)
echo "ECR Repository: $ECR_REPO"
echo "Task Definition: $TASK_DEF_ARN"
echo "Cluster Name: $CLUSTER_NAME"
echo "EFS File System ID: $EFS_ID"
echo "EFS DNS Name: $EFS_DNS"

# Build and push Docker image
echo ""
echo "Step 2: Building and pushing Docker image..."
cd ../docker
IMAGE_TAG="latest"

# Build the image
docker build --platform linux/arm64 -t ${ECR_REPO}:${IMAGE_TAG} .

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO

# Push the image
echo "Pushing image to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo ""
echo "Step 3: Running ECS task with EFS volume..."

# Get default VPC configuration
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
# Pin ECS task to the same subnet as EFS
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "Subnets[0].SubnetId" --output text)
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

echo "VPC: $DEFAULT_VPC"
echo "Subnets: $SUBNETS"
echo "Security Group: $SECURITY_GROUP"

# Run ECS task (EFS is already configured in the task definition)
echo ""
echo "Starting ECS task with EFS volume..."

TASK_RUN_OUTPUT=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_FAMILY \
  --launch-type FARGATE \
  --platform-version 1.4.0 \
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
echo "EFS File System Information:"
echo "  ID: $EFS_ID"
echo "  DNS: $EFS_DNS"
echo ""
echo "Next steps:"
echo "1. Check CloudWatch logs: /ecs/azp-agent-demo-efs"
echo "2. Verify agents in Azure DevOps portal"
echo "3. Run the pipeline: azure-pipelines/pipeline-shared-efs-storage.yml"
echo ""
echo "EFS Access Points Demo (Manual Steps):"
echo "  See readme.md for instructions on creating and testing EFS access points"
echo "  This demonstrates 'defense in depth' security:"
echo "    - Network layer: Security groups"
echo "    - Identity layer: IAM policies"
echo "    - Application layer: EFS access points (directory isolation)"
echo ""
echo "To check task status:"
echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN"
echo ""
echo "To stop the task:"
echo "  aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN"
echo ""
echo "To destroy the environment:"
echo "  cd terraform && terraform destroy --auto-approve"
echo ""
