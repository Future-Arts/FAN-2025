resource "aws_lambda_function" "url_processor" {
  filename         = "../src/lambda_function.zip"
  function_name    = "url-processor-lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.handler"
  runtime          = "nodejs14.x"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      MAX_DEPTH              = 3
      RATE_LIMIT_PER_DOMAIN  = 10
      ALLOWED_DOMAINS        = "[]"
      URL_QUEUE_URL          = aws_sqs_queue.url_scraping_queue.url
      IMAGE_QUEUE_URL        = aws_sqs_queue.image_download_queue.url
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_lambda_event_source_mapping" "url_scraping_queue_trigger" {
  event_source_arn = aws_sqs_queue.url_scraping_queue.arn
  function_name    = aws_lambda_function.url_processor.arn
  batch_size       = 1
}