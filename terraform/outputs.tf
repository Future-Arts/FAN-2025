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

# Add these outputs to your existing terraform/outputs.tf file

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint URL for real-time updates"
  value       = module.websocket.websocket_api_endpoint
}

output "websocket_api_id" {
  description = "WebSocket API ID"
  value       = module.websocket.websocket_api_id
}

output "dashboard_environment_variables" {
  description = "Environment variables for dashboard configuration (enhanced with WebSocket)"
  value = {
    VITE_AWS_REGION           = data.aws_region.current.name
    VITE_AWS_IDENTITY_POOL_ID = aws_cognito_identity_pool.dashboard_identity_pool.id
    VITE_SITEMAP_TABLE_NAME   = aws_dynamodb_table.website_sitemaps.name
    VITE_WEBSOCKET_ENDPOINT   = module.websocket.websocket_api_endpoint
    VITE_API_ENDPOINT         = module.api_gateway.api_endpoint_url
  }
}

output "websocket_connections_table_name" {
  description = "WebSocket connections DynamoDB table name"
  value       = module.websocket.connections_table_name
}

output "real_time_dashboard_setup" {
  description = "Complete setup information for real-time dashboard"
  value = {
    websocket_endpoint        = module.websocket.websocket_api_endpoint
    api_endpoint             = module.api_gateway.api_endpoint_url
    cognito_identity_pool_id = aws_cognito_identity_pool.dashboard_identity_pool.id
    dynamodb_table_name      = aws_dynamodb_table.website_sitemaps.name
    region                   = data.aws_region.current.name
  }
}
