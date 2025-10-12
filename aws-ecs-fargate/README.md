# Azure Pipelines Agent on AWS ECS Fargate

This demo environment deploys self-hosted Azure Pipelines agents on AWS ECS Fargate. The agents are containerized and can execute pipeline jobs on-demand in a serverless container environment.

## Architecture Overview

```
Azure DevOps Pipeline → Triggers Job
         ↓
ECS Fargate Task (Agent Container)
         ↓
Pulls secrets from AWS Secrets Manager
         ↓
Executes Pipeline Jobs
```

**Components:**
- **Docker Image**: Alpine-based container with Azure Pipelines agent, Docker CLI, and Azure CLI
- **AWS ECS Fargate**: Serverless container orchestration
- **AWS ECR**: Container registry for agent images
- **AWS Secrets Manager**: Secure storage for Azure DevOps credentials
- **CloudWatch Logs**: Centralized logging for agent activities

## Prerequisites

Before starting, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with SSO or credentials
   ```bash
   aws configure --profile default
   # OR for SSO
   aws sso login --sso-session your-sso-session
   ```
3. **Terraform** >= 1.0 installed
4. **Docker** installed locally
5. **Azure DevOps Organization** with:
   - Personal Access Token (PAT) with "Agent Pools (read, manage)" permissions
   - Agent pool created (e.g., `Default`)

## Quick Start

### Option 1: Automated Setup Script

Use the provided script to deploy everything automatically:

```bash
cd aws-ecs-fargate
chmod +x build-demo-env.sh

# Review and update .env file first (see Configuration section)
./build-demo-env.sh
```

This script will:
1. Login to AWS SSO
2. Deploy infrastructure with Terraform
3. Build and push Docker image to ECR
4. Start an ECS Fargate task
5. Display task status

### Option 2: Manual Step-by-Step Deployment

#### Step 1: Configure Environment

1. **Create environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your values:**
   ```bash
   # Required Azure DevOps settings
   AZP_URL=https://dev.azure.com/your-organization
   AZP_TOKEN=your-personal-access-token
   AZP_POOL=your-agent-pool-name

   # AWS settings
   AWS_PROFILE=default
   AWS_ACCOUNT_ID=123456789012
   AWS_REGION=us-east-1
   ```

3. **Configure Terraform variables:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

   Update with your settings:
   ```hcl
   aws_region  = "us-east-1"
   aws_profile = "default"
   cluster_name = "azp-agent-cluster"

   azp_url   = "https://dev.azure.com/your-organization"
   azp_token = "your-personal-access-token"
   azp_pool  = "Default"

   task_cpu    = "256"  # .25 vCPU
   task_memory = "512"  # 512 MB
   ```

#### Step 2: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy infrastructure
terraform apply
```

This creates:
- ECR repository
- ECS cluster
- Task definition
- Secrets in AWS Secrets Manager
- IAM roles and policies
- CloudWatch log group

#### Step 3: Build and Push Docker Image

```bash
# Get ECR repository URL from Terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)

# Build the Docker image
cd ../docker
docker build -t azp-agent-aws-ecs-fargate .

# Login to ECR
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
  docker login --username AWS --password-stdin $ECR_URL

# Tag and push image
docker tag azp-agent-aws-ecs-fargate:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

#### Step 4: Run ECS Fargate Task

```bash
cd ../terraform

# Get task definition and cluster details
TASK_DEF_ARN=$(terraform output -raw task_definition_arn)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)

# Get default VPC network configuration
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
  --query "Vpcs[0].VpcId" --output text)

SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
  --query "Subnets[*].SubnetId" --output text | tr '\t' ',')

SECURITY_GROUP=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" \
  --query "SecurityGroups[0].GroupId" --output text)

# Launch the task
aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"
```

## Verification

### Check Agent Status

1. **In Azure DevOps:**
   - Navigate to: Organization Settings → Agent pools → [your-pool-name]
   - You should see the agent(s) listed as "Online"

2. **Check ECS Task Status:**
   ```bash
   aws ecs list-tasks --cluster $CLUSTER_NAME

   # Get detailed task info
   TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[0]' --output text)
   aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN
   ```

3. **View Agent Logs:**
   ```bash
   # Get log group from Terraform
   LOG_GROUP=$(terraform output -raw cloudwatch_log_group)

   # Tail logs
   aws logs tail $LOG_GROUP --follow
   ```

## Testing Azure Pipelines

### Test Pipeline Example

Create a pipeline in Azure DevOps to test the agent:

```yaml
trigger:
  - main

pool:
  name: demo-agent  # Your agent pool name

jobs:
- job: TestAgent
  displayName: 'Test ECS Fargate Agent'
  steps:
  - script: |
      echo "Hello from ECS Fargate!"
      echo "Agent Name: $(Agent.Name)"
      echo "Agent OS: $(Agent.OS)"
      uname -a
    displayName: 'Basic Info'

  - script: |
      docker --version
      az --version
    displayName: 'Check Installed Tools'
```

### Advanced Test: Volume Mounting

Use the provided comprehensive test pipeline:

```bash
# Pipeline is located at:
azure-pipelines/test-volume-mounting.yml
```

This pipeline tests:
- Path discovery and container paths
- Basic volume mounting scenarios
- Multi-stage container operations
- Docker-in-Docker volume mapping

To run:
1. Go to Azure DevOps → Pipelines → New Pipeline
2. Select "Existing Azure Pipelines YAML file"
3. Choose `aws-ecs-fargate/azure-pipelines/test-volume-mounting.yml`
4. Run the pipeline

