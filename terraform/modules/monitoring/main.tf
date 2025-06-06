# terraform/modules/monitoring/main.tf
# Optional monitoring module for enhanced observability

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# ================================================================
# SNS TOPIC FOR ALERTS
# ================================================================

resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-scraping-alerts"
  
  tags = {
    Name        = "${var.environment} Scraping Alerts"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================================================
# BASIC CLOUDWATCH DASHBOARD
# ================================================================

resource "aws_cloudwatch_dashboard" "scraping_dashboard" {
  dashboard_name = "${var.environment}-scraping-dashboard"

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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name],
            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", var.sqs_queue_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Core Metrics"
          period  = 300
        }
      }
    ]
  })
}
