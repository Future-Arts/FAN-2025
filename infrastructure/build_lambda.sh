#!/bin/bash

# Exit on any error
set -e

# Script should be run from the infrastructure directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
INFRA_DIR="$SCRIPT_DIR"

echo "Creating Lambda deployment package..."

# Create virtual environment if it doesn't exist
if [ ! -d "$SRC_DIR/.venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$SRC_DIR/.venv"
fi

# Activate virtual environment
source "$SRC_DIR/.venv/bin/activate"

# Install dependencies
echo "Installing dependencies..."
pip install -r "$SRC_DIR/requirements.txt" -t "$INFRA_DIR/lambda_package/"

# Copy source file
echo "Copying source files..."
cp "$SRC_DIR/pagescraper.py" "$INFRA_DIR/lambda_package/"

# Create zip file
echo "Creating zip file..."
cd "$INFRA_DIR/lambda_package" && zip -r ../lambda_function.zip .

# Cleanup
echo "Cleaning up..."
rm -rf "$INFRA_DIR/lambda_package"

echo "Lambda package created successfully at $INFRA_DIR/lambda_function.zip"