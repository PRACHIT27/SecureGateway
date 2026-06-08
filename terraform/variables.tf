variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "securegateway"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "pentest_skip_threshold" {
  description = "Number of HIGH severity SAST findings that triggers fast-block and skips pentest"
  type        = number
  default     = 3
}

variable "sqs_visibility_timeout_sast" {
  description = "SQS visibility timeout in seconds for SAST queue (should exceed max scan time)"
  type        = number
  default     = 300
}

variable "sqs_visibility_timeout_pentest" {
  description = "SQS visibility timeout in seconds for pentest queue"
  type        = number
  default     = 600
}

variable "report_retention_days" {
  description = "Number of days to retain scan reports in S3"
  type        = number
  default     = 30
}

variable "fargate_cpu_sast" {
  description = "CPU units for SAST Fargate task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "fargate_memory_sast" {
  description = "Memory in MB for SAST Fargate task"
  type        = number
  default     = 512
}

variable "fargate_cpu_pentest" {
  description = "CPU units for pentest Fargate task"
  type        = number
  default     = 512
}

variable "fargate_memory_pentest" {
  description = "Memory in MB for pentest Fargate task"
  type        = number
  default     = 1024
}
