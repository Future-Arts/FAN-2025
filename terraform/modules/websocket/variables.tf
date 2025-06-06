# terraform/modules/websocket/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "websocket_lambda_role_arn" {
  description = "ARN of the IAM role for WebSocket Lambda functions"
  type        = string
}

variable "websocket_package_path" {
  description = "Path to the WebSocket Lambda deployment package"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "stage_name" {
  description = "WebSocket API stage name"
  type        = string
  default     = "prod"
}
