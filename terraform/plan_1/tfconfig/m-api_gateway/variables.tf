# terraform/modules/api-gateway/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "sqs_queue_url" {
  description = "URL of the SQS queue for integration"
  type        = string
}

variable "sqs_integration_role_arn" {
  description = "ARN of the IAM role for SQS integration"
  type        = string
}

variable "enable_api_key" {
  description = "Enable API key authentication"
  type        = bool
  default     = true
}

variable "enable_usage_plan" {
  description = "Enable usage plan for rate limiting"
  type        = bool
  default     = true
}

variable "enable_cors" {
  description = "Enable CORS support"
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Request rate limit per second"
  type        = number
  default     = 5
}

variable "burst_limit" {
  description = "Request burst limit"
  type        = number
  default     = 10
}

variable "monthly_quota" {
  description = "Monthly request quota"
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

