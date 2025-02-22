terraform {
  backend "s3" {
    bucket         = "terraform-state-fan2025"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "Developer-024611159954"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-fan2025"

  lifecycle {
    prevent_destroy = true
  }
}

# Enable Versioning
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB for State Locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Variables
variable "environment" {
  type    = string
  default = "prod"
}

# SQS Queues
resource "aws_sqs_queue" "scraping_dlq" {
  name                      = "url-scraping-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "image_dlq" {
  name                      = "image-download-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "lambda-scraper-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}

# Main SQS Queues
resource "aws_sqs_queue" "scraping_queue" {
  name                      = "url-scraping-queue"
  visibility_timeout_seconds = 900  # 15 minutes
  message_retention_seconds = 1209600  # 14 days
  delay_seconds             = 0
  receive_wait_time_seconds = 20  # Enable long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scraping_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "image_queue" {
  name                      = "image-download-queue"
  visibility_timeout_seconds = 900
  message_retention_seconds = 1209600
  delay_seconds             = 0
  receive_wait_time_seconds = 20
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })
}

# Lambda Function
resource "aws_lambda_function" "page_scraper" {
  filename         = "${path.module}/../infrastructure/lambda_function.zip"
  function_name    = "page-scraper"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "pagescraper.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300  # 5 minutes
  memory_size     = 512

  source_code_hash = filebase64sha256("${path.module}/../infrastructure/lambda_function.zip")

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      MAX_DEPTH             = 3
      RATE_LIMIT_PER_DOMAIN = 10
      ALLOWED_DOMAINS       = "[]"
      URL_QUEUE_URL         = aws_sqs_queue.scraping_queue.url
      IMAGE_QUEUE_URL       = aws_sqs_queue.image_queue.url
    }
  }

  #reserved_concurrent_executions = 10
}

# Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.page_scraper.function_name}"
  retention_in_days = 14
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-scraper-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda IAM Policy
resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "lambda-scraper-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.scraping_queue.arn,
          aws_sqs_queue.image_queue.arn,
          aws_sqs_queue.scraping_dlq.arn,
          aws_sqs_queue.image_dlq.arn,
          aws_sqs_queue.lambda_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
        ]
      }
    ]
  })
}

# Lambda SQS Trigger
resource "aws_lambda_event_source_mapping" "scraping_queue_trigger" {
  event_source_arn = aws_sqs_queue.scraping_queue.arn
  function_name    = aws_lambda_function.page_scraper.arn
  batch_size       = 1
  
  maximum_batching_window_in_seconds = 0

  scaling_config {
    maximum_concurrency = 10
  }
}

# API Gateway CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/scraping-api"
  retention_in_days = 14
}

# API Gateway Role for SQS
resource "aws_iam_role" "api_gateway_sqs" {
  name = "api-gateway-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# API Gateway policy for SQS access
resource "aws_iam_role_policy" "api_gateway_sqs" {
  name = "api-gateway-sqs-policy"
  role = aws_iam_role.api_gateway_sqs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.scraping_queue.arn
        ]
      }
    ]
  })
}

# Lambda execution role policy for SQS
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "lambda-sqs-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.scraping_queue.arn,
          aws_sqs_queue.image_queue.arn,
          aws_sqs_queue.lambda_dlq.arn,
          aws_sqs_queue.scraping_dlq.arn,
          aws_sqs_queue.image_dlq.arn
        ]
      }
    ]
  })
}


# API Gateway
resource "aws_api_gateway_rest_api" "scraping_api" {
  name        = "scraping-api"
  description = "API for adding URLs to scraping queue"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Key
resource "aws_api_gateway_api_key" "scraping_api_key" {
  name = "scraping-api-key"
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "scraping_api_usage_plan" {
  name = "scraping-api-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.scraping_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 1000
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }
}

# Key association
resource "aws_api_gateway_usage_plan_key" "scraping_api_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.scraping_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.scraping_api_usage_plan.id
}

resource "aws_api_gateway_resource" "scrape" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  parent_id   = aws_api_gateway_rest_api.scraping_api.root_resource_id
  path_part   = "scrape"
}

# API method
resource "aws_api_gateway_method" "scrape_post" {
  rest_api_id      = aws_api_gateway_rest_api.scraping_api.id
  resource_id      = aws_api_gateway_resource.scrape.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true

  request_validator_id = aws_api_gateway_request_validator.validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.scrape_request_model.name
  }
}

# Request validator
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "scrape-endpoint-validator"
  rest_api_id                = aws_api_gateway_rest_api.scraping_api.id
  validate_request_body      = true
  validate_request_parameters = true
}

# Request model
resource "aws_api_gateway_model" "scrape_request_model" {
  rest_api_id  = aws_api_gateway_rest_api.scraping_api.id
  name         = "ScrapeRequestModel"
  description  = "JSON Schema for scrape endpoint"
  content_type = "application/json"

  schema = jsonencode({
    type = "object"
    required = ["page_url"]
    properties = {
      page_url = {
        type = "string"
        pattern = "^.*$"  # Accept any string
      }
      store_images = {
        type = "boolean"
        default = false
      }
    }
  })
}

# API Gateway integration to use the role
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.scraping_api.id
  resource_id             = aws_api_gateway_resource.scrape.id
  http_method             = aws_api_gateway_method.scrape_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.api_gateway_sqs.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.scraping_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&MessageBody={
  "page_url": "$input.path('$.page_url')",
  "store_images": $input.path('$.store_images')
}
EOF
  }
}

# Method response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response
resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "message": "URL added to scraping queue",
  "status": "success",
  "requestId": "$context.requestId"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.sqs_integration]
}

# API Gateway deployment and stage
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id

  depends_on = [
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration_response.integration_response
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.scrape,
      aws_api_gateway_method.scrape_post,
      aws_api_gateway_integration.sqs_integration
    ]))
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId     = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      requestTime  = "$context.requestTime"
      httpMethod   = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status       = "$context.status"
      protocol     = "$context.protocol"
      responseLength = "$context.responseLength"
      apiKey      = "$context.identity.apiKey"
    })
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Outputs
output "api_endpoint" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}${aws_api_gateway_stage.prod.stage_name}/scrape"
}

output "scraping_queue_url" {
  value = aws_sqs_queue.scraping_queue.url
}

output "image_queue_url" {
  value = aws_sqs_queue.image_queue.url
}

output "api_key" {
  value     = aws_api_gateway_api_key.scraping_api_key.value
  sensitive = true
}

output "dlq_urls" {
  value = {
    scraping = aws_sqs_queue.scraping_dlq.url
    image    = aws_sqs_queue.image_dlq.url
    lambda   = aws_sqs_queue.lambda_dlq.url
  }
}