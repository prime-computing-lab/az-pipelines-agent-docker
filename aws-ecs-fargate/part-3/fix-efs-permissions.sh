#!/bin/bash

# Exit on error
set -e

export AWS_PROFILE="your-aws-profile"
source .env
aws sso login --sso-session your-sso-session

echo "========================================="
echo "Fixing EFS Permissions with Access Point"
echo "========================================="
echo ""
echo "Problem: Non-root user (agent) cannot create subdirectories in EFS mounted volume"
echo "Solution: Create an EFS Access Point with matching UID/GID (1000:1000)"
echo ""
echo "Reference:"
echo "  - https://stackoverflow.com/questions/65965998/efs-mount-on-ecs-fargate-read-write-permissions-denied-for-non-root-user"
echo "  - https://medium.com/@viniciuscolutti/how-to-use-efs-volumes-with-non-root-user-on-ecs-fargate-containers-b927e5db46c9"
echo ""

# Get EFS ID from Terraform output
cd terraform
EFS_ID=$(terraform output -raw efs_file_system_id)
echo "EFS File System ID: $EFS_ID"
echo ""

# Check if access point already exists
EXISTING_AP=$(aws efs describe-access-points \
  --file-system-id $EFS_ID \
  --query 'AccessPoints[?Tags[?Key==`Name` && Value==`azp-agent-shared-access-point`]].AccessPointId' \
  --output text)

if [ ! -z "$EXISTING_AP" ]; then
  echo "Access point already exists: $EXISTING_AP"
  echo "To recreate, first delete it with:"
  echo "  aws efs delete-access-point --access-point-id $EXISTING_AP"
  echo ""
  ACCESS_POINT_ID=$EXISTING_AP
else
  echo "Creating EFS Access Point..."
  echo "  - POSIX User: UID=1000, GID=1000 (matches 'agent' user in container)"
  echo "  - Root Directory: /agent-storage"
  echo "  - Permissions: 755 (owner can read/write/execute, others can read/execute)"
  echo ""

  # Create access point for shared agent storage
  ACCESS_POINT_OUTPUT=$(aws efs create-access-point \
    --file-system-id $EFS_ID \
    --posix-user Uid=1000,Gid=1000 \
    --root-directory "Path=/agent-storage,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
    --tags Key=Name,Value=azp-agent-shared-access-point Key=Environment,Value=demo Key=ManagedBy,Value=manual)

  ACCESS_POINT_ID=$(echo $ACCESS_POINT_OUTPUT | jq -r '.AccessPointId')
  echo "✓ Access Point created: $ACCESS_POINT_ID"
fi

cd ..

echo ""
echo "========================================="
echo "Access Point Created Successfully!"
echo "========================================="
echo ""
echo "Access Point ID: $ACCESS_POINT_ID"
echo ""
echo "How it works:"
echo "  1. EFS Access Point enforces UID/GID 1000:1000 for all file operations"
echo "  2. This matches the 'agent' user in the Docker container"
echo "  3. Root directory '/agent-storage' is created with proper ownership"
echo "  4. Non-root user can now create subdirectories (e.g., /shared-storage/artifacts)"
echo ""
echo "Next Steps:"
echo "  1. Run ./update-task-with-access-point.sh to update the task definition"
echo "  2. Stop current tasks: aws ecs stop-task --cluster \$CLUSTER_NAME --task \$TASK_ARN"
echo "  3. Start new tasks with updated task definition"
echo "  4. Re-run the pipeline: azure-pipelines/pipeline-shared-efs-storage.yml"
echo ""
echo "The permission denied error should now be resolved!"
echo ""
