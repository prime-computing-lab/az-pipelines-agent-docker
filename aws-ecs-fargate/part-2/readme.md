# Azure Pipelines Agent on AWS ECS Fargate with EBS Persistent Storage

This demo environment demonstrates how to run containerized Azure Pipelines agents on AWS ECS Fargate with EBS volumes for persistent storage. This builds upon the basic ECS Fargate setup from Part 1 by adding persistent storage capabilities.

## Overview

This setup provides:
- **Containerized Azure Pipelines agents** running on ECS Fargate
- **EBS volumes** for persistent storage across agent tasks
- **KMS encryption** for EBS volumes
- **IAM roles** with appropriate permissions for EBS operations
- **CloudWatch logging** for monitoring
- **Terraform IaC** for reproducible infrastructure

## Architecture

The architecture includes:
- **ECS Fargate Cluster**: Serverless container orchestration
- **EBS Volume**: Persistent block storage attached to Fargate tasks
- **ECR Repository**: Docker image storage
- **Secrets Manager**: Secure credential storage
- **KMS Key**: Encryption for EBS volumes
- **IAM Roles**: Task execution and task roles with EBS permissions

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed
- Terraform >= 1.0
- Azure DevOps organization with:
  - Personal Access Token (PAT) with Agent Pools (read, manage) permissions
  - Agent Pool created (e.g., "demo-agent")

## Project Structure

```
part-2/
├── docker/
│   ├── Dockerfile              # Container image with volume support
│   ├── docker-compose.yml      # Local testing setup
│   └── start.sh                # Agent startup script
├── terraform/
│   ├── main.tf                 # Main infrastructure configuration
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Output values
│   ├── terraform.tfvars.example # Example variable values
│   └── .gitignore             # Terraform gitignore
├── azure-pipelines/
│   └── pipeline-persistent-storage.yml  # Test pipeline
├── .env.example               # Environment variables template
├── build-demo-env.sh          # Automated setup script
└── readme.md                  # This file
```

## Setup Instructions

