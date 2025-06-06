# terraform/modules/lambda-scraper/main.tf
# Modern Lambda deployment with hash-based conditional deployment

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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

# Set FAN-2025 root directory
locals {
  fan_root = abspath("${path.module}/../../..")
  abs_source_path = "${local.fan_root}/${var.source_path}"
  abs_output_path = "${local.fan_root}/${var.output_path}"
  requirements_path = "${local.fan_root}/applications/page-scraper/requirements.txt"
  build_script = "${local.fan_root}/terraform/build_lambda.py"
}

# Build hash calculation using Python script
data "external" "build_info" {
  program = ["bash", "-c", "python3 \"${local.build_script}\""]
  
  # Pass paths as environment variables
  query = {
    SOURCE_PATH = local.abs_source_path
    REQUIREMENTS_FILE = local.requirements_path
    OUTPUT_PATH = local.abs_output_path
  }
}

# Create directory for infrastructure files
resource "null_resource" "create_infrastructure_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(local.abs_output_path)}"
  }
}

# Lambda build using Python script
resource "null_resource" "lambda_build" {
  triggers = {
    # Trigger rebuild when source files change
    build_hash = data.external.build_info.result.hash
    # Force rebuild when variables change
    environment_vars = md5(jsonencode(var.environment_variables))
  }

  provisioner "local-exec" {
    command = "python3 \"${local.build_script}\""
    environment = {
      SOURCE_PATH = local.abs_source_path
      REQUIREMENTS_FILE = local.requirements_path
      OUTPUT_PATH = local.abs_output_path
    }
  }

  depends_on = [null_resource.create_infrastructure_dir]
}

# Fallback requirements.txt if not exists
resource "local_file" "requirements_fallback" {
  count = fileexists(local.requirements_path) ? 0 : 1
  
  content = <<EOF
requests==2.31.0
beautifulsoup4==4.12.2
boto3
EOF
  filename = local.requirements_path
}

# Lambda package path (build script creates the zip)
locals {
  lambda_package_path = local.abs_output_path
}

# Modern Lambda function with ARM64 and enhanced logging
resource "aws_lambda_function" "scraper" {
  filename         = local.lambda_package_path
  function_name    = var.function_name
  role            = var.lambda_role_arn
  handler         = var.handler
  runtime         = var.runtime
  timeout         = var.timeout
  memory_size     = var.memory_size
  
  # Performance optimization with ARM64
  architectures = var.use_arm64 ? ["arm64"] : ["x86_64"]
  
  # Hash-based deployment - only update when content changes
  source_code_hash = filebase64sha256(local.abs_output_path)
  
  # Enhanced logging configuration (2024+ feature)
  dynamic "logging_config" {
    for_each = var.enable_json_logging ? [1] : []
    content {
      log_format = "JSON"
      log_group  = aws_cloudwatch_log_group.lambda_logs.name
    }
  }
  
  # Modern tracing configuration
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  # Dead letter queue configuration
  dynamic "dead_letter_config" {
    for_each = var.dlq_arn != null ? [1] : []
    content {
      target_arn = var.dlq_arn
    }
  }
  
  # VPC configuration if provided
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }
  
  environment {
    variables = var.environment_variables
  }
 
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    null_resource.lambda_build
  ]
}

# CloudWatch log group with modern configuration
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = {
    Name        = "${var.function_name}-logs"
    Environment = var.environment
  }
}

# Event source mapping with modern scaling configuration
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  count = var.event_source_arn != null ? 1 : 0
  
  event_source_arn = var.event_source_arn
  function_name    = aws_lambda_function.scraper.arn
  batch_size       = var.batch_size
  
  maximum_batching_window_in_seconds = var.max_batching_window
  
  # Modern scaling configuration
  dynamic "scaling_config" {
    for_each = var.max_concurrency != null ? [1] : []
    content {
      maximum_concurrency = var.max_concurrency
    }
  }
}
