#!/bin/bash

# Exit on error
set -e

export AWS_PROFILE="your-aws-profile"
source .env
aws sso login --sso-session your-sso-session

echo "========================================="
echo "Updating Task Definition with EFS Access Point"
echo "========================================="
echo ""

# Get values from Terraform output
cd terraform
TASK_DEF_FAMILY=$(terraform output -raw task_definition_family)
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
EFS_ID=$(terraform output -raw efs_file_system_id)
cd ..

echo "Task Definition Family: $TASK_DEF_FAMILY"
echo "Cluster Name: $CLUSTER_NAME"
echo "EFS ID: $EFS_ID"
echo ""

# Get the access point ID
ACCESS_POINT_ID=$(aws efs describe-access-points \
  --file-system-id $EFS_ID \
  --query 'AccessPoints[?Tags[?Key==`Name` && Value==`azp-agent-shared-access-point`]].AccessPointId' \
  --output text)

if [ -z "$ACCESS_POINT_ID" ]; then
  echo "ERROR: Access point not found!"
  echo "Please run ./fix-efs-permissions.sh first to create the access point."
  exit 1
fi

echo "Access Point ID: $ACCESS_POINT_ID"
echo ""

# Get current task definition
echo "Retrieving current task definition..."
CURRENT_TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_FAMILY)

# Extract the task definition and clean up runtime-generated fields
echo "Preparing new task definition revision..."
NEW_TASK_DEF=$(echo $CURRENT_TASK_DEF | jq '.taskDefinition |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  # Update the EFS volume configuration to include access point INSIDE authorizationConfig
  .volumes[0].efsVolumeConfiguration.authorizationConfig.accessPointId = "'$ACCESS_POINT_ID'" |
  # Root directory should be "/" when using access point (access point defines the root)
  .volumes[0].efsVolumeConfiguration.rootDirectory = "/"
')

# Save to temporary file
TEMP_FILE=$(mktemp)
echo $NEW_TASK_DEF > $TEMP_FILE

echo "Registering new task definition revision with access point..."
echo ""

# Register new task definition
NEW_REVISION=$(aws ecs register-task-definition --cli-input-json file://$TEMP_FILE)
NEW_TASK_DEF_ARN=$(echo $NEW_REVISION | jq -r '.taskDefinition.taskDefinitionArn')
NEW_REVISION_NUM=$(echo $NEW_REVISION | jq -r '.taskDefinition.revision')

# Clean up temp file
rm $TEMP_FILE

echo "✓ New task definition registered!"
echo ""
echo "Task Definition ARN: $NEW_TASK_DEF_ARN"
echo "Revision: $NEW_REVISION_NUM"
echo ""

echo "========================================="
echo "Task Definition Updated Successfully!"
echo "========================================="
echo ""
echo "Changes made:"
echo "  - Added EFS Access Point ID: $ACCESS_POINT_ID"
echo "  - Set root directory to \"/\" (access point defines the root)"
echo ""
echo "Next Steps:"
echo ""
echo "1. Stop current running tasks:"
echo "   TASKS=\$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns[]' --output text)"
echo "   for TASK in \$TASKS; do"
echo "     aws ecs stop-task --cluster $CLUSTER_NAME --task \$TASK"
echo "   done"
echo ""
echo "2. Start new tasks with updated definition:"
echo "   Run the relevant section from build-demo-env.sh or manually:"
echo "   aws ecs run-task \\"
echo "     --cluster $CLUSTER_NAME \\"
echo "     --task-definition $NEW_TASK_DEF_ARN \\"
echo "     --launch-type FARGATE \\"
echo "     --platform-version 1.4.0 \\"
echo "     --network-configuration \"awsvpcConfiguration={subnets=[SUBNET],securityGroups=[SG],assignPublicIp=ENABLED}\""
echo ""
echo "3. Verify agents appear in Azure DevOps"
echo ""
echo "4. Re-run the pipeline: azure-pipelines/pipeline-shared-efs-storage.yml"
echo ""
echo "The permission denied error should now be resolved!"
echo ""
