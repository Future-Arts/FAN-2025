#!/bin/bash
# Terraform State Migration Script - Move resources from root to modules

echo "Starting Terraform state migration..."
echo "This will move existing resources to their new module locations"
echo ""

# Set strict error handling
set -e

# Function to check if resource exists in state
resource_exists() {
    terraform state show "$1" &>/dev/null
}

echo "=== MIGRATING SQS QUEUES ==="
if resource_exists "aws_sqs_queue.scraping_queue"; then
    terraform state mv "aws_sqs_queue.scraping_queue" "module.sqs_queues.aws_sqs_queue.scraping_queue"
    echo "✓ Moved scraping queue"
fi

if resource_exists "aws_sqs_queue.scraping_dlq"; then
    terraform state mv "aws_sqs_queue.scraping_dlq" "module.sqs_queues.aws_sqs_queue.scraping_dlq"
    echo "✓ Moved scraping DLQ"
fi

if resource_exists "aws_sqs_queue.lambda_dlq"; then
    terraform state mv "aws_sqs_queue.lambda_dlq" "module.sqs_queues.aws_sqs_queue.lambda_dlq"
    echo "✓ Moved lambda DLQ"
fi

echo ""
echo "=== MIGRATING IAM ROLES ==="
if resource_exists "aws_iam_role.lambda_exec"; then
    terraform state mv "aws_iam_role.lambda_exec" "module.iam.aws_iam_role.lambda_execution"
    echo "✓ Moved lambda execution role"
fi

if resource_exists "aws_iam_role.api_gateway_sqs"; then
    terraform state mv "aws_iam_role.api_gateway_sqs" "module.iam.aws_iam_role.api_gateway_sqs"
    echo "✓ Moved API Gateway SQS role"
fi

if resource_exists "aws_iam_role.cognito_unauthenticated"; then
    terraform state mv "aws_iam_role.cognito_unauthenticated" "module.iam.aws_iam_role.cognito_unauthenticated"
    echo "✓ Moved Cognito unauthenticated role"
fi

echo ""
echo "=== MIGRATING IAM POLICIES ==="
if resource_exists "aws_iam_role_policy.lambda_sqs"; then
    terraform state mv "aws_iam_role_policy.lambda_sqs" "module.iam.aws_iam_role_policy.lambda_sqs_access"
    echo "✓ Moved lambda SQS policy"
fi

echo ""
echo "=== MIGRATING S3 BUCKET ==="
if resource_exists "aws_s3_bucket.scraped_data"; then
    terraform state mv "aws_s3_bucket.scraped_data" "module.storage.aws_s3_bucket.scraped_data"
    echo "✓ Moved scraped data bucket"
fi

if resource_exists "aws_s3_bucket_versioning.scraped_data_versioning"; then
    terraform state mv "aws_s3_bucket_versioning.scraped_data_versioning" "module.storage.aws_s3_bucket_versioning.scraped_data_versioning"
    echo "✓ Moved bucket versioning"
fi

if resource_exists "aws_s3_bucket_server_side_encryption_configuration.scraped_data_encryption"; then
    terraform state mv "aws_s3_bucket_server_side_encryption_configuration.scraped_data_encryption" "module.storage.aws_s3_bucket_server_side_encryption_configuration.scraped_data_encryption"
    echo "✓ Moved bucket encryption"
fi

echo ""
echo "=== MIGRATING API GATEWAY ==="
if resource_exists "aws_api_gateway_rest_api.scraping_api"; then
    terraform state mv "aws_api_gateway_rest_api.scraping_api" "module.api_gateway.aws_api_gateway_rest_api.scraping_api"
    echo "✓ Moved API Gateway REST API"
fi

if resource_exists "aws_api_gateway_api_key.scraping_api_key"; then
    terraform state mv "aws_api_gateway_api_key.scraping_api_key" "module.api_gateway.aws_api_gateway_api_key.scraping_api_key[0]"
    echo "✓ Moved API Gateway API key"
fi

if resource_exists "aws_api_gateway_resource.scrape"; then
    terraform state mv "aws_api_gateway_resource.scrape" "module.api_gateway.aws_api_gateway_resource.scrape"
    echo "✓ Moved API Gateway resource"
fi

if resource_exists "aws_api_gateway_method.scrape_post"; then
    terraform state mv "aws_api_gateway_method.scrape_post" "module.api_gateway.aws_api_gateway_method.scrape_post"
    echo "✓ Moved API Gateway POST method"
fi

if resource_exists "aws_api_gateway_integration.sqs_integration"; then
    terraform state mv "aws_api_gateway_integration.sqs_integration" "module.api_gateway.aws_api_gateway_integration.sqs_integration"
    echo "✓ Moved API Gateway SQS integration"
fi

if resource_exists "aws_api_gateway_deployment.api_deployment"; then
    terraform state mv "aws_api_gateway_deployment.api_deployment" "module.api_gateway.aws_api_gateway_deployment.api_deployment"
    echo "✓ Moved API Gateway deployment"
fi

if resource_exists "aws_api_gateway_stage.prod"; then
    terraform state mv "aws_api_gateway_stage.prod" "module.api_gateway.aws_api_gateway_stage.prod"
    echo "✓ Moved API Gateway stage"
fi

echo ""
echo "=== MIGRATING LAMBDA ==="
if resource_exists "aws_lambda_function.page_scraper"; then
    terraform state mv "aws_lambda_function.page_scraper" "module.page_scraper_lambda.aws_lambda_function.scraper"
    echo "✓ Moved Lambda function"
fi

if resource_exists "aws_cloudwatch_log_group.lambda_logs"; then
    terraform state mv "aws_cloudwatch_log_group.lambda_logs" "module.page_scraper_lambda.aws_cloudwatch_log_group.lambda_logs"
    echo "✓ Moved Lambda log group"
fi

if resource_exists "aws_lambda_event_source_mapping.scraping_queue_trigger"; then
    terraform state mv "aws_lambda_event_source_mapping.scraping_queue_trigger" "module.page_scraper_lambda.aws_lambda_event_source_mapping.sqs_trigger[0]"
    echo "✓ Moved Lambda event source mapping"
fi

echo ""
echo "=== MIGRATION COMPLETE ==="
echo "✓ All resources have been migrated to modules"
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to verify no destructive changes"
echo "2. Run 'terraform apply' to apply any remaining configuration changes"
echo ""
