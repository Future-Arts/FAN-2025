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
}

# variables (we test in production because i never write bad code)
variable "environment" {
  type    = string
  default = "prod"
}

# ================================================================
# terraform management / meta stuff
# ================================================================
# s3 bucket for storing tfstate remotely
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-fan2025"

  lifecycle {
    prevent_destroy = true
  }
}
# enable s3 bucket versioning for some insurance in case something terrible happens
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
# server side encryption for tfstate
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# state locking in the incredibly rare chance that anyone else on the team ever learns to use terraform...
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ================================================================
# dashboard resources
# ================================================================
# dynamodb for storing some metadata about scraped sites, used in dashboard visualizer (separate db to avoid locking issues)
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

# ================================================================
# scraping data pipeline before data processing and categorization
# ================================================================
# dlq for errored queue entries so that I can fix them (never happens because i never write bad code)
resource "aws_sqs_queue" "scraping_dlq" {
  name                      = "url-scraping-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}
# actually not sure what this one is, lemme uh get back to you
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "lambda-scraper-dlq"
  message_retention_seconds = 1209600
  visibility_timeout_seconds = 300
}
# the actual queue that the URLs should be inserted into when we need them to be scraped
resource "aws_sqs_queue" "scraping_queue" {
  name                      = "url-scraping-queue"
  visibility_timeout_seconds = 900
  message_retention_seconds = 1209600
  delay_seconds             = 0
  receive_wait_time_seconds = 20
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scraping_dlq.arn
    maxReceiveCount     = 3
  })
}
# bucket to hold all scraped data. this can be viewed as a backup for airtable if you need to refresh or reinitialize airtable
resource "aws_s3_bucket" "scraped_data" {
  bucket = "artist-scraped-data"

  lifecycle {
    prevent_destroy = true
  }
}
# surely we will not need versioning on this bucket because we would never corrupt/mutilate the data inside, but let's enable it anyways just for fun
resource "aws_s3_bucket_versioning" "scraped_data_versioning" {
  bucket = aws_s3_bucket.scraped_data.id
  versioning_configuration {
    status = "Enabled"
  }
}
# i guess we can encrypt the data, but i mean... it's all pulled from public sites lol
resource "aws_s3_bucket_server_side_encryption_configuration" "scraped_data_encryption" {
  bucket = aws_s3_bucket.scraped_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# requirements.txt file for the page scraping lambda
resource "local_file" "requirements" {
  content = <<EOF
requests==2.31.0
beautifulsoup4==4.12.2
EOF
  filename = "${path.module}/../infrastructure/requirements.txt"
}
# make sure the infrastructure directory exists in the correct location for zipping up the lambda
resource "null_resource" "create_infrastructure_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../infrastructure"
  }
}
# define triggers to rebuild lambda upload package
resource "null_resource" "lambda_package" {
  triggers = {
    # Rebuild when Python code or requirements change
    python_code = fileexists("${path.module}/../infrastructure/pagescraper.py") ? filebase64sha256("${path.module}/../infrastructure/pagescraper.py") : "none"
    requirements = local_file.requirements.content
    build_script = fileexists("${path.module}/build_lambda.sh") ? filebase64sha256("${path.module}/build_lambda.sh") : "none"
  }
  # might have to change this depending on what OS the dev is running on, but let's be real nobody else even uses terraform on this team.
  # in fact, i doubt anyone will ever read this comment. if you do read this, even if you are a team working on this in the future, text
  # me at 253-545-8346 and I will venmo/apple pay you 3 dollars.
  provisioner "local-exec" {
    command = "chmod +x ${path.module}/build_lambda.sh && ${path.module}/build_lambda.sh"
  }

  depends_on = [
    local_file.requirements,
    null_resource.create_infrastructure_dir
  ]
}
# page scraping script, defining local relative path and some aws configuration settings
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
      MAX_DEPTH             = 20
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
# cloudwatch for storing errors
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/page-scraper"
  retention_in_days = 14
}
# trigger the lambda whenever there is a url in the queue that hasnt been yoinked
resource "aws_lambda_event_source_mapping" "scraping_queue_trigger" {
  event_source_arn = aws_sqs_queue.scraping_queue.arn
  function_name    = aws_lambda_function.page_scraper.arn
  batch_size       = 1
  
  maximum_batching_window_in_seconds = 0

  scaling_config {
    maximum_concurrency = 10
  }
}
# ================================================================
# iam roles and security policies for all resources
# ================================================================
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
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/scraping-api"
  retention_in_days = 14
}
# IAM Policy for unauthenticated dashboard users - DynamoDB read access
resource "aws_iam_role_policy" "cognito_unauthenticated_policy" {
  name = "cognito-dashboard-unauthenticated-policy"
  role = aws_iam_role.cognito_unauthenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.sitemap_storage.arn,
          "${aws_dynamodb_table.sitemap_storage.arn}/index/*"
        ]
      }
    ]
  })
}
# Cognito Identity Pool for unauthenticated dashboard access
resource "aws_cognito_identity_pool" "dashboard_identity_pool" {
  identity_pool_name               = "scraping-dashboard-identity-pool"
  allow_unauthenticated_identities = true
  allow_classic_flow              = false

  tags = {
    Name        = "Scraping Dashboard Identity Pool"
    Environment = var.environment
  }
}
# IAM Role for unauthenticated users from the identity pool
resource "aws_iam_role" "cognito_unauthenticated" {
  name = "cognito-dashboard-unauthenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.dashboard_identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })
}
# Attach the role to the identity pool
resource "aws_cognito_identity_pool_roles_attachment" "dashboard_identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.dashboard_identity_pool.id

  roles = {
    "unauthenticated" = aws_iam_role.cognito_unauthenticated.arn
  }
}
# ================================================================
# api gateway configuration
# ================================================================
resource "aws_api_gateway_rest_api" "scraping_api" {
  name        = "scraping-api"
  description = "API for adding URLs to scraping queue"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
resource "aws_api_gateway_api_key" "scraping_api_key" {
  name = "scraping-api-key"
}
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
resource "aws_api_gateway_method" "scrape_options" {
  rest_api_id   = aws_api_gateway_rest_api.scraping_api.id
  resource_id   = aws_api_gateway_resource.scrape.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
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
resource "aws_api_gateway_request_validator" "validator" {
  name                        = "scrape-endpoint-validator"
  rest_api_id                = aws_api_gateway_rest_api.scraping_api.id
  validate_request_body      = true
  validate_request_parameters = true
}
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
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.scraping_api.id
  resource_id = aws_api_gateway_resource.scrape.id
  http_method = aws_api_gateway_method.scrape_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
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
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# outputs
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
# Output the Cognito Identity Pool ID for environment variables
output "cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.dashboard_identity_pool.id
  description = "Cognito Identity Pool ID for zero-config dashboard access"
}

# Update existing sitemap_table_name output to include more context
output "dashboard_environment_variables" {
  value = {
    VITE_AWS_REGION = data.aws_region.current.name
    VITE_AWS_IDENTITY_POOL_ID = aws_cognito_identity_pool.dashboard_identity_pool.id
    VITE_SITEMAP_TABLE_NAME = aws_dynamodb_table.sitemap_storage.name
  }
  description = "Environment variables to configure in your build process for zero-config access"
}
