# AWS ECS Fargate with EFS - Azure Pipelines Agent Demo

This demo shows how to run **non-root containers** on AWS ECS Fargate with **Amazon EFS** for shared, persistent storage. It demonstrates a common permission issue with EFS and non-root users, and how to solve it using **EFS Access Points**.

## Overview

**The Problem:** EFS enforces POSIX permissions at the filesystem level. When containers run as non-root users, they cannot create directories without proper ownership setup.

**The Solution:** [EFS Access Points](https://medium.com/@viniciuscolutti/how-to-use-efs-volumes-with-non-root-user-on-ecs-fargate-containers-b927e5db46c9) enforce user identity (UID/GID) at the EFS level, creating directories with correct ownership automatically.

## Key Concepts

### EFS Components
- **File System**: Elastic, scalable NFS storage that multiple containers access simultaneously
- **Mount Target**: Network endpoint (port 2049) in your VPC for NFS connections
- **Access Point**: Application-specific entry point that enforces:
  - POSIX user identity (UID/GID)
  - Root directory path isolation
  - Ownership and permissions

### EFS vs EBS
| Feature | EFS | EBS |
|---------|-----|-----|
| Sharing | Multiple containers simultaneously | Single task only |
| Lifecycle | Independent of tasks | Tied to task lifecycle |
| Root Access | Not required (with Access Points) | Required |

## Demo Flow

This demo intentionally demonstrates the problem before the solution:

1. **Initial Setup** → Deploy without Access Point → Pipeline fails with permission error
2. **Solution** → Create EFS Access Point with UID 1000 → Update task definition → Pipeline succeeds

This proves non-root containers work with EFS when properly configured.

## Architecture

```
ECS Fargate Tasks (UID 1000) → EFS Access Point (UID 1000) → EFS File System
                                      ↓
                            /agent-storage (owned by 1000:1000)
```

## Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- Docker
- Azure DevOps account with Personal Access Token
- jq

## Setup

1. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with AWS region, AZP_URL, AZP_TOKEN, AZP_POOL

   cd terraform && cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars
   ```

2. **Deploy infrastructure**
   ```bash
   ./build-demo-env.sh
   ```

   This deploys: EFS with KMS encryption, ECS cluster, task definition (2 agents), ECR repository, IAM roles, and CloudWatch logs.

## What Gets Deployed

- **EFS**: Encrypted file system, security group (NFS port 2049), mount target
- **ECS**: Fargate cluster, task definition with 2 Alpine Linux containers (non-root user `agent` UID 1000)
- **IAM**: Task execution role (ECR, Secrets Manager access) and task role (EFS permissions)
- **Storage**: EFS volume mounted at `/shared-storage`

## Demo Walkthrough

### Phase 1: The Problem ❌

1. **Verify agents** in Azure DevOps (Project Settings → Agent Pools)
2. **Run pipeline** `azure-pipelines/pipeline-shared-efs-storage.yml`
3. **Expected result**: Fails with `Permission denied` error

**Why it fails:**
- Container runs as UID 1000
- Dockerfile's `chown agent /shared-storage` is ignored when EFS mounts (EFS overlay takes precedence)
- EFS enforces POSIX permissions at filesystem level
- No matching ownership = permission denied

### Phase 2: The Solution ✅

**Create EFS Access Point:**
```bash
./fix-efs-permissions.sh
```

This creates an access point with:
- POSIX User: UID/GID 1000 (matches container user)
- Root directory: `/agent-storage` with permissions 755 and owner 1000:1000

**Update task definition:**
```bash
./update-task-with-access-point.sh
```

Adds `accessPointId` to task definition's `authorizationConfig`.

**Restart tasks:**
```bash
cd terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[]' --output text | \
  xargs -I {} aws ecs stop-task --cluster $CLUSTER_NAME --task {}
```

**Re-run pipeline**: Now succeeds! The pipeline demonstrates:
- Agent 1 creates artifacts on EFS
- Agent 2 retrieves and deploys from EFS
- Agent 1 verifies Agent 2's data

## How Access Points Solve the Problem

**Access Point Configuration:**
- `PosixUser`: Enforces UID/GID 1000 for all operations
- `RootDirectory.Path`: Isolates access to `/agent-storage`
- `CreationInfo`: Creates directory with owner 1000:1000, permissions 755

**Task Definition Change:**
- Added: `authorizationConfig.accessPointId`
- Required: `transitEncryption: ENABLED` (needed for IAM auth)

**Security Layers:**
1. **Network**: Security group allows NFS (2049) from ECS tasks
2. **IAM**: Policies grant `ClientMount` and `ClientWrite` permissions
3. **Access Point**: Enforces UID/GID and directory isolation

## Production Considerations

**Performance:**
- General Purpose mode (default): Suitable for most workloads
- Max I/O mode: For highly parallelized workloads
- Bursting throughput: Scales with storage size
- Provisioned throughput: For consistent performance

**Cost Optimization:**
- Lifecycle policies: Move infrequent files to IA storage
- EFS One Zone: Lower cost for non-HA workloads
- Multiple access points: Share one EFS across apps with isolation

**Estimated Costs** (ap-southeast-2):
- EFS Standard: ~$0.30/GB/month
- Fargate (2 tasks @ 1 vCPU, 2GB): ~$58/month continuous

## Cleanup

```bash
# Delete access point (if exists)
cd terraform
EFS_ID=$(terraform output -raw efs_file_system_id)
ACCESS_POINT_ID=$(aws efs describe-access-points --file-system-id $EFS_ID \
  --query 'AccessPoints[?Tags[?Key==`Name` && Value==`azp-agent-shared-access-point`]].AccessPointId' \
  --output text)
[ ! -z "$ACCESS_POINT_ID" ] && aws efs delete-access-point --access-point-id $ACCESS_POINT_ID

# Stop tasks and destroy infrastructure
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[]' --output text | \
  xargs -I {} aws ecs stop-task --cluster $CLUSTER_NAME --task {}

terraform destroy --auto-approve
```

## Troubleshooting

**Permission denied error**: Expected on first run. Create EFS Access Point using `./fix-efs-permissions.sh`

**Pipeline still fails after access point created**:
- Verify access point has UID/GID 1000: `aws efs describe-access-points --access-point-id $ACCESS_POINT_ID`
- Verify task definition includes accessPointId in authorizationConfig
- Restart tasks to use updated task definition

**Agents not connecting**: Check CloudWatch logs at `/ecs/azp-agent-demo-efs`

**EFS mount failures**: Verify security group allows NFS (2049), IAM permissions, mount targets, and KMS key permissions

## References

- [How to use EFS volumes with non-root user on ECS Fargate](https://medium.com/@viniciuscolutti/how-to-use-efs-volumes-with-non-root-user-on-ecs-fargate-containers-b927e5db46c9) by Vinicius Colutti
- [AWS ECS EFS Volumes Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html)
- [EFS Access Points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html)
- [Stack Overflow: EFS permissions with non-root user](https://stackoverflow.com/questions/65965998/efs-mount-on-ecs-fargate-read-write-permissions-denied-for-non-root-user)

---

*Demo/educational project - use at your own risk*
