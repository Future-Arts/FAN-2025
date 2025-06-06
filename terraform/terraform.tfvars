# terraform.tfvars - Start with current working config
environment = "prod"
aws_region  = "us-west-2"

# Keep current Lambda settings (they're working)
lambda_memory_size = 512
lambda_timeout     = 300
lambda_use_arm64   = true

# Add 3D features gradually
enable_3d_optimizations = true
max_nodes_per_website   = "500"
enable_progressive_loading = false  # Start disabled

# Keep current DynamoDB settings
dynamodb_billing_mode = "PAY_PER_REQUEST"

# Don't enable monitoring yet
enable_enhanced_monitoring = false
