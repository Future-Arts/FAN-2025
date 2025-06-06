# terraform/main.tf
# Enhanced Terraform configuration for 3D Force Graph visualization
# Implements optimizations from the comprehensive implementation strategy

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

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-fan2025"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

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
# ENHANCED DYNAMODB TABLE FOR 3D VISUALIZATION
# ================================================================

# Enhanced DynamoDB table with adjacency list pattern for 3D force graphs
resource "aws_dynamodb_table" "website_sitemaps" {
  name           = "website-sitemaps"  # Synchronized with IAM policies and other references
  billing_mode   = var.enable_provisioned_capacity ? "PROVISIONED" : "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  # Provisioned capacity for cost optimization (when enabled)
  read_capacity  = var.enable_provisioned_capacity ? var.read_capacity_units : null
  write_capacity = var.enable_provisioned_capacity ? var.write_capacity_units : null

  # Enhanced schema for 3D visualization
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  attribute {
    name = "GSI2SK"
    type = "S"
  }

  # GSI1: For status and timestamp queries (3D visualization filtering)
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
    
    read_capacity  = var.enable_provisioned_capacity ? var.gsi_read_capacity_units : null
    write_capacity = var.enable_provisioned_capacity ? var.gsi_write_capacity_units : null
  }

  # GSI2: For domain-based analysis (3D visualization navigation)
  global_secondary_index {
    name            = "GSI2"
    hash_key        = "GSI2PK"
    range_key       = "GSI2SK"
    projection_type = "ALL"
    
    read_capacity  = var.enable_provisioned_capacity ? var.gsi_read_capacity_units : null
    write_capacity = var.enable_provisioned_capacity ? var.gsi_write_capacity_units : null
  }

  # Enhanced monitoring for 3D visualization performance
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = {
    Name                = "Website Sitemaps"
    Environment         = var.environment
    Purpose             = "3D Force Graph Data Storage"
    OptimizedFor        = "AdjacencyListPattern"
    VisualizationType   = "3D Force Graph"
  }
}

# ================================================================
# ENHANCED COGNITO CONFIGURATION FOR 3D DASHBOARD
# ================================================================

resource "aws_cognito_identity_pool" "dashboard_identity_pool" {
  identity_pool_name               = "scraping-dashboard-identity-pool"
  allow_unauthenticated_identities = true
  allow_classic_flow              = false

  tags = {
    Name        = "3D Scraping Dashboard Identity Pool"
    Environment = var.environment
    Purpose     = "3D Force Graph Dashboard Access"
  }
}

# ================================================================
# ENHANCED MODULES WITH 3D OPTIMIZATION
# ================================================================

# Storage module with enhanced monitoring for 3D data
module "storage" {
  source = "./modules/storage"
  
  environment              = var.environment
  scraped_data_bucket_name = "artist-scraped-data"
  enable_versioning        = true
  enable_encryption        = true
 
  # Enhanced monitoring for 3D visualization data
  enable_monitoring             = true
  bucket_size_alarm_threshold   = 107374182400
  alarm_topic_arn              = module.monitoring.sns_topic_arn
}

# Enhanced SQS queues with optimized settings for 3D processing
module "sqs_queues" {
  source = "./modules/sqs-queues"
  
  environment                    = var.environment
  visibility_timeout_seconds     = 900  # Increased for 3D processing
  max_receive_count             = 3
  enable_monitoring             = true
  queue_depth_alarm_threshold   = 100
  alarm_topic_arn               = module.monitoring.sns_topic_arn
}

# Enhanced IAM with specific 3D dashboard permissions
module "iam" {
  source = "./modules/iam"
  
  environment           = var.environment
  aws_region           = var.aws_region
  enable_xray_tracing  = true
  s3_bucket_arn        = module.storage.scraped_data_bucket_arn
  dynamodb_table_arn   = aws_dynamodb_table.website_sitemaps.arn
  
