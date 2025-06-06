# terraform/modules/iam/outputs.tf

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "api_gateway_sqs_role_arn" {
  description = "ARN of the API Gateway SQS integration role"
  value       = aws_iam_role.api_gateway_sqs.arn
}

output "cognito_unauthenticated_role_arn" {
  description = "ARN of the Cognito unauthenticated role"
  value       = aws_iam_role.cognito_unauthenticated.arn
}

# Add this to your existing terraform/modules/iam/outputs.tf file

output "websocket_lambda_role_arn" {
  description = "ARN of the WebSocket Lambda execution role"
  value       = aws_iam_role.websocket_lambda_execution.arn
}

output "websocket_lambda_role_name" {
  description = "Name of the WebSocket Lambda execution role"
  value       = aws_iam_role.websocket_lambda_execution.name
}
