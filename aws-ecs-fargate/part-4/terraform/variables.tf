variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "my-demo-cluster-bind-mounts"
}

variable "azp_token" {
  description = "Azure Pipelines Personal Access Token"
  type        = string
  sensitive   = true
}

variable "azp_pool" {
  description = "Azure Pipelines Agent Pool name"
  type        = string
}

variable "azp_url" {
  description = "Azure DevOps organization URL"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for the ECS task (1024 = 1 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory for the ECS task in MB"
  type        = string
  default     = "512"
}

variable "cpu_architecture" {
  description = "CPU architecture for the ECS task (X86_64 or ARM64)"
  type        = string
  default     = "ARM64"
}

variable "operating_system_family" {
  description = "Operating system family for the ECS task (LINUX or WINDOWS_SERVER_*)"
  type        = string
  default     = "LINUX"
}

variable "agent_names" {
  description = "List of Azure Pipelines agent names"
  type        = list(string)
  default     = ["azp-agent-1-bind-mounts", "azp-agent-2-bind-mounts"]
}