## Docker Compose (Local Testing)

For local development and testing before deploying to ECS:

```bash
cd docker

# Create .env file (see Configuration section)
cp ../.env .

# Start agents locally
docker-compose up -d

# View logs
docker-compose logs -f

# Stop agents
docker-compose down
```

The docker-compose setup runs two agent instances (`azp-agent-1` and `azp-agent-2`) locally.

## Maintenance

### Updating the Agent Image

```bash
# Make changes to Dockerfile or start.sh
cd docker

# Rebuild and push
docker build -t azp-agent-aws-ecs-fargate .
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
  docker login --username AWS --password-stdin $ECR_URL
docker tag azp-agent-aws-ecs-fargate:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Stop old tasks (they will automatically pull new image on next run)
aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN
```

### Scaling Agents

To run multiple agents, simply execute `aws ecs run-task` multiple times, or create an ECS Service with desired count:

```bash
# Run 3 agent tasks
for i in {1..3}; do
  aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition $TASK_DEF_ARN \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"
done
```

### Viewing Logs

```bash
# Tail all agent logs
aws logs tail /ecs/azp-agent-demo --follow

# View logs for specific agent
aws logs tail /ecs/azp-agent-demo --follow --filter-pattern "azp-agent-fargate-1"

# View logs from last hour
aws logs tail /ecs/azp-agent-demo --since 1h
```

### Rotating Azure DevOps Token

```bash
# Update the secret in Secrets Manager
aws secretsmanager update-secret \
  --secret-id azp-agent-credentials \
  --secret-string '{"AZP_TOKEN":"new-token","AZP_POOL":"demo-agent","AZP_URL":"https://dev.azure.com/your-org"}'

# Restart tasks to pick up new token
aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN
```

## Cleanup

### Stop Running Tasks

```bash
# List and stop all tasks
TASK_ARNS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[*]' --output text)
for task in $TASK_ARNS; do
  aws ecs stop-task --cluster $CLUSTER_NAME --task $task
done
```

### Destroy Infrastructure

```bash
cd terraform

# Destroy all resources
terraform destroy
```

**Note:** This will delete:
- ECS cluster and task definitions
- ECR repository and images
- Secrets Manager secrets (after recovery window)
- IAM roles and policies
- CloudWatch log group and logs

## Troubleshooting

### Agent Not Appearing in Azure DevOps

1. **Check task status:**
   ```bash
   aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN
   ```

2. **Check logs for errors:**
   ```bash
   aws logs tail /ecs/azp-agent-demo --since 10m
   ```

3. **Common issues:**
   - Invalid Azure DevOps token
   - Incorrect agent pool name
   - Network connectivity issues (check security group allows outbound HTTPS)

### Task Fails to Start

1. **Check ECR image exists:**
   ```bash
   aws ecr describe-images --repository-name azp-agent-aws-ecs-fargate
   ```

2. **Verify task definition:**
   ```bash
   aws ecs describe-task-definition --task-definition azp-agent-demo
   ```

3. **Check IAM permissions:**
   - Task execution role needs permissions for ECR, Secrets Manager, and CloudWatch

### Docker-in-Docker Issues

- ECS Fargate does **not** support Docker-in-Docker natively
- Docker CLI is included for building images, but requires external Docker daemon
- Consider using AWS CodeBuild or EC2-based ECS for full Docker capabilities

## Security Considerations

- **Secrets Protection**: `.env` and `terraform.tfvars` are gitignored - never commit these files
- **Token Security**: Azure DevOps token stored in AWS Secrets Manager with encryption at rest
- **Least Privilege**: IAM roles follow principle of least privilege
- **Network Security**: Configure security groups appropriately for your use case
- **Image Scanning**: ECR repository has scan-on-push enabled

## Cost Considerations

- **ECS Fargate**: Charged per vCPU/hour and GB memory/hour while tasks are running
- **ECR Storage**: Charged per GB/month for stored images
- **CloudWatch Logs**: Charged for log storage and ingestion
- **Secrets Manager**: Charged per secret per month and API calls

**Cost Optimization Tips:**
- Stop tasks when not needed
- Use smaller task sizes for simple workloads
- Set CloudWatch log retention to 7 days or less
- Delete unused ECR images

## Additional Resources

- [Azure Pipelines Documentation](https://docs.microsoft.com/azure/devops/pipelines/)
- [AWS ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Original Azure Pipelines Agent Dockerfile](https://docs.microsoft.com/azure/devops/pipelines/agents/docker)

## Project Structure

```
aws-ecs-fargate/
├── README.md                          # This file
├── .env                              # Environment variables (gitignored)
├── .gitignore                        # Git ignore rules
├── build-demo-env.sh                 # Automated deployment script
├── docker/
│   ├── Dockerfile                    # Agent container image
│   ├── start.sh                      # Agent startup script
│   └── docker-compose.yml            # Local testing setup
├── terraform/
│   ├── main.tf                       # Infrastructure definition
│   ├── variables.tf                  # Variable declarations
│   ├── outputs.tf                    # Output values
│   ├── terraform.tfvars.example      # Example variables
│   ├── terraform.tfvars              # Your variables (gitignored)
│   └── README.md                     # Terraform-specific docs
└── azure-pipelines/
    └── test-volume-mounting.yml      # Test pipeline for validation
```

## License

This is a demo project for educational purposes.
