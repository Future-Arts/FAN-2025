# terraform/modules/websocket/main.tf
# WebSocket API Gateway and Lambda infrastructure for real-time updates

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88"
    }
  }
}

# WebSocket API Gateway
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = "${var.environment}-scraping-websocket"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  
  tags = {
    Name        = "${var.environment} Scraping WebSocket API"
    Environment = var.environment
    Purpose     = "Real-time 3D visualization updates"
  }
}

# DynamoDB table for WebSocket connections
resource "aws_dynamodb_table" "websocket_connections" {
  name           = "${var.environment}-websocket-connections"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment} WebSocket Connections"
    Environment = var.environment
    Purpose     = "WebSocket connection management"
  }
}

# CloudWatch log group for WebSocket functions
resource "aws_cloudwatch_log_group" "websocket_logs" {
  name              = "/aws/lambda/${var.environment}-websocket"
  retention_in_days = var.log_retention_days
}

# WebSocket Connect Lambda function
resource "aws_lambda_function" "websocket_connect" {
  filename         = var.websocket_package_path
  function_name    = "${var.environment}-websocket-connect"
  role            = var.websocket_lambda_role_arn
  handler         = "websocket_handler.connect_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256
  architectures   = ["arm64"]

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.websocket_logs]

  tags = {
    Name        = "${var.environment} WebSocket Connect"
    Environment = var.environment
  }
}

# WebSocket Disconnect Lambda function
resource "aws_lambda_function" "websocket_disconnect" {
  filename         = var.websocket_package_path
  function_name    = "${var.environment}-websocket-disconnect"
  role            = var.websocket_lambda_role_arn
  handler         = "websocket_handler.disconnect_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256
  architectures   = ["arm64"]

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.websocket_logs]

  tags = {
    Name        = "${var.environment} WebSocket Disconnect"
    Environment = var.environment
  }
}

# WebSocket Message Lambda function
resource "aws_lambda_function" "websocket_message" {
  filename         = var.websocket_package_path
  function_name    = "${var.environment}-websocket-message"
  role            = var.websocket_lambda_role_arn
  handler         = "websocket_handler.message_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256
  architectures   = ["arm64"]

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.websocket_logs]

  tags = {
    Name        = "${var.environment} WebSocket Message"
    Environment = var.environment
  }
}

# WebSocket Broadcaster Lambda function (called by scraping Lambda)
resource "aws_lambda_function" "websocket_broadcaster" {
  filename         = var.websocket_package_path
  function_name    = "${var.environment}-websocket-broadcaster"
  role            = var.websocket_lambda_role_arn
  handler         = "websocket_handler.broadcast_handler"
  runtime         = "python3.12"
  timeout         = 60
  memory_size     = 512
  architectures   = ["arm64"]

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_api.websocket_api.api_endpoint
      ENVIRONMENT           = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.websocket_logs]

  tags = {
    Name        = "${var.environment} WebSocket Broadcaster"
    Environment = var.environment
  }
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "websocket_connect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_disconnect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_message_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

# WebSocket routes
resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration.id}"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

# WebSocket integrations
resource "aws_apigatewayv2_integration" "connect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_connect.invoke_arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_disconnect.invoke_arn
}

resource "aws_apigatewayv2_integration" "message_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_message.invoke_arn
}

# WebSocket deployment
resource "aws_apigatewayv2_deployment" "websocket_deployment" {
  api_id = aws_apigatewayv2_api.websocket_api.id

  depends_on = [
    aws_apigatewayv2_route.connect_route,
    aws_apigatewayv2_route.disconnect_route,
    aws_apigatewayv2_route.default_route
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# WebSocket stage
resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id        = aws_apigatewayv2_api.websocket_api.id
  deployment_id = aws_apigatewayv2_deployment.websocket_deployment.id
  name          = var.stage_name

  default_route_settings {
    logging_level            = "INFO"
    data_trace_enabled       = true
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.websocket_logs.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      connectionId    = "$context.connectionId"
      routeKey        = "$context.routeKey"
      status          = "$context.status"
      requestTime     = "$context.requestTime"
      responseLength  = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.environment} WebSocket Stage"
    Environment = var.environment
  }
}
