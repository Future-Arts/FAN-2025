# terraform/modules/storage/main.tf
# Modern S3 bucket configuration for scraped data storage

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# S3 bucket for storing scraped data
resource "aws_s3_bucket" "scraped_data" {
  bucket = var.scraped_data_bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Scraped Data Bucket"
    Environment = var.environment
    Purpose     = "Storage for web scraping results"
  }
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "scraped_data_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.scraped_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "scraped_data_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.scraped_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = var.kms_key_id != null ? true : false
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "scraped_data_pab" {
  bucket = aws_s3_bucket.scraped_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch metric for monitoring bucket size
resource "aws_cloudwatch_metric_alarm" "bucket_size_alarm" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.environment}-scraped-data-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"  # Daily
  statistic           = "Average"
  threshold           = var.bucket_size_alarm_threshold
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []

  dimensions = {
    BucketName  = aws_s3_bucket.scraped_data.bucket
    StorageType = "StandardStorage"
  }

  tags = {
    Name        = "${var.environment} Bucket Size Alarm"
    Environment = var.environment
  }
}
