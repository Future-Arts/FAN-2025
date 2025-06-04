# terraform/modules/api-gateway/outputs.tf

output "api_endpoint_url" {
  description = "API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.scraping_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/scrape"
}

output "api_key_value" {
  description = "API Gateway key value"
  value       = var.enable_api_key ? aws_api_gateway_api_key.scraping_api_key[0].value : null
  sensitive   = true
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.scraping_api.id
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.prod.stage_name
}
