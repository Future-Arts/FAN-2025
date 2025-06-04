# terraform/modules/storage/outputs.tf

output "scraped_data_bucket_name" {
  description = "Name of the scraped data bucket"
  value       = aws_s3_bucket.scraped_data.bucket
}

output "scraped_data_bucket_arn" {
  description = "ARN of the scraped data bucket"
  value       = aws_s3_bucket.scraped_data.arn
}

output "scraped_data_bucket_domain_name" {
  description = "Domain name of the scraped data bucket"
  value       = aws_s3_bucket.scraped_data.bucket_domain_name
}

output "scraped_data_bucket_regional_domain_name" {
  description = "Regional domain name of the scraped data bucket"
  value       = aws_s3_bucket.scraped_data.bucket_regional_domain_name
}