  # Enhanced permissions for 3D visualization
  cognito_identity_pool_id = aws_cognito_identity_pool.dashboard_identity_pool.id
}

# Enhanced Lambda with 3D processing optimizations
module "page_scraper_lambda" {
  source = "./modules/lambda-scraper"
  
  function_name     = "page-scraper"
  lambda_role_arn   = module.iam.lambda_execution_role_arn
  
  # Build configuration (relative to FAN-2025 root)
  source_path        = "applications/page-scraper/src"
  build_script_path  = "applications/page-scraper/build.sh"
  output_path        = "infrastructure/lambda_function.zip"
  
  environment       = var.environment
  aws_region        = var.aws_region
  
  # Enhanced performance for 3D data processing
  use_arm64         = true
  memory_size       = var.lambda_memory_size
  timeout           = var.lambda_timeout
  
  # Enhanced features for 3D visualization
  enable_json_logging  = true
  enable_xray_tracing = true
  log_retention_days  = var.log_retention_days
  
  # Event source configuration optimized for 3D processing
  event_source_arn = module.sqs_queues.scraping_queue_arn
  batch_size       = 1
  max_concurrency  = var.lambda_max_concurrency
  
  # Enhanced dead letter queue configuration
  dlq_arn = module.sqs_queues.lambda_dlq_arn
  
  # Environment variables for 3D force graph optimization
  environment_variables = {
    MAX_DEPTH             = var.scraping_max_depth
    RATE_LIMIT_PER_DOMAIN = var.rate_limit_per_domain
    ALLOWED_DOMAINS       = jsonencode(var.allowed_domains)
    URL_QUEUE_URL         = module.sqs_queues.scraping_queue_url
    SITEMAP_TABLE_NAME    = aws_dynamodb_table.website_sitemaps.name
    
    # 3D visualization specific variables
    ENABLE_3D_OPTIMIZATION     = "true"
    MAX_NODES_PER_WEBSITE     = var.max_nodes_per_website
    ENABLE_PROGRESSIVE_LOADING = "true"
    VISUALIZATION_MODE         = "3D_FORCE_GRAPH"

    # WebSocket broadcasting
    WEBSOCKET_BROADCASTER_FUNCTION_NAME = module.websocket.websocket_broadcaster_function_name
    WEBSOCKET_API_ENDPOINT              = module.websocket.websocket_api_endpoint
    ENABLE_WEBSOCKET_UPDATES            = "true"
  }
}

# Enhanced API Gateway with 3D-specific rate limits
module "api_gateway" {
  source = "./modules/api-gateway"
  
  environment = var.environment
  
  sqs_queue_url            = module.sqs_queues.scraping_queue_url
  sqs_integration_role_arn = module.iam.api_gateway_sqs_role_arn
  
  # Enhanced API configuration for 3D dashboard
  enable_api_key     = true
  rate_limit         = var.api_rate_limit
  burst_limit        = var.api_burst_limit
  monthly_quota      = var.api_monthly_quota
  log_retention_days = var.log_retention_days
  
  # Enhanced CORS for 3D visualization
  enable_cors = true
}

# New monitoring module for enhanced 3D visualization monitoring
# New monitoring module for enhanced 3D visualization monitoring
module "monitoring" {
  source = "./modules/monitoring"
  
  environment = var.environment
  aws_region  = var.aws_region
  
  # Resources to monitor
  dynamodb_table_name  = aws_dynamodb_table.website_sitemaps.name
  lambda_function_name = module.page_scraper_lambda.function_name
  sqs_queue_name      = module.sqs_queues.scraping_queue_name
  api_gateway_name    = module.api_gateway.api_gateway_id
  s3_bucket_name      = module.storage.scraped_data_bucket_name
  
  # Notification settings (optional)
  notification_email = ""  # Set to your email if you want notifications
}

