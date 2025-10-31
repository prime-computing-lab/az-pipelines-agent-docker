# ECS Fargate with Bind Mounts - Azure Pipelines Agent Demo

This demo environment showcases running Azure Pipelines agents on AWS ECS Fargate with **bind mount** storage for shared data between containers.

## Overview

This is part 4 of the ECS Fargate storage comparison series:
- **Part 2**: EBS volumes
- **Part 3**: EFS (Elastic File System)
- **Part 4**: Bind mounts (this demo)

## What are Bind Mounts?

Bind mounts are host-based volumes that:
- Create an empty directory on the Fargate infrastructure
- Are shared between containers in the same task
- Are **tied to the lifecycle of the container/task**
- Do NOT persist data across task restarts or terminations
- Are suitable for temporary storage and inter-container communication

## Key Characteristics

### When to Use Bind Mounts
- Temporary file sharing between containers in the same task
- Scratch space for build artifacts within a task
- No need for data persistence across task restarts
- Low cost - no additional storage charges

### When NOT to Use Bind Mounts
- Persistent storage requirements
- Data needs to survive container/task restarts
- Shared storage across multiple tasks
- Long-term data retention

## Important Limitations

**Data Lifecycle**: All data in bind mounts is lost when the task stops or restarts. This makes bind mounts **unsuitable for Azure Pipelines agents** that need persistent work directories between jobs.

## Architecture

```
┌─────────────────────────────────────────┐
│         ECS Fargate Task                │
│                                         │
│  ┌──────────────┐   ┌──────────────┐  │
│  │   Agent 1    │   │   Agent 2    │  │
│  │              │   │              │  │
│  │ /shared-     │   │ /shared-     │  │
│  │  storage ────┼───┼── storage    │  │
│  └──────────────┘   └──────────────┘  │
│          │                 │           │
│          └────── Bind ─────┘           │
│                 Mount                  │
│         (ephemeral storage)            │
│                                        │
│   Data is lost on task termination    │
└─────────────────────────────────────────┘
```

## Demo Components

### Infrastructure (Terraform)
- ECR repository for Docker images
- ECS Fargate cluster
- Task definition with bind mount configuration
- IAM roles for task execution
- Secrets Manager for Azure Pipelines credentials
- CloudWatch log groups

### Azure Pipelines Agents (Docker)
- Alpine Linux-based containers
- 2 agents sharing a bind mount volume
- Azure CLI pre-installed
- Non-root user (agent) configuration

### Pipeline
- Build stage: Creates artifacts and saves to bind mount
- Deploy stage: Retrieves artifacts from bind mount (same task only)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker Desktop (for local testing)
- Azure DevOps organization with agent pool
- Azure Pipelines Personal Access Token (PAT)

## Configuration

Before deployment, configure the following files (never commit these):

1. Copy `.env.example` to `.env` and configure:
   - `AZP_URL`: Your Azure DevOps organization URL
   - `AZP_TOKEN`: Your Personal Access Token
   - `AZP_POOL`: Your agent pool name

2. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and configure:
   - `aws_profile`: Your AWS CLI profile
   - `aws_region`: Your AWS region
   - `cluster_name`: Your ECS cluster name

**Note**: Never commit `.env`, `terraform.tfvars`, or `terraform.tfstate*` files to version control.

## Quick Start

Use the provided scripts for automated deployment:

```bash
# Deploy infrastructure and build agents
./build-demo-env.sh

# Cleanup resources
./destroy-demo-env.sh
```

Manual deployment:

```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply

# 2. Build and push Docker image
docker build -f docker/Dockerfile --platform linux/arm64 -t <ecr-repo-url>:latest .
docker push <ecr-repo-url>:latest

# 3. Task runs automatically with 2 agents sharing bind mount storage
```

## Configuration Details

### Bind Mount Volume Configuration

In the ECS task definition:

```hcl
volume {
  name = "bind-mount-storage"
  # No additional configuration needed
  # Creates an empty directory on the Fargate host
}
```

Container mount points:

```hcl
mountPoints = [
  {
    sourceVolume  = "bind-mount-storage"
    containerPath = "/shared-storage"
    readOnly      = false
  }
]
```

## Comparison with EBS and EFS

| Feature | Bind Mounts | EBS | EFS |
|---------|-------------|-----|-----|
| Data Persistence | Lost on task stop | Persists | Persists |
| Sharing Across Tasks | Same task only | Single task | Multiple tasks |
| Performance | Fast (local) | High | Variable |
| Cost | Free | $$ | $$$ |
| Setup Complexity | Simple | Medium | Complex |
| Use Case | Temporary | Single task persistent | Multi-task shared |

## Limitations

- Data is lost when the task stops or restarts
- Data is only shared between containers in the same task
- No encryption at rest or backup capabilities

## Conclusion

Bind mounts are not suitable for Azure Pipelines agents requiring persistent work directories. Use EBS for single-task persistent storage or EFS for multi-task shared storage.

## Resources

- [AWS ECS Bind Mounts Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/bind-mounts.html)
- [ECS Storage Types Comparison](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_data_volumes.html)
- [Bind Mount Configuration](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specify-bind-mount-config.html)

## Cleanup

```bash
# Destroy all resources
cd terraform
terraform destroy
```

## License

This demo is provided as-is for educational purposes.
