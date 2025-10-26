variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "azp-agent-cluster-efs-demo"
}

variable "task_cpu" {
  description = "Task CPU units"
  type        = string
  default     = "1024"
}

variable "task_memory" {
  description = "Task memory in MB"
  type        = string
  default     = "2048"
}

variable "operating_system_family" {
  description = "Operating system family for the task"
  type        = string
  default     = "LINUX"
}

variable "cpu_architecture" {
  description = "CPU architecture for the task"
  type        = string
  default     = "ARM64"
}

variable "agent_names" {
  description = "List of Azure Pipeline agent names"
  type        = list(string)
  default     = ["azp-agent-efs-1", "azp-agent-efs-2"]
}

# Azure Pipelines configuration
variable "azp_url" {
  description = "Azure DevOps organization URL"
  type        = string
  sensitive   = true
}

variable "azp_token" {
  description = "Azure DevOps Personal Access Token"
  type        = string
  sensitive   = true
}

variable "azp_pool" {
  description = "Azure Pipelines agent pool name"
  type        = string
}
