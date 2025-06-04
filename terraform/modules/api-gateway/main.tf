# terraform/modules/api-gateway/main.tf
# Modern API Gateway configuration with SQS integration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/scraping-api"
  retention_in_days = var.log_retention_days
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "scraping_api" {
  name        = "scraping-api"
  description = "API for adding URLs to scraping queue"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Key
resource "aws_api_gateway_api_key" "scraping_api_key" {
  count = var.enable_api_key ? 1 : 0
  name  = "scraping-api-key"
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "scraping_api_usage_plan" {
  count = var.enable_usage_plan ? 1 : 0
  name  = "scraping-api-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.scraping_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = var.monthly_quota
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = var.burst_limit
    rate_limit  = var.rate_limit
  }
}

# Usage Plan Key
resource "aws_api_gateway_usage_plan_key" "scraping_api_usage_plan_key" {
  count = var.enable_api_key && var.enable_usage_plan ? 1 : 0
  
  key_id        = aws_api_gateway_api_key.scraping_api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.scraping_api_usage_plan[0].id
}

# Resource: /scrape
resource "aws_api_gateway_resource" "scrape" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  parent_id   = aws_api_gateway_rest_api.scraping_api.root_resource_id
  path_part   = "scrape"
}

# Request Validator
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "scrape-endpoint-validator"
  rest_api_id                = aws_api_gateway_rest_api.scraping_api.id
  validate_request_body      = true
  validate_request_parameters = true
}

# Request Model
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
    }
  })
}

# OPTIONS Method (CORS preflight)
resource "aws_api_gateway_method" "scrape_options" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  resource_id   = aws_api_gateway_resource.scrape.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# POST Method
resource "aws_api_gateway_method" "scrape_post" {
  rest_api_id      = aws_api_gateway_rest_api.scraping_api.id
  resource_id      = aws_api_gateway_resource.scrape.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = var.enable_api_key

  request_validator_id = aws_api_gateway_request_validator.validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.scrape_request_model.name
  }
}

# OPTIONS Integration (CORS)
resource "aws_api_gateway_integration" "options_integration" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# POST Integration (SQS)
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.scraping_api.id
  resource_id             = aws_api_gateway_resource.scrape.id
  http_method             = aws_api_gateway_method.scrape_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = var.sqs_integration_role_arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${split("/", var.sqs_queue_url)[length(split("/", var.sqs_queue_url)) - 1]}"

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

# OPTIONS Method Response (CORS)
resource "aws_api_gateway_method_response" "options_response_200" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options[0].http_method
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

# POST Method Response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = "200"

  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = true
  } : {}

  response_models = {
    "application/json" = "Empty"
  }
}

# OPTIONS Integration Response (CORS)
resource "aws_api_gateway_integration_response" "options_integration_response" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options[0].http_method
  status_code = aws_api_gateway_method_response.options_response_200[0].status_code

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

# POST Integration Response
resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  } : {}

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

# Deployment
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

# Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      resourcePath    = "$context.resourcePath"
      status          = "$context.status"
      protocol        = "$context.protocol"
      responseLength  = "$context.responseLength"
      apiKey          = "$context.identity.apiKey"
    })
  }
}
