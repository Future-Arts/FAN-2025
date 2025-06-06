# terraform/modules/monitoring/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Resource names for monitoring
variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table to monitor"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function to monitor"
  type        = string
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue to monitor"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to monitor"
  type        = string
}

variable "api_gateway_name" {
  description = "Name of the API Gateway to monitor"
  type        = string
}

# Notification configuration
variable "notification_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}
