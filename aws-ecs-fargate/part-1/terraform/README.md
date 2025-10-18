# Azure Pipelines Agent on AWS ECS Fargate - Terraform Deployment

This Terraform configuration deploys the Azure Pipelines agent infrastructure on AWS ECS Fargate.

## Prerequisites

- Terraform
- AWS CLI configured with appropriate credentials
- Docker installed locally
- Azure DevOps organization with a Personal Access Token

## What This Creates

- **ECR Repository**: For storing the Azure Pipelines agent Docker image
- **Secrets Manager**: Stores Azure Pipelines credentials securely
- **IAM Role**: ECS task execution role with necessary permissions
- **ECS Cluster**: Fargate cluster for running agents
- **CloudWatch Logs**: Log group for agent logs
- **ECS Task Definition**: Defines how the agent container runs

## Setup

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars with your values:**
   ```bash
   vim terraform.tfvars
   ```

3. **Ensure AWS SSO is logged in:**
   ```bash
   aws sso login --sso-session <sso-session-name>
   ```

## Deployment

### 1. Build and Push Docker Image

First, build and push the Docker image to ECR:

```bash
# Initialize Terraform
terraform init

# Create the ECR repository
terraform apply -target=aws_ecr_repository.azp_agent

# Get the ECR repository URL from output
ECR_URL=$(terraform output -raw ecr_repository_url)

# Build the Docker image (from parent directory)
cd ..
docker build -t azp-agent-aws-ecs-fargate .

# Login to ECR
aws ecr get-login-password --region <region> --profile <your-profile> | \
  docker login --username AWS --password-stdin $ECR_URL

# Tag and push the image
docker tag azp-agent-aws-ecs-fargate:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Return to terraform directory
cd terraform
```

### 2. Deploy Infrastructure

```bash
# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

## Running a Task

After deployment, you need to run the ECS task manually or create a service. To run a one-off task:

```bash
# Get the task definition ARN
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)

# Get subnets from default VPC
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')

# Get default security group for the VPC
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

# Run the task
aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"
```

## Cleanup

To destroy all resources:

```bash
# Destroy all infrastructure
terraform destroy
```

**Note:** Before destroying, ensure no ECS tasks are running in the cluster.

## Viewing Logs

```bash
# Get the log group name
LOG_GROUP=$(terraform output -raw cloudwatch_log_group)

# View logs
aws logs tail $LOG_GROUP --follow
```

## Updating the Image

To update the Docker image:

```bash
# Build new image
docker build -t azp-agent-aws-ecs-fargate .

# Get ECR URL
ECR_URL=$(terraform output -raw ecr_repository_url)

# Login, tag, and push
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
  docker login --username AWS --password-stdin $ECR_URL

docker tag azp-agent-aws-ecs-fargate:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Force new task deployment (if using a service)
aws ecs update-service --cluster $CLUSTER_NAME --service my-service --force-new-deployment
```

## Outputs

After applying, Terraform provides useful outputs:

- `ecr_repository_url`: ECR repository URL for pushing images
- `ecs_cluster_name`: Name of the ECS cluster
- `task_definition_arn`: ARN of the task definition
- `docker_login_command`: Complete command to login to ECR

## Security Notes

- `terraform.tfvars` contains secrets and is gitignored
- Azure Pipelines token is stored in AWS Secrets Manager
- ECS tasks pull secrets from Secrets Manager at runtime
- IAM roles follow least-privilege principle
