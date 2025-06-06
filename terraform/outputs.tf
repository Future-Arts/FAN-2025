# terraform/outputs.tf

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.api_endpoint_url
}

output "scraping_queue_url" {
  description = "URL of the main scraping queue"
  value       = module.sqs_queues.scraping_queue_url
}

output "api_key" {
  description = "API Gateway key for authentication"
  value       = module.api_gateway.api_key_value
  sensitive   = true
}

output "dlq_urls" {
  description = "Dead letter queue URLs for monitoring"
  value = {
    scraping = module.sqs_queues.scraping_dlq_url
    lambda   = module.sqs_queues.lambda_dlq_url
  }
}

output "sitemap_table_name" {
  description = "Name of the DynamoDB sitemap table"
  value       = aws_dynamodb_table.website_sitemaps.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for scraped data"
  value       = module.storage.scraped_data_bucket_name
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID for dashboard access"
  value       = aws_cognito_identity_pool.dashboard_identity_pool.id
}

output "dashboard_environment_variables" {
  description = "Environment variables for dashboard configuration"
  value = {
    VITE_AWS_REGION           = data.aws_region.current.name
    VITE_AWS_IDENTITY_POOL_ID = aws_cognito_identity_pool.dashboard_identity_pool.id
    VITE_SITEMAP_TABLE_NAME   = aws_dynamodb_table.website_sitemaps.name
  }
}
