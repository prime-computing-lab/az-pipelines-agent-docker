#!/bin/bash

# Exit on error
set -e

export AWS_PROFILE="admin-sandbox2"
source .env
aws sso login --sso-session prime

echo "========================================="
echo "Building ECS Fargate Demo with EBS Storage"
echo "========================================="

# Initialize and apply Terraform
echo ""
echo "Step 1: Deploying infrastructure with Terraform..."
cd aws-ecs-fargate/part-2/terraform
terraform init
terraform apply --auto-approve

# Get outputs
ECR_REPO=$(terraform output -raw ecr_repository_url)
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
echo "ECR Repository: $ECR_REPO"
echo "Task Definition: $TASK_DEF_ARN"
echo "Cluster Name: $CLUSTER_NAME"

# Build and push Docker image
echo ""
echo "Step 2: Building and pushing Docker image..."
cd ../docker
IMAGE_TAG="latest"

# Build the image
docker build --platform linux/arm64 -t ${ECR_REPO}:${IMAGE_TAG} .

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Push the image
echo "Pushing image to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo ""
echo "Step 3: Running ECS task with EBS volume..."

# Get default VPC configuration
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

echo "VPC: $DEFAULT_VPC"
echo "Subnets: $SUBNETS"
echo "Security Group: $SECURITY_GROUP"

# Get the KMS key ARN and IAM role ARN for EBS
KMS_KEY_ARN=$(terraform -chdir=../terraform output -raw kms_key_arn)
ECS_INFRA_ROLE_ARN=$(terraform -chdir=../terraform output -raw ecs_infrastructure_role_arn)

# Run ECS task with EBS volume configuration
echo ""
echo "Starting ECS task with EBS volume..."

# Create a temporary file for the volume configuration
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/configure-ebs-volume.html
VOLUME_CONFIG=$(cat <<EOF
[
  {
    "name": "shared-volume",
    "managedEBSVolume": {
      "roleArn": "$ECS_INFRA_ROLE_ARN",
      "volumeType": "gp3",
      "sizeInGiB": 5,
      "iops": 3000,
      "throughput": 125,
      "encrypted": true,
      "kmsKeyId": "$KMS_KEY_ARN",
      "filesystemType": "ext4",
      "terminationPolicy": {
          "deleteOnTermination": false
      },
      "tagSpecifications": [
        {
          "resourceType": "volume",
          "tags": [
            {
              "key": "Name",
              "value": "azp-agent-ebs-volume"
            },
            {
              "key": "Environment",
              "value": "demo"
            }
          ]
        }
      ]
    }
  }
]
EOF
)

# Write the volume configuration to a temporary file
echo "$VOLUME_CONFIG" > /tmp/ebs-volume-config.json

# Run the task with EBS volume
TASK_RUN_OUTPUT=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --platform-version 1.4.0 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
  --volume-configurations "$(cat /tmp/ebs-volume-config.json)" \
  --output json)

# Clean up temp file
rm -f /tmp/ebs-volume-config.json

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
echo "Next steps:"
echo "1. Check CloudWatch logs: /ecs/azp-agent-demo-ebs"
echo "2. Verify agents in Azure DevOps portal"
echo "3. Run the pipeline: azure-pipelines/pipeline-persistent-storage.yml"
echo ""
echo "To check task status:"
echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN"
echo ""
echo "To stop the task:"
echo "  aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN"
echo ""
echo "To destroy the environment:"
echo "  cd terraform && terraform destroy --auto-approve"
