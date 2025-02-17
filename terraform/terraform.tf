terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "Developer-024611159954"
}

# SQS
resource "aws_sqs_queue" "scraping_queue" {
  name                      = "url-scraping-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds = 1209600  # 14 days
  delay_seconds             = 0
  receive_wait_time_seconds = 20  # Enable long polling
}

resource "aws_sqs_queue" "image_queue" {
  name                      = "image-download-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds = 1209600
  delay_seconds             = 0
  receive_wait_time_seconds = 20  # Enable long polling
}

# API Gateway
resource "aws_api_gateway_rest_api" "scraping_api" {
  name        = "scraping-api"
  description = "API for adding URLs to scraping queue"
}

resource "aws_api_gateway_resource" "scrape" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  parent_id   = aws_api_gateway_rest_api.scraping_api.root_resource_id
  path_part   = "scrape"
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

# IAM
resource "aws_iam_role" "api_gateway_role" {
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

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "api-gateway-sqs-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.scraping_queue.arn,
          aws_sqs_queue.image_queue.arn
        ]
      }
    ]
  })
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

# validator
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "scrape-endpoint-validator"
  rest_api_id                = aws_api_gateway_rest_api.scraping_api.id
  validate_request_body      = true
  validate_request_parameters = true
}

# model
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
        pattern = "^.*$"
      }
      store_images = {
        type = "boolean"
        default = false
      }
    }
  })
}

# API integration
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.scraping_api.id
  resource_id             = aws_api_gateway_resource.scrape.id
  http_method             = aws_api_gateway_method.scrape_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.api_gateway_role.arn
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

# response from method
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# response
resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "message": "URL added to scraping queue",
  "status": "success"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.sqs_integration]
}

# deploy + stage
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id

  depends_on = [
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration_response.integration_response,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  stage_name    = "prod"
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# outputs
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