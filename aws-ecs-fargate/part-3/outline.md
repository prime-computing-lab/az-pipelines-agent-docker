EFS
Terraform deploy with ECS Fargate with EFS - simple environment with security group and IAM policies.  Do not include efs access points yet.  I will do the access points config via aws cli or the console during the demo to build on the environment deployed by terraform.

2x Azure Pipelines agents to deploy same pipeline used in part-2
Point out EFS considerations:
- Need to create it first
- KMS?
- security group
- access point

Why EFS
- data outlives containers / tasks
- shared
- scalable - storage grows and shrinks automatically
- fully managed - no servers to provision or manage

- performance and cost
    - 2 EFS main flavours: gen purpose, max I/O
    - througput: how fast canyou move data? default bursting mode - auto scaling - more data faster throughput vs provisioned
cost optimization
    - share one efs system cross apps using access points to keep data separate
    - lifecycle mgt - move old unused files to cheaper storage tier
    - use one zone storage for workloads without multi AZ needs
    
- security - unlike ebs that requires root access. EFS does not require it.  in fact there is data isolation with efs access points.  

Using combination of aws console and vs code/terminal, demo how to implement efs access points.  Another project perhaps that can access the same efs folder, and then after introducing efs access point, show that now it can only access it's specific folder.

Defense in depth
1. Network layer - control traffic with security groups
2. Identity layer - manage access with IAM policies
3. Application layer - isolate data with efs access points - locking it down to specific folder

Build on the demo environment from part 2 - 
/Users/kingadmin/Documents/Git/az-pipelines-agent-docker-priv/aws-ecs-fargate/part-2/azure-pipelines
/Users/kingadmin/Documents/Git/az-pipelines-agent-docker-priv/aws-ecs-fargate/part-2/docker
/Users/kingadmin/Documents/Git/az-pipelines-agent-docker-priv/aws-ecs-fargate/part-2/terraform
/Users/kingadmin/Documents/Git/az-pipelines-agent-docker-priv/aws-ecs-fargate/part-2/build-demo-env.sh

Build the configuration in the demo environment based on the different aspects of EFS in relation to ECS Fargate - as discussed in aws docs
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-volumes.html
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/efs-best-practices.html
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specify-efs-config.html
https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tutorial-efs-volumes.html
