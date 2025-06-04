# terraform/modules/sqs-queues/outputs.tf

output "scraping_queue_url" {
  description = "URL of the main scraping queue"
  value       = aws_sqs_queue.scraping_queue.url
}

output "scraping_queue_arn" {
  description = "ARN of the main scraping queue"
  value       = aws_sqs_queue.scraping_queue.arn
}

output "scraping_queue_name" {
  description = "Name of the main scraping queue"
  value       = aws_sqs_queue.scraping_queue.name
}

output "scraping_dlq_url" {
  description = "URL of the scraping DLQ"
  value       = aws_sqs_queue.scraping_dlq.url
}

output "scraping_dlq_arn" {
  description = "ARN of the scraping DLQ"
  value       = aws_sqs_queue.scraping_dlq.arn
}

output "lambda_dlq_url" {
  description = "URL of the Lambda DLQ"
  value       = aws_sqs_queue.lambda_dlq.url
}

output "lambda_dlq_arn" {
  description = "ARN of the Lambda DLQ"
  value       = aws_sqs_queue.lambda_dlq.arn
}
