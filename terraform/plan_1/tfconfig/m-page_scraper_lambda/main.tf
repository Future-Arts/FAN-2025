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

# Data source for git commit hash
data "external" "git_commit" {
  program = ["bash", "-c", "cd ${var.source_path} && echo '{\"commit_hash\": \"'$(git rev-parse HEAD 2>/dev/null || echo 'local-dev')'\"}'"]
}

# Advanced source code hash calculation
data "external" "source_files_hash" {
  program = ["bash", "-c", <<-EOT
    cd ${var.source_path}
    HASH=$(find . -type f \( -name "*.py" -o -name "requirements.txt" \) -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1 || echo 'no-files')
    echo "{\"hash\": \"$HASH\"}"
  EOT
  ]
}

# Create directory for infrastructure files
resource "null_resource" "create_infrastructure_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(var.output_path)}"
  }
}

# Modern build automation with robust error handling
resource "null_resource" "lambda_build" {
  triggers = {
    # Multi-factor trigger system
    source_code_hash = data.external.source_files_hash.result.hash
    git_commit      = data.external.git_commit.result.commit_hash
    requirements    = fileexists("${var.source_path}/../requirements.txt") ? filemd5("${var.source_path}/../requirements.txt") : "no-requirements"
    build_script    = fileexists(var.build_script_path) ? filemd5(var.build_script_path) : "no-build-script"
    # Force rebuild when variables change
    environment_vars = md5(jsonencode(var.environment_variables))
  }

  provisioner "local-exec" {
    command = "chmod +x ${var.build_script_path} && timeout 300 ${var.build_script_path} || echo 'Build script failed, using fallback'"
    environment = {
      BUILD_ENV     = var.environment
      AWS_REGION    = var.aws_region
      SOURCE_PATH   = var.source_path
      OUTPUT_PATH   = var.output_path
      GIT_COMMIT    = data.external.git_commit.result.commit_hash
    }
    
    on_failure = "continue"
  }

  depends_on = [null_resource.create_infrastructure_dir]
}

# Fallback requirements.txt if not exists
resource "local_file" "requirements_fallback" {
  count = fileexists("${var.source_path}/../requirements.txt") ? 0 : 1
  
  content = <<EOF
requests==2.31.0
beautifulsoup4==4.12.2
EOF
  filename = "${var.source_path}/../requirements.txt"
}

# Content-aware archive generation
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_path
  output_path = var.output_path
  
  depends_on = [
    null_resource.lambda_build,
    local_file.requirements_fallback
  ]
}

# Modern Lambda function with ARM64 and enhanced logging
resource "aws_lambda_function" "scraper" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role            = var.lambda_role_arn
  handler         = var.handler
  runtime         = var.runtime
  timeout         = var.timeout
  memory_size     = var.memory_size
  
  # Performance optimization with ARM64
  architectures = var.use_arm64 ? ["arm64"] : ["x86_64"]
  
  # Hash-based deployment - only update when content changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
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
  
  # Lifecycle management for stable deployments
  lifecycle {
    ignore_changes = [
      last_modified,
      version
    ]
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
    GitCommit   = data.external.git_commit.result.commit_hash
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
