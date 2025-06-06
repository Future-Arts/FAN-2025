# terraform/variables.tf

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# Add these variables to the END of your existing variables.tf file

# ================================================================
# 3D VISUALIZATION VARIABLES
# ================================================================

variable "enable_3d_optimizations" {
  description = "Enable 3D visualization specific optimizations"
  type        = bool
  default     = false
}

variable "max_nodes_per_website" {
  description = "Maximum number of nodes to process per website for 3D visualization"
  type        = string
  default     = "500"
}

variable "enable_progressive_loading" {
  description = "Enable progressive loading for large datasets"
  type        = bool
  default     = false
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_use_arm64" {
  description = "Use ARM64 Graviton processors for Lambda"
  type        = bool
  default     = true
}

variable "lambda_max_concurrency" {
  description = "Maximum concurrent Lambda executions"
  type        = number
  default     = 10
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = false
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
}

# CORS configuration
variable "cors_origins" {
  description = "Allowed CORS origins for API Gateway"
  type        = list(string)
  default     = ["*"]
}


variable "enable_s3_lifecycle_rules" {
  description = "Enable S3 lifecycle rules"
  type        = bool
  default     = false
}

variable "sqs_alarm_threshold" {
  description = "SQS alarm threshold"
  type        = number
  default     = 100
}

variable "scraping_max_depth" {
  description = "Maximum scraping depth"
  type        = string
  default     = "20"
}

variable "rate_limit_per_domain" {
  description = "Rate limit per domain"
  type        = string
  default     = "10"
}

variable "allowed_domains" {
  description = "Allowed domains list"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Log retention days"
  type        = number
  default     = 14
}

variable "api_rate_limit" {
  description = "API rate limit"
  type        = number
  default     = 5
}

variable "api_burst_limit" {
  description = "API burst limit"
  type        = number
  default     = 10
}

variable "api_monthly_quota" {
  description = "API monthly quota"
  type        = number
  default     = 1000
}

variable "notification_email" {
  description = "Notification email"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL"
  type        = string
  default     = ""
}

# Add these missing variables to your terraform/variables.tf file

# ================================================================
# DYNAMODB CAPACITY VARIABLES
# ================================================================

variable "enable_provisioned_capacity" {
  description = "Enable provisioned capacity for DynamoDB"
  type        = bool
  default     = false
}

variable "read_capacity_units" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 5
}

variable "write_capacity_units" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 5
}

variable "gsi_read_capacity_units" {
  description = "Read capacity units for GSI"
  type        = number
  default     = 5
}

variable "gsi_write_capacity_units" {
  description = "Write capacity units for GSI"
  type        = number
  default     = 5
}

# ================================================================
# DYNAMODB FEATURES
# ================================================================

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB"
  type        = bool
  default     = true
}

variable "enable_autoscaling" {
  description = "Enable autoscaling for DynamoDB"
  type        = bool
  default     = false
}

# ================================================================
# AUTOSCALING VARIABLES
# ================================================================

variable "min_read_capacity_units" {
  description = "Minimum read capacity units for autoscaling"
  type        = number
  default     = 5
}

variable "max_read_capacity_units" {
  description = "Maximum read capacity units for autoscaling"
  type        = number
  default     = 40
}

variable "min_write_capacity_units" {
  description = "Minimum write capacity units for autoscaling"
  type        = number
  default     = 5
}

variable "max_write_capacity_units" {
  description = "Maximum write capacity units for autoscaling"
  type        = number
  default     = 40
}

variable "read_target_utilization" {
  description = "Target utilization for read capacity autoscaling"
  type        = number
  default     = 70
}

variable "write_target_utilization" {
  description = "Target utilization for write capacity autoscaling"
  type        = number
  default     = 70
}

# ================================================================
# COST MONITORING
# ================================================================

variable "enable_cost_monitoring" {
  description = "Enable cost monitoring alarms"
  type        = bool
  default     = false
}

variable "daily_cost_threshold" {
  description = "Daily cost threshold for alarms (USD)"
  type        = number
  default     = 10
}
