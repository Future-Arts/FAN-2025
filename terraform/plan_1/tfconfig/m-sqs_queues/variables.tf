# terraform/modules/sqs-queues/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the main queue"
  type        = number
  default     = 900  # 15 minutes
}

variable "message_retention_seconds" {
  description = "Message retention period for the main queue"
  type        = number
  default     = 1209600  # 14 days
}

variable "delay_seconds" {
  description = "Delay seconds for the main queue"
  type        = number
  default     = 0
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time"
  type        = number
  default     = 20
}

variable "max_receive_count" {
  description = "Maximum receive count before moving to DLQ"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for DLQ"
  type        = number
  default     = 1209600  # 14 days
}

variable "dlq_visibility_timeout_seconds" {
  description = "Visibility timeout for DLQ"
  type        = number
  default     = 300
}

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "queue_depth_alarm_threshold" {
  description = "Threshold for queue depth alarm"
  type        = number
  default     = 100
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = null
}
