variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "be-historic-export"
}

variable "vpc_id" {
  description = "VPC ID for the Fargate task"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the Fargate task (needs internet access for RSS feeds)"
  type        = list(string)
}

variable "fargate_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)"
  type        = string
  default     = "2048" # 2 vCPU
}

variable "fargate_memory" {
  description = "Fargate task memory in MB"
  type        = string
  default     = "8192" # 8 GB
}

variable "ephemeral_storage_gb" {
  description = "Ephemeral storage for Fargate task in GB (max 200)"
  type        = number
  default     = 100 # Room for 60-70 GB XML + processing
}

variable "s3_expiration_days" {
  description = "Days before S3 objects auto-expire"
  type        = number
  default     = 90
}

variable "image_tag" {
  description = "Docker image tag in ECR (use date-based tags since ECR is immutable)"
  type        = string
  default     = "v1"
}
