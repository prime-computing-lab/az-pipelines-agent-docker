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

# ECR Repository
resource "aws_ecr_repository" "azp_agent" {
  name                 = "azp-agent-aws-ecs-fargate-ebs"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "azp-agent-aws-ecs-fargate-ebs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Secrets Manager - Azure Pipelines Credentials
resource "aws_secretsmanager_secret" "azp_credentials" {
  name                    = "azp-agent-credentials-ebs"
  description             = "Azure Pipelines agent credentials for EBS demo"
  recovery_window_in_days = 0

  tags = {
    Name        = "azp-agent-credentials-ebs"
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

# KMS Key for EBS Volume Encryption
resource "aws_kms_key" "ebs_encryption" {
  description             = "KMS key for ECS EBS volume encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "ecs-ebs-encryption-key"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "ebs_encryption" {
  name          = "alias/ecs-ebs-encryption"
  target_key_id = aws_kms_key.ebs_encryption.key_id
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRoleDemoEBS"

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
    Name        = "ecsTaskExecutionRoleDemoEBS"
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

# Additional policy for KMS access (for EBS encryption)
resource "aws_iam_role_policy" "kms_access" {
  name = "kms-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = aws_kms_key.ebs_encryption.arn
      }
    ]
  })
}

# IAM Role for ECS Infrastructure (required for managed EBS volumes)
resource "aws_iam_role" "ecs_infrastructure" {
  name = "ecsInfrastructureRoleDemoEBS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ecsInfrastructureRoleDemoEBS"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Attach AWS managed policy for ECS infrastructure (EBS volumes)
resource "aws_iam_role_policy_attachment" "ecs_infrastructure_volumes" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}

# Additional policy for KMS access (for EBS encryption)
resource "aws_iam_role_policy" "ecs_infrastructure_kms" {
  name = "ecs-infrastructure-kms-policy"
  role = aws_iam_role.ecs_infrastructure.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.ebs_encryption.arn
      }
    ]
  })
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
  name              = "/ecs/azp-agent-demo-ebs"
  retention_in_days = 7

  tags = {
    Name        = "azp-agent-logs-ebs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ECS Task Definition with EBS Volume Configuration
resource "aws_ecs_task_definition" "azp_agent" {
  family                   = "azp-agent-demo-ebs"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  # EBS Volume Configuration
  volume {
    name = "shared-volume"

    configure_at_launch = true
  }

  container_definitions = jsonencode([
    for agent_name in var.agent_names : {
      name      = agent_name
      image     = "${aws_ecr_repository.azp_agent.repository_url}:latest"
      essential = true

      # Mount the EBS volume
      mountPoints = [
        {
          sourceVolume  = "shared-volume"
          containerPath = "/shared-volume"
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
    Name        = "azp-agent-demo-ebs"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
