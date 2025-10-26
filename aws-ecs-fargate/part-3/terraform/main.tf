terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Get default VPC and subnets for the demo
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ECR Repository
resource "aws_ecr_repository" "azp_agent" {
  name                 = "azp-agent-aws-ecs-fargate-efs"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "azp-agent-aws-ecs-fargate-efs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Secrets Manager - Azure Pipelines Credentials
resource "aws_secretsmanager_secret" "azp_credentials" {
  name                    = "azp-agent-credentials-efs"
  description             = "Azure Pipelines agent credentials for EFS demo"
  recovery_window_in_days = 0

  tags = {
    Name        = "azp-agent-credentials-efs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "azp_credentials" {
  secret_id = aws_secretsmanager_secret.azp_credentials.id
  secret_string = jsonencode({
    AZP_TOKEN = var.azp_token
    AZP_POOL  = var.azp_pool
    AZP_URL   = var.azp_url
  })
}

# KMS Key for EFS Encryption
resource "aws_kms_key" "efs_encryption" {
  description             = "KMS key for EFS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "efs-encryption-key"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "efs_encryption" {
  name          = "alias/efs-encryption"
  target_key_id = aws_kms_key.efs_encryption.key_id
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "efs-sg-demo"
  description = "Security group for EFS mount targets"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "efs-sg-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# EFS File System
resource "aws_efs_file_system" "shared_storage" {
  creation_token = "azp-agent-efs-demo"
  encrypted      = true
  kms_key_id     = aws_kms_key.efs_encryption.arn

  # Performance mode: generalPurpose is suitable for most workloads
  # For higher throughput workloads, consider maxIO
  performance_mode = "generalPurpose"

  # Throughput mode: bursting scales with file system size
  # For consistent throughput, use provisioned mode
  throughput_mode = "bursting"

  # Lifecycle policy to transition files to IA storage class
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  # Lifecycle policy to transition files from IA back to standard
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name        = "azp-agent-efs-demo"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# EFS Mount Target (single AZ for cost optimization)
resource "aws_efs_mount_target" "shared_storage" {
  file_system_id  = aws_efs_file_system.shared_storage.id
  subnet_id       = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.efs.id]
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRoleDemoEFS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ecsTaskExecutionRoleDemoEFS"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "secrets_access" {
  name = "secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.azp_credentials.arn
      }
    ]
  })
}

# Policy for EFS access (needed for IAM-based EFS volume mounting)
# ClientRootAccess may be required to prevent root squashing.
# Reference: https://docs.aws.amazon.com/efs/latest/ug/iam-access-control-nfs-efs.html
# See also: https://stackoverflow.com/questions/65965998/efs-mount-on-ecs-fargate-read-write-permissions-denied-for-non-root-user
resource "aws_iam_role_policy" "efs_access" {
  name = "efs-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = aws_efs_file_system.shared_storage.arn
      }
    ]
  })
}

# IAM Role for ECS Tasks (required for EFS IAM authorization, even with no additional permissions)
resource "aws_iam_role" "ecs_task" {
  name = "ecsTaskRoleDemoEFS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ecsTaskRoleDemoEFS"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "demo" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = var.cluster_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "azp_agent" {
  name              = "/ecs/azp-agent-demo-efs"
  retention_in_days = 7

  tags = {
    Name        = "azp-agent-logs-efs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ECS Task Definition with EFS Volume Configuration
resource "aws_ecs_task_definition" "azp_agent" {
  family                   = "azp-agent-demo-efs"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  # EFS Volume Configuration (without access point initially)
  volume {
    name = "efs-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.shared_storage.id
      transit_encryption = "ENABLED"

      authorization_config {
        iam = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    for agent_name in var.agent_names : {
      name      = agent_name
      image     = "${aws_ecr_repository.azp_agent.repository_url}:latest"
      essential = true

      # Mount the EFS volume
      mountPoints = [
        {
          sourceVolume  = "efs-storage"
          containerPath = "/shared-storage"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "AZP_AGENT_NAME"
          value = agent_name
        }
      ]

      secrets = [
        {
          name      = "AZP_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.azp_credentials.arn}:AZP_TOKEN::"
        },
        {
          name      = "AZP_POOL"
          valueFrom = "${aws_secretsmanager_secret.azp_credentials.arn}:AZP_POOL::"
        },
        {
          name      = "AZP_URL"
          valueFrom = "${aws_secretsmanager_secret.azp_credentials.arn}:AZP_URL::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.azp_agent.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = agent_name
        }
      }
    }
  ])

  tags = {
    Name        = "azp-agent-demo-efs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
