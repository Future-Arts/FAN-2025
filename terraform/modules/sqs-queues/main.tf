# terraform/modules/sqs-queues/main.tf
# Modern SQS queue configuration with DLQ and monitoring

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# Dead Letter Queue for failed scraping requests
resource "aws_sqs_queue" "scraping_dlq" {
  name                      = "url-scraping-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  visibility_timeout_seconds = var.dlq_visibility_timeout_seconds

  tags = {
    Name        = "URL Scraping DLQ"
    Environment = var.environment
    Purpose     = "Dead Letter Queue for failed scraping requests"
  }
}

# Dead Letter Queue for Lambda function errors
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "lambda-scraper-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  visibility_timeout_seconds = var.dlq_visibility_timeout_seconds

  tags = {
    Name        = "Lambda Scraper DLQ"
    Environment = var.environment
    Purpose     = "Dead Letter Queue for Lambda function errors"
  }
}

# Main scraping queue with modern configuration
resource "aws_sqs_queue" "scraping_queue" {
  name                      = "url-scraping-queue"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds = var.message_retention_seconds
  delay_seconds             = var.delay_seconds
  receive_wait_time_seconds = var.receive_wait_time_seconds

  # DLQ configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.scraping_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name        = "URL Scraping Queue"
    Environment = var.environment
    Purpose     = "Main queue for URL scraping requests"
  }
}

# CloudWatch alarms for monitoring queue depth
resource "aws_cloudwatch_metric_alarm" "queue_depth_alarm" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.environment}-scraping-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.queue_depth_alarm_threshold
  alarm_description   = "This metric monitors SQS queue depth"
  alarm_actions       = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []

  dimensions = {
    QueueName = aws_sqs_queue.scraping_queue.name
  }

  tags = {
    Name        = "${var.environment} Queue Depth Alarm"
    Environment = var.environment
  }
}

# CloudWatch alarm for DLQ messages
resource "aws_cloudwatch_metric_alarm" "dlq_messages_alarm" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.environment}-scraping-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors DLQ for failed messages"
  alarm_actions       = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []

  dimensions = {
    QueueName = aws_sqs_queue.scraping_dlq.name
  }

  tags = {
    Name        = "${var.environment} DLQ Messages Alarm"
    Environment = var.environment
  }
}
