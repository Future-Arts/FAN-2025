# terraform/modules/storage/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "scraped_data_bucket_name" {
  description = "Name of the S3 bucket for scraped data"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for bucket encryption (null for AES256)"
  type        = string
  default     = null
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "bucket_size_alarm_threshold" {
  description = "Threshold for bucket size alarm in bytes"
  type        = number
  default     = 107374182400  # 100GB
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = null
}
