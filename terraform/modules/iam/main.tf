# terraform/modules/iam/main.tf
# Modern IAM configuration with least privilege principles

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
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

  tags = {
    Name        = "Lambda Execution Role"
    Environment = var.environment
  }
}

# Basic Lambda execution policy
resource "aws_iam_role_policy" "lambda_basic_execution" {
  name = "lambda-scraper-policy"
  role = aws_iam_role.lambda_execution.id

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
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*:*"
      }
    ]
  })
}

# SQS access policy for Lambda
resource "aws_iam_role_policy" "lambda_sqs_access" {
  name = "lambda-sqs-policy"
  role = aws_iam_role.lambda_execution.id

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
          "arn:aws:sqs:${var.aws_region}:*:url-scraping-queue",
          "arn:aws:sqs:${var.aws_region}:*:lambda-scraper-dlq",
          "arn:aws:sqs:${var.aws_region}:*:url-scraping-dlq"
        ]
      }
    ]
  })
}

# X-Ray tracing policy for Lambda
resource "aws_iam_role_policy" "lambda_xray_access" {
  count = var.enable_xray_tracing ? 1 : 0
  name  = "lambda-xray-access"
  role  = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# API Gateway role for SQS integration
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

  tags = {
    Name        = "API Gateway SQS Role"
    Environment = var.environment
  }
}

# API Gateway SQS access policy
resource "aws_iam_role_policy" "api_gateway_sqs_access" {
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
        Resource = "arn:aws:sqs:${var.aws_region}:*:url-scraping-queue"
      }
    ]
  })
}

# Cognito unauthenticated role for dashboard access
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
            "cognito-identity.amazonaws.com:aud" = var.cognito_identity_pool_id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "Cognito Unauthenticated Role"
    Environment = var.environment
  }
}

# DynamoDB read access for dashboard users
resource "aws_iam_role_policy" "cognito_dynamodb_read" {
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
          "arn:aws:dynamodb:${var.aws_region}:*:table/website-sitemaps",
          "arn:aws:dynamodb:${var.aws_region}:*:table/website-sitemaps/index/*"
        ]
      }
    ]
  })
}

# Lambda DynamoDB access policy
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-sitemap-policy"
  role = aws_iam_role.lambda_execution.name

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
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })
}

# Lambda S3 access policy for scraped data storage
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-policy"
  role = aws_iam_role.lambda_execution.id

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
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}
