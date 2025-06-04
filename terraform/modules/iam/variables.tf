# terraform/modules/iam/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing support"
  type        = bool
  default     = true
}

variable "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID for role assumption"
  type        = string
  default     = "*"  # Will be updated after Cognito pool is created
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Lambda access"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB sitemap table"
  type        = string
}