### 1. Configure Environment Variables

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env` with your AWS and Azure DevOps details:
```bash
AWS_REGION=ap-southeast-2
AWS_ACCOUNT_ID=your-aws-account-id
AZP_URL=https://dev.azure.com/your-organization
AZP_TOKEN=your-pat-token
AZP_POOL=demo-agent
```

### 2. Configure Terraform Variables

Copy the example Terraform variables file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific configuration.

### 3. Deploy the Infrastructure

#### Option A: Automated Setup (Recommended)

Run the automated build script:

```bash
chmod +x build-demo-env.sh
./build-demo-env.sh
```

This script will:
1. Initialize and apply Terraform configuration
2. Build and push the Docker image to ECR
3. Start an ECS Fargate task with EBS volume
4. Display task status and next steps

#### Option B: Manual Setup

1. **Deploy Infrastructure**:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

2. **Build and Push Docker Image**:
   ```bash
   cd ../docker

   # Get ECR repository URL from Terraform output
   ECR_REPO=$(terraform -chdir=../terraform output -raw ecr_repository_url)

   # Build image
   docker build --platform linux/arm64 -t ${ECR_REPO}:latest .

   # Login to ECR
   aws ecr get-login-password --region ap-southeast-2 | \
     docker login --username AWS --password-stdin $ECR_REPO

   # Push image
   docker push ${ECR_REPO}:latest
   ```

3. **Start ECS Task**:
   ```bash
   # Get infrastructure details
   TASK_DEF_ARN=$(terraform -chdir=../terraform output -raw task_definition_arn)
   CLUSTER_NAME=$(terraform -chdir=../terraform output -raw ecs_cluster_name)
   KMS_KEY_ARN=$(terraform -chdir=../terraform output -raw kms_key_arn)

   # Get VPC configuration
   DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
     --query "Vpcs[0].VpcId" --output text)
   SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
     --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
   SECURITY_GROUP=$(aws ec2 describe-security-groups \
     --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" \
     --query "SecurityGroups[0].GroupId" --output text)

   # Create volume configuration file
   cat > /tmp/ebs-volume-config.json << EOF
   [
     {
       "name": "shared-volume",
       "ebs": {
         "volumeType": "gp3",
         "sizeInGiB": 20,
         "iops": 3000,
         "throughput": 125,
         "encrypted": true,
         "kmsKeyId": "$KMS_KEY_ARN",
         "deleteOnTermination": true
       }
     }
   ]
   EOF

   # Run task with EBS volume
   aws ecs run-task \
     --cluster $CLUSTER_NAME \
     --task-definition $TASK_DEF_ARN \
     --launch-type FARGATE \
     --platform-version 1.4.0 \
     --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
     --volume-configurations file:///tmp/ebs-volume-config.json
   ```

## Testing Persistent Storage

### Run the Test Pipeline

1. Import the pipeline in Azure DevOps:
   - Go to Pipelines → New Pipeline
   - Select your repository
   - Choose "Existing Azure Pipelines YAML file"
   - Select `aws-ecs-fargate/part-2/azure-pipelines/pipeline-persistent-storage.yml`

2. Run the pipeline:
   - The **Build** stage runs on `azp-agent-1-ebs` and creates an artifact in `/shared-volume/artifacts`
   - The **Deploy** stage runs on `azp-agent-2-ebs` and retrieves the artifact from the same volume
   - This demonstrates that the EBS volume persists data across different agent tasks

### Local Testing with Docker Compose

Before deploying to ECS, you can test locally:

```bash
cd docker
docker-compose up -d
```

This simulates the EBS volume behavior using a local Docker volume.

## EBS Volume Configuration

The demo uses the following EBS configuration:

- **Volume Type**: gp3 (General Purpose SSD)
- **Size**: 20 GB
- **IOPS**: 3000
- **Throughput**: 125 MB/s
- **Encryption**: Enabled with KMS
- **Delete on Termination**: True (for demo purposes)

You can adjust these settings in `terraform/variables.tf` or pass them via terraform variables.

## Monitoring and Troubleshooting

### View CloudWatch Logs

```bash
aws logs tail /ecs/azp-agent-demo-ebs --follow
```

### Check Task Status

```bash
CLUSTER_NAME=$(terraform -chdir=terraform output -raw ecs_cluster_name)
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN
```

### Check EBS Volume

```bash
# List volumes with specific tags
aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=azp-agent-ebs-volume" \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,State:State,Type:VolumeType}'
```

### Common Issues

1. **Task fails to start**: Check CloudWatch logs for errors
2. **Volume attachment issues**: Ensure platform version 1.4.0 or later
3. **Permission errors**: Verify IAM roles have correct EBS and KMS permissions
4. **Agents not appearing in Azure DevOps**: Check AZP_TOKEN, AZP_URL, and AZP_POOL settings

## Key Differences from Part 1

| Aspect | Part 1 | Part 2 |
|--------|--------|--------|
| Storage | Ephemeral (task storage only) | Persistent (EBS volume) |
| Volume Configuration | None | EBS volume with KMS encryption |
| IAM Task Role | Not required | Required for EBS operations |
| Platform Version | Any | 1.4.0+ required for EBS |
| Use Case | Stateless workloads | Stateful workloads requiring persistence |

## EBS Storage Options

AWS ECS Fargate supports three storage options:

1. **EBS Volumes** (this demo):
   - Persistent block storage
   - High performance
   - KMS encryption support
   - Best for: Build artifacts, caches, shared data

2. **EFS** (Elastic File System):
   - Shared NFS file system
   - Multiple tasks can access simultaneously
   - Best for: Shared configuration, multi-task access

3. **Bind Mount**:
   - Docker-in-Docker scenarios
   - Limited to task ephemeral storage
   - Best for: Container-based builds

## Cost Considerations

- **ECS Fargate**: Pay per vCPU and memory per second
- **EBS Volume**: Pay per GB-month + IOPS and throughput
- **ECR**: Pay per GB stored
- **KMS**: Pay per key per month + API requests
- **Data Transfer**: Standard AWS data transfer charges apply

For cost optimization:
- Delete volumes when not in use (set `deleteOnTermination: true`)
- Right-size CPU/memory allocations
- Use lifecycle policies for ECR images

## Cleanup

To destroy all resources:

```bash
# Stop any running tasks first
CLUSTER_NAME=$(terraform -chdir=terraform output -raw ecs_cluster_name)
aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[]' --output text | \
  xargs -I {} aws ecs stop-task --cluster $CLUSTER_NAME --task {}

# Wait for tasks to stop
sleep 30

# Destroy infrastructure
cd terraform
terraform destroy --auto-approve
```

## References

- [AWS ECS EBS Volumes Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ebs-volumes.html)
- [ECS Fargate Storage Options](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_data_volumes.html)
- [EBS Volume Configuration](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/configure-ebs-volume.html)
- [EBS KMS Encryption](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ebs-kms-encryption.html)
- [Azure Pipelines Container Jobs](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/container-phases)

## Next Steps

- Implement auto-scaling for agents based on pipeline queue depth
- Add monitoring and alerting for agent health
- Explore EFS for shared file system scenarios
- Implement CI/CD for agent image updates
- Add backup strategies for persistent data

## Related Content

- Part 1: Basic Azure Pipelines Agent on ECS Fargate (no persistent storage)
- Video: Complete walkthrough of EBS persistent storage setup
