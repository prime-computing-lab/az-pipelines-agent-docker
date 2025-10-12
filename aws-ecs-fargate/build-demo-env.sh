# Configure your AWS profile
export AWS_PROFILE="${AWS_PROFILE:-default}"

# Source environment variables from .env file
source ../.env

# Login to AWS (comment out if not using SSO)
# aws sso login --sso-session your-sso-session

# build the demo environment
cd terraform
terraform init
terraform apply --auto-approve


# build the docker image
cd ../docker
IMAGE_TAG="azp-agent-aws-ecs-fargate"
docker build -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${IMAGE_TAG} .
# authenticate the docker client to ECR to push image
aws ecr get-login-password | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
# push the image to ECR
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${IMAGE_TAG}

# start the ECS Fargate task
TASK_DEF_ARN=$(terraform -chdir=../terraform output -raw task_definition_arn)
CLUSTER_NAME=$(terraform -chdir=../terraform output -raw ecs_cluster_name)

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)

# Get subnets from default VPC
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')

# Get default security group for the VPC
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"

# Get status of the task (including stopped tasks)
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --desired-status RUNNING --query 'taskArns[0]' --output text)
if [ "$TASK_ARN" == "None" ] || [ -z "$TASK_ARN" ]; then
  TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --desired-status STOPPED --query 'taskArns[0]' --output text)
fi
aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].{TaskArn:taskArn,Status:lastStatus,DesiredStatus:desiredStatus,Cpu:cpu,Memory:memory,StoppedReason:stoppedReason,Containers:containers[0].{Name:name,Status:lastStatus,ExitCode:exitCode,Reason:reason}}'

# cleanup the demo environment
terraform destroy --auto-approve