# Build WebSocket Lambda package
resource "null_resource" "websocket_build" {
  triggers = {
    # Force rebuild when source files change
    source_hash = filemd5("${path.module}/../applications/websocket-handler/src/websocket_handler.py")
    build_script = filemd5("${path.module}/../applications/websocket-handler/build.sh")
    requirements = filemd5("${path.module}/../applications/websocket-handler/requirements.txt")
  }

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/../applications/websocket-handler/build.sh && ${path.module}/../applications/websocket-handler/build.sh"
    environment = {
      BUILD_ENV   = var.environment
      AWS_REGION  = var.aws_region
      OUTPUT_PATH = "${path.module}/../infrastructure/websocket_function.zip"
    }
  }
}

# WebSocket module for real-time dashboard updates
module "websocket" {
  source = "./modules/websocket"
  
  environment                = var.environment
  websocket_lambda_role_arn  = module.iam.websocket_lambda_role_arn
  websocket_package_path     = "${path.module}/../infrastructure/websocket_function.zip"
  log_retention_days         = var.log_retention_days
  stage_name                 = var.environment
  
  depends_on = [null_resource.websocket_build]
}


# ================================================================
# COGNITO ROLE ATTACHMENTS
# ================================================================

resource "aws_cognito_identity_pool_roles_attachment" "dashboard_identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.dashboard_identity_pool.id

  roles = {
    "unauthenticated" = module.iam.cognito_unauthenticated_role_arn
  }
}

# ================================================================
# ENHANCED CLOUDWATCH DASHBOARDS FOR 3D VISUALIZATION
# ================================================================

resource "aws_cloudwatch_dashboard" "scraping_3d_dashboard" {
  dashboard_name = "${var.environment}-3d-scraping-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.website_sitemaps.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            ["AWS/Lambda", "Duration", "FunctionName", module.page_scraper_lambda.function_name],
            [".", "Invocations", ".", "."],
            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", module.sqs_queues.scraping_queue_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "3D Force Graph - Core Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${module.page_scraper_lambda.function_name}' | fields @timestamp, @message | filter @message like /3D/ | sort @timestamp desc | limit 20"
          region  = var.aws_region
          title   = "3D Processing Logs"
          view    = "table"
        }
      }
    ]
  })
}

# ================================================================
# COST OPTIMIZATION RESOURCES
# ================================================================

# CloudWatch alarm for DynamoDB costs
resource "aws_cloudwatch_metric_alarm" "dynamodb_cost_alarm" {
  count = var.enable_cost_monitoring ? 1 : 0
  
  alarm_name          = "${var.environment}-dynamodb-cost-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.daily_cost_threshold
  alarm_description   = "This metric monitors DynamoDB estimated charges"
  alarm_actions       = [module.monitoring.sns_topic_arn]

  dimensions = {
    Currency    = "USD"
    ServiceName = "AmazonDynamoDB"
  }

  tags = {
    Name        = "${var.environment} DynamoDB Cost Alarm"
    Environment = var.environment
    Purpose     = "Cost Optimization"
  }
}

# ================================================================
# AUTO-SCALING FOR DYNAMODB (RESERVED CAPACITY PLANNING)
# ================================================================

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  count = var.enable_provisioned_capacity && var.enable_autoscaling ? 1 : 0
  
  max_capacity       = var.max_read_capacity_units
  min_capacity       = var.min_read_capacity_units
  resource_id        = "table/${aws_dynamodb_table.website_sitemaps.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  count = var.enable_provisioned_capacity && var.enable_autoscaling ? 1 : 0
  
  name               = "${var.environment}-DynamoDBReadCapacityUtilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.read_target_utilization
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  count = var.enable_provisioned_capacity && var.enable_autoscaling ? 1 : 0
  
  max_capacity       = var.max_write_capacity_units
  min_capacity       = var.min_write_capacity_units
  resource_id        = "table/${aws_dynamodb_table.website_sitemaps.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  count = var.enable_provisioned_capacity && var.enable_autoscaling ? 1 : 0
  
  name               = "${var.environment}-DynamoDBWriteCapacityUtilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.write_target_utilization
  }
}
