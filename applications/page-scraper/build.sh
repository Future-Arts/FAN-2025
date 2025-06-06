#!/bin/bash
# Modern Lambda build script with error handling and cross-platform compatibility
set -euo pipefail

# Color output for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    >&2 echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    >&2 echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    >&2 echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    >&2 echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
handle_error() {
    log_error "Build failed at line $1"
    cleanup
    exit 1
}

trap 'handle_error $LINENO' ERR

# Environment variables with defaults
BUILD_ENV=${BUILD_ENV:-"development"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
GIT_COMMIT=${GIT_COMMIT:-"unknown"}

# Use absolute paths provided by Terraform, or fall back to relative paths
if [ -n "${FAN_ROOT:-}" ]; then
    # Running from Terraform with absolute paths
    SOURCE_DIR="${SOURCE_PATH}"
    REQUIREMENTS_FILE="${FAN_ROOT}/applications/page-scraper/requirements.txt"
    OUTPUT_PATH="${OUTPUT_PATH}"
else
    # Running manually - use script directory as reference
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_DIR="$SCRIPT_DIR/src"
    REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
    
    # Handle OUTPUT_PATH - if relative, resolve from current working directory, not script directory
    if [ -n "${OUTPUT_PATH:-}" ]; then
        # If OUTPUT_PATH is relative, make it absolute from current working directory
        if [[ ! "$OUTPUT_PATH" = /* ]]; then
            OUTPUT_PATH="$(pwd)/$OUTPUT_PATH"
        fi
    else
        OUTPUT_PATH="$SCRIPT_DIR/../../infrastructure/lambda_function.zip"
    fi
fi

log_info "Build script started from: ${SCRIPT_DIR:-$PWD}"
log_info "Source directory: $SOURCE_DIR"
log_info "Requirements file: $REQUIREMENTS_FILE"
log_info "Output path: $OUTPUT_PATH"

# Detect operating system for cross-platform compatibility
detect_os() {
    case "$(uname -s)" in
        Linux*)     MACHINE=Linux;;
        Darwin*)    MACHINE=Mac;;
        CYGWIN*)    MACHINE=Cygwin;;
        MINGW*)     MACHINE=MinGw;;
        MSYS*)      MACHINE=Msys;;
        *)          MACHINE="UNKNOWN:$(uname -s)"
    esac
    log_info "Detected OS: $MACHINE"
}

# Python environment setup
setup_python_env() {
    log_info "Setting up Python environment..."
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed or not in PATH"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    log_info "Using Python version: $PYTHON_VERSION"
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "$SOURCE_DIR/.venv" ]; then
        log_info "Creating virtual environment..."
        python3 -m venv "$SOURCE_DIR/.venv"
    fi
    
    # Activate virtual environment
    case $MACHINE in
        Cygwin|MinGw|Msys)
            source "$SOURCE_DIR/.venv/Scripts/activate"
            ;;
        *)
            source "$SOURCE_DIR/.venv/bin/activate"
            ;;
    esac
    
    # Upgrade pip for consistency
    python -m pip install --upgrade pip --quiet --disable-pip-version-check
}

# Create requirements.txt if it doesn't exist
ensure_requirements() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        log_warning "requirements.txt not found, creating minimal requirements"
        cat > "$REQUIREMENTS_FILE" << EOF
requests==2.31.0
beautifulsoup4==4.12.2
boto3==1.34.0
EOF
    fi
    log_info "Requirements file exists: $REQUIREMENTS_FILE"
}

# Dependency installation with optimizations
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Create temporary build directory
    local tmp_build_dir
    tmp_build_dir=$(mktemp -d)
    log_info "Using build directory: $tmp_build_dir"
    
    # Install dependencies to build directory
    pip install -r "$REQUIREMENTS_FILE" -t "$tmp_build_dir" \
        --quiet --disable-pip-version-check --no-compile \
        --platform linux_x86_64 --only-binary=:all: --no-deps || {
        log_warning "Platform-specific install failed, trying generic install..."
        pip install -r "$REQUIREMENTS_FILE" -t "$tmp_build_dir" \
            --quiet --disable-pip-version-check --no-compile
    }

    echo "$tmp_build_dir"
}

# Source code copying with validation
copy_source_code() {
    local build_dir="$1"
    log_info "Copying source code..."
    
    # Check if source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        exit 1
    fi
    
    # Copy Python source files
    find "$SOURCE_DIR" -name "*.py" -exec cp {} "$build_dir/" \;
    
    # Validate main handler exists
    if [ ! -f "$build_dir/pagescraper.py" ]; then
        log_error "Main handler file (pagescraper.py) not found"
        exit 1
    fi
    
    # Add build metadata
    cat > "$build_dir/build_info.json" << EOF
{
    "build_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "build_env": "$BUILD_ENV",
    "git_commit": "$GIT_COMMIT",
    "python_version": "$PYTHON_VERSION",
    "machine": "$MACHINE"
}
EOF
    
    log_success "Source code copied successfully"
}

# Package optimization
optimize_package() {
    local build_dir="$1"
    log_info "Optimizing package..."
    
    # Remove unnecessary files to reduce package size
    find "$build_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$build_dir" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
    find "$build_dir" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    find "$build_dir" -type f -name "*.pyc" -delete 2>/dev/null || true
    find "$build_dir" -type f -name "*.pyo" -delete 2>/dev/null || true
    find "$build_dir" -type f -name "*.pyd" -delete 2>/dev/null || true
    find "$build_dir" -type f -name ".DS_Store" -delete 2>/dev/null || true
    
    # Remove test directories
    find "$build_dir" -type d -name "test*" -exec rm -rf {} + 2>/dev/null || true
    find "$build_dir" -type d -name "*test*" -exec rm -rf {} + 2>/dev/null || true
    
    log_success "Package optimized"
}

# ZIP creation with validation
create_zip_package() {
    local build_dir="$1"
    log_info "Creating deployment package..."
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    
    # Remove existing package
    [ -f "$OUTPUT_PATH" ] && rm -f "$OUTPUT_PATH"
    
    # Create ZIP package
    cd "$build_dir"
    
    if command -v zip &> /dev/null; then
        zip -r "$OUTPUT_PATH" . -x "*.pyc" "*/__pycache__/*" > /dev/null
    else
        # Fallback for systems without zip
        case $MACHINE in
            Mac|Linux)
                tar -czf "${OUTPUT_PATH%.zip}.tar.gz" .
                log_warning "Created tar.gz instead of zip (zip command not available)"
                ;;
            *)
                log_error "No suitable archive tool found"
                exit 1
                ;;
        esac
    fi
    
    cd - > /dev/null
    
    # Validate package was created
    if [ ! -f "$OUTPUT_PATH" ]; then
        log_error "Failed to create deployment package"
        exit 1
    fi
    
    # Check package size
    PACKAGE_SIZE=$(du -h "$OUTPUT_PATH" 2>/dev/null | cut -f1 || echo 'unknown')
    log_success "Deployment package created: $PACKAGE_SIZE"
    
    # Warn if package is too large
    PACKAGE_SIZE_BYTES=$(stat -f%z "$OUTPUT_PATH" 2>/dev/null || stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    if [ "$PACKAGE_SIZE_BYTES" -gt 52428800 ]; then  # 50MB
        log_warning "Package size ($PACKAGE_SIZE) exceeds 50MB, consider optimization"
    fi
}

# Cleanup function
cleanup() {
    if [ -n "${BUILD_DIR:-}" ] && [ -d "$BUILD_DIR" ]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Deactivate virtual environment if active
    if [ -n "${VIRTUAL_ENV:-}" ]; then
        deactivate 2>/dev/null || true
    fi
}

# Main build process
main() {
    log_info "Starting Lambda build process..."
    log_info "Build environment: $BUILD_ENV"
    log_info "Git commit: $GIT_COMMIT"
    log_info "AWS region: $AWS_REGION"
    
    detect_os
    ensure_requirements
    setup_python_env
    
    BUILD_DIR=$(install_dependencies)
    copy_source_code "$BUILD_DIR"
    optimize_package "$BUILD_DIR"
    create_zip_package "$BUILD_DIR"
    
    cleanup
    
    log_success "Lambda build completed successfully!"
    log_info "Package location: $OUTPUT_PATH"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
