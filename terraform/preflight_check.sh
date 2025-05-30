#!/bin/bash
# Pre-flight check script to verify everything is ready for terraform apply

echo "=== Pre-flight Check for Terraform Deployment ==="

# Check 1: build_lambda.sh exists and is executable
echo "1. Checking build_lambda.sh..."
if [ -f "build_lambda.sh" ] && [ -x "build_lambda.sh" ]; then
    echo "   ✓ build_lambda.sh exists and is executable"
    file_size=$(wc -c < build_lambda.sh)
    if [ "$file_size" -gt 100 ]; then
        echo "   ✓ File has content ($file_size bytes)"
    else
        echo "   ✗ File appears to be empty or very small ($file_size bytes)"
        exit 1
    fi
else
    echo "   ✗ build_lambda.sh missing or not executable"
    echo "   Run: chmod +x build_lambda.sh"
    exit 1
fi

# Check 2: Infrastructure directory
echo "2. Checking infrastructure directory..."
if [ -d "../infrastructure" ]; then
    echo "   ✓ ../infrastructure directory exists"
else
    echo "   ✓ Creating ../infrastructure directory"
    mkdir -p ../infrastructure
fi

# Check 3: Python script (optional, will be created if missing)
echo "3. Checking Python script..."
if [ -f "../infrastructure/pagescraper.py" ]; then
    echo "   ✓ pagescraper.py exists"
else
    echo "   ⚠ pagescraper.py missing (will create placeholder)"
fi

# Check 4: AWS credentials
echo "4. Checking AWS credentials..."
if aws sts get-caller-identity --profile Developer-024611159954 >/dev/null 2>&1; then
    echo "   ✓ AWS profile credentials work"
elif aws sts get-caller-identity >/dev/null 2>&1; then
    echo "   ✓ AWS environment credentials work"
else
    echo "   ✗ AWS credentials not working"
    echo "   Check your credentials with: aws sts get-caller-identity"
    exit 1
fi

# Check 5: Required tools
echo "5. Checking required tools..."
command -v terraform >/dev/null 2>&1 && echo "   ✓ terraform" || (echo "   ✗ terraform not found" && exit 1)
command -v python3 >/dev/null 2>&1 && echo "   ✓ python3" || (echo "   ✗ python3 not found" && exit 1)
command -v pip >/dev/null 2>&1 && echo "   ✓ pip" || (echo "   ✗ pip not found" && exit 1)
command -v zip >/dev/null 2>&1 && echo "   ✓ zip" || (echo "   ✗ zip not found" && exit 1)

# Check 6: Test build script
echo "6. Testing build script..."
if ./build_lambda.sh >/dev/null 2>&1; then
    echo "   ✓ Build script runs successfully"
    if [ -f "../infrastructure/lambda_function.zip" ]; then
        zip_size=$(du -h ../infrastructure/lambda_function.zip | cut -f1)
        echo "   ✓ Lambda package created ($zip_size)"
    else
        echo "   ✗ Lambda package not created"
        exit 1
    fi
else
    echo "   ✗ Build script failed"
    echo "   Run: ./build_lambda.sh"
    exit 1
fi

echo ""
echo "=== ✓ All checks passed! Ready for terraform apply ==="
echo ""
echo "Next steps:"
echo "1. terraform plan"
echo "2. terraform apply"
