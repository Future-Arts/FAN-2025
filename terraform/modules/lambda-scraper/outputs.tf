# terraform/modules/lambda-scraper/outputs.tf

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.scraper.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.scraper.function_name
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.scraper.invoke_arn
}

output "function_qualified_arn" {
  description = "Qualified ARN of the Lambda function"
  value       = aws_lambda_function.scraper.qualified_arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "source_code_hash" {
  description = "Base64-encoded SHA256 hash of the deployment package"
  value       = aws_lambda_function.scraper.source_code_hash
}

output "build_hash" {
  description = "Build hash used for this deployment"
  value       = data.external.build_info.result.hash
}

output "build_timestamp" {
  description = "Timestamp when the build was triggered"
  value       = null_resource.lambda_build.id
}
