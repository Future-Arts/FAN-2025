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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  # Using environment credentials instead of profile
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

# DynamoDB Table for Sitemap Storage
resource "aws_dynamodb_table" "sitemap_storage" {
  name           = "website-sitemaps"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "website_domain"

  attribute {
    name = "website_domain"
    type = "S"
  }

  tags = {
    Name        = "Website Sitemaps"
    Environment = var.environment
  }
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "scraping_dlq" {
  name                      = "url-scraping-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "lambda-scraper-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}

# Main SQS Queue
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

# S3 Bucket for scraped data
resource "aws_s3_bucket" "scraped_data" {
  bucket = "artist-scraped-data"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "scraped_data_versioning" {
  bucket = aws_s3_bucket.scraped_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scraped_data_encryption" {
  bucket = aws_s3_bucket.scraped_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Create requirements.txt file for Lambda dependencies
resource "local_file" "requirements" {
  content = <<EOF
requests==2.31.0
beautifulsoup4==4.12.2
EOF
  filename = "${path.module}/../infrastructure/requirements.txt"
}

# Ensure infrastructure directory exists
resource "null_resource" "create_infrastructure_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../infrastructure"
  }
}

# Build the Lambda deployment package using external script
resource "null_resource" "lambda_package" {
  triggers = {
    # Rebuild when Python code or requirements change
    python_code = fileexists("${path.module}/../infrastructure/pagescraper.py") ? filebase64sha256("${path.module}/../infrastructure/pagescraper.py") : "none"
    requirements = local_file.requirements.content
    build_script = fileexists("${path.module}/build_lambda.sh") ? filebase64sha256("${path.module}/build_lambda.sh") : "none"
  }

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/build_lambda.sh && ${path.module}/build_lambda.sh"
  }

  depends_on = [
    local_file.requirements,
    null_resource.create_infrastructure_dir
  ]
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

  source_code_hash = fileexists("${path.module}/../infrastructure/lambda_function.zip") ? filebase64sha256("${path.module}/../infrastructure/lambda_function.zip") : null

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      MAX_DEPTH             = 3
      RATE_LIMIT_PER_DOMAIN = 10
      ALLOWED_DOMAINS       = "[]"
      URL_QUEUE_URL         = aws_sqs_queue.scraping_queue.url
      SITEMAP_TABLE_NAME    = aws_dynamodb_table.sitemap_storage.name
    }
  }

  depends_on = [
    null_resource.lambda_package,
    aws_cloudwatch_log_group.lambda_logs
  ]

  #reserved_concurrent_executions = 10
}

# Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/page-scraper"
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

# Lambda IAM Policy for basic execution
resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "lambda-scraper-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Lambda IAM Policy for SQS access
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
          aws_sqs_queue.lambda_dlq.arn,
          aws_sqs_queue.scraping_dlq.arn
        ]
      }
    ]
  })
}

# Lambda IAM Policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-sitemap-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.sitemap_storage.arn
        ]
      }
    ]
  })
}

# Lambda IAM Policy for S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.scraped_data.arn}/*"
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

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "scrape_options" {
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  resource_id   = aws_api_gateway_resource.scrape.id
  http_method   = "OPTIONS"
  authorization = "NONE"
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
    }
  })
}

# OPTIONS method integration (Mock integration for CORS)
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# OPTIONS method response with CORS headers
resource "aws_api_gateway_method_response" "options_response_200" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# OPTIONS integration response with CORS headers
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options.http_method
  status_code = aws_api_gateway_method_response.options_response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,x-api-key'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.options_integration]
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
  "page_url": "$input.path('$.page_url')"
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

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

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

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

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
    aws_api_gateway_integration_response.integration_response,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration_response.options_integration_response
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.scrape,
      aws_api_gateway_method.scrape_post,
      aws_api_gateway_method.scrape_options,
      aws_api_gateway_integration.sqs_integration,
      aws_api_gateway_integration.options_integration
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
  value = "https://${aws_api_gateway_rest_api.scraping_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/scrape"
}

output "scraping_queue_url" {
  value = aws_sqs_queue.scraping_queue.url
}

output "api_key" {
  value     = aws_api_gateway_api_key.scraping_api_key.value
  sensitive = true
}

output "dlq_urls" {
  value = {
    scraping = aws_sqs_queue.scraping_dlq.url
    lambda   = aws_sqs_queue.lambda_dlq.url
  }
}

output "sitemap_table_name" {
  value = aws_dynamodb_table.sitemap_storage.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.scraped_data.id
}
