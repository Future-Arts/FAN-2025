# terraform/main.tf
# Modern Terraform configuration maintaining existing S3 backend

terraform {
  backend "s3" {
    bucket         = "terraform-state-fan2025"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
  
  required_version = ">= 1.6.0"
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
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ================================================================
# TERRAFORM STATE MANAGEMENT (EXISTING RESOURCES)
# ================================================================

# S3 bucket for storing tfstate remotely (keep existing)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-fan2025"

  lifecycle {
    prevent_destroy = true
  }
}

# Enable S3 bucket versioning for tfstate insurance
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server side encryption for tfstate
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State locking with DynamoDB
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
# MODERN MODULAR INFRASTRUCTURE
# ================================================================

# Storage module - S3 bucket for scraped data
module "storage" {
  source = "./modules/storage"
  
  environment              = var.environment
  scraped_data_bucket_name = "artist-scraped-data"
  enable_versioning        = true
  enable_encryption        = true
}

# SQS queues module - messaging infrastructure
module "sqs_queues" {
  source = "./modules/sqs-queues"
  
  environment                    = var.environment
  visibility_timeout_seconds     = 900
  max_receive_count             = 3
  enable_monitoring             = true
  queue_depth_alarm_threshold   = 100
}

# IAM module - security and permissions
module "iam" {
  source = "./modules/iam"
  
  environment           = var.environment
  aws_region           = var.aws_region
  enable_xray_tracing  = true
}

# DynamoDB table for sitemap storage (keep existing name)
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

# Cognito Identity Pool for dashboard access
resource "aws_cognito_identity_pool" "dashboard_identity_pool" {
  identity_pool_name               = "scraping-dashboard-identity-pool"
  allow_unauthenticated_identities = true
  allow_classic_flow              = false

  tags = {
    Name        = "Scraping Dashboard Identity Pool"
    Environment = var.environment
  }
}

# Lambda scraper module - core processing function
module "page_scraper_lambda" {
  source = "./modules/lambda-scraper"
  
  function_name     = "page-scraper"
  lambda_role_arn   = module.iam.lambda_execution_role_arn
  
  # Build configuration
  source_path        = "../applications/page-scraper/src"
  build_script_path  = "../applications/page-scraper/build.sh"
  output_path        = "../infrastructure/lambda_function.zip"
  
  environment       = var.environment
  aws_region        = var.aws_region
  
  # Performance optimization
  use_arm64         = true
  memory_size       = 512
  timeout           = 300
  
  # Enhanced features
  enable_json_logging  = true
  enable_xray_tracing = true
  log_retention_days  = 14
  
  # Event source configuration
  event_source_arn = module.sqs_queues.scraping_queue_arn
  batch_size       = 1
  max_concurrency  = 10
  
  # Dead letter queue
  dlq_arn = module.sqs_queues.lambda_dlq_arn
  
  # Environment variables
  environment_variables = {
    MAX_DEPTH             = "20"
    RATE_LIMIT_PER_DOMAIN = "10"
    ALLOWED_DOMAINS       = "[]"
    URL_QUEUE_URL         = module.sqs_queues.scraping_queue_url
    SITEMAP_TABLE_NAME    = aws_dynamodb_table.sitemap_storage.name
  }
}

# API Gateway module - external interface
module "api_gateway" {
  source = "./modules/api-gateway"
  
  environment = var.environment
  
  sqs_queue_url            = module.sqs_queues.scraping_queue_url
  sqs_integration_role_arn = module.iam.api_gateway_sqs_role_arn
  
  # API configuration
  enable_api_key     = true
  rate_limit         = 5
  burst_limit        = 10
  monthly_quota      = 1000
  log_retention_days = 14
}

# Cognito role attachment
resource "aws_cognito_identity_pool_roles_attachment" "dashboard_identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.dashboard_identity_pool.id

  roles = {
    "unauthenticated" = module.iam.cognito_unauthenticated_role_arn
  }
}

# Additional IAM policy for Lambda DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-sitemap-policy"
  role = module.iam.lambda_execution_role_name

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
          aws_dynamodb_table.sitemap_storage.arn,
          "${aws_dynamodb_table.sitemap_storage.arn}/index/*"
        ]
      }
    ]
  })
}

# Additional IAM policy for Lambda S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-policy"
  role = module.iam.lambda_execution_role_name

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
          "${module.storage.scraped_data_bucket_arn}/*"
        ]
      }
    ]
  })
}
