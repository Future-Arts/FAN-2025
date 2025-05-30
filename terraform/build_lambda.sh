#!/bin/bash
set -e

echo "Building Lambda deployment package..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$SCRIPT_DIR/../infrastructure"

cd "$INFRASTRUCTURE_DIR"

# Clean up previous builds
rm -rf lambda_package lambda_function.zip

# Create a clean directory for the package
mkdir lambda_package
cd lambda_package

# Check if pagescraper.py exists, if not create a placeholder
if [ ! -f "../pagescraper.py" ]; then
    echo "Warning: pagescraper.py not found. Creating placeholder..."
    cat > pagescraper.py << 'PYEOF'
import json

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps('Placeholder Lambda function - please replace with actual code')
    }
PYEOF
else
    # Copy your Python script
    cp ../pagescraper.py .
fi

# Copy requirements.txt
cp ../requirements.txt .

# Install dependencies locally (suppress pip warnings)
echo "Installing Python dependencies..."
pip install -r requirements.txt -t . --quiet --disable-pip-version-check

# Remove unnecessary files to reduce package size
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
rm requirements.txt

# Create the deployment package
echo "Creating deployment package..."
zip -r ../lambda_function.zip . -x "*.pyc" "*/__pycache__/*" > /dev/null

# Clean up build directory
cd ..
rm -rf lambda_package

echo "Lambda function packaged successfully!"
echo "Package size: $(du -h lambda_function.zip 2>/dev/null | cut -f1 || echo 'unknown')"
