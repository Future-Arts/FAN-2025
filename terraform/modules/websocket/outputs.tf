# terraform/modules/websocket/outputs.tf

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint URL"
  value       = "${replace(aws_apigatewayv2_api.websocket_api.api_endpoint, "https://", "wss://")}/${aws_apigatewayv2_stage.websocket_stage.name}"
}

output "websocket_api_id" {
  description = "WebSocket API ID"
  value       = aws_apigatewayv2_api.websocket_api.id
}

output "websocket_broadcaster_function_name" {
  description = "WebSocket broadcaster Lambda function name"
  value       = aws_lambda_function.websocket_broadcaster.function_name
}

output "websocket_broadcaster_function_arn" {
  description = "WebSocket broadcaster Lambda function ARN"
  value       = aws_lambda_function.websocket_broadcaster.arn
}

output "connections_table_name" {
  description = "WebSocket connections DynamoDB table name"
  value       = aws_dynamodb_table.websocket_connections.name
}

output "connections_table_arn" {
  description = "WebSocket connections DynamoDB table ARN"
  value       = aws_dynamodb_table.websocket_connections.arn
}
