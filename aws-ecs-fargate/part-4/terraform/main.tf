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
  name                 = "azp-agent-aws-ecs-fargate-bind-mounts"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "azp-agent-aws-ecs-fargate-bind-mounts"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Secrets Manager - Azure Pipelines Credentials
resource "aws_secretsmanager_secret" "azp_credentials" {
  name                    = "azp-agent-credentials-bind-mounts"
  description             = "Azure Pipelines agent credentials for bind mounts demo"
  recovery_window_in_days = 0

  tags = {
    Name        = "azp-agent-credentials-bind-mounts"
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

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRoleDemoBindMounts"

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
    Name        = "ecsTaskExecutionRoleDemoBindMounts"
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
  name              = "/ecs/azp-agent-demo-bind-mounts"
  retention_in_days = 7

  tags = {
    Name        = "azp-agent-logs-bind-mounts"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ECS Task Definition with Bind Mount Configuration
resource "aws_ecs_task_definition" "azp_agent" {
  family                   = "azp-agent-demo-bind-mounts"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  # Bind Mount Volume Configuration
  # Bind mounts are host-based volumes that exist on the Fargate infrastructure
  # They are tied to the lifecycle of the container/task
  # Suitable for temporary storage, not for persistent data across task restarts
  volume {
    name = "bind-mount-storage"
    # No additional configuration needed - creates an empty directory on the host
  }

  container_definitions = jsonencode([
    for agent_name in var.agent_names : {
      name      = agent_name
      image     = "${aws_ecr_repository.azp_agent.repository_url}:latest"
      essential = true

      # Mount the bind mount volume
      mountPoints = [
        {
          sourceVolume  = "bind-mount-storage"
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
    Name        = "azp-agent-demo-bind-mounts"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
