output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.azp_agent.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.demo.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.demo.arn
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.azp_agent.arn
}

output "task_definition_family" {
  description = "ECS task definition family"
  value       = aws_ecs_task_definition.azp_agent.family
}

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.shared_storage.id
}

output "efs_file_system_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.shared_storage.arn
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.shared_storage.dns_name
}

output "efs_security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

output "kms_key_arn" {
  description = "KMS key ARN for EFS encryption"
  value       = aws_kms_key.efs_encryption.arn
}

output "kms_key_id" {
  description = "KMS key ID for EFS encryption"
  value       = aws_kms_key.efs_encryption.key_id
}

output "vpc_id" {
  description = "VPC ID where resources are deployed"
  value       = data.aws_vpc.default.id
}

output "subnet_id" {
  description = "Subnet ID where mount target is created"
  value       = data.aws_subnets.default.ids[0]
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.azp_agent.name
}
