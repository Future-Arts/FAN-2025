# terraform/modules/lambda-scraper/variables.tf

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  type        = string
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
  default     = "pagescraper.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "use_arm64" {
  description = "Use ARM64 Graviton processors for cost optimization"
  type        = bool
  default     = true
}

variable "source_path" {
  description = "Path to the Lambda source code directory"
  type        = string
}

variable "build_script_path" {
  description = "Path to the build script"
  type        = string
}

variable "output_path" {
  description = "Output path for the Lambda deployment package"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "enable_json_logging" {
  description = "Enable JSON format logging (2024+ feature)"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "dlq_arn" {
  description = "Dead letter queue ARN"
  type        = string
  default     = null
}

variable "vpc_config" {
  description = "VPC configuration for Lambda"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "event_source_arn" {
  description = "ARN of the event source (SQS queue)"
  type        = string
  default     = null
}

variable "batch_size" {
  description = "Maximum number of records in each batch"
  type        = number
  default     = 1
}

variable "max_batching_window" {
  description = "Maximum batching window in seconds"
  type        = number
  default     = 0
}

variable "max_concurrency" {
  description = "Maximum concurrent executions"
  type        = number
  default     = 10
}
