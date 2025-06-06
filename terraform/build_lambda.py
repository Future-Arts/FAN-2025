#!/usr/bin/env python3
"""
Lambda build automation script for FAN-2025 project.
This script handles dependency installation and packaging for Lambda deployment.
"""

import os
import sys
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
import hashlib

def log(message):
    """Simple logging function"""
    print(f"[BUILD] {message}", file=sys.stderr)

def get_fan_root():
    """Get the FAN-2025 root directory"""
    # Script is in terraform/, so go up one level
    return Path(__file__).parent.parent.absolute()

def calculate_source_hash(source_dir, requirements_file):
    """Calculate hash of source files and requirements"""
    hasher = hashlib.sha256()
    
    # Hash Python files
    for py_file in sorted(Path(source_dir).glob("*.py")):
        with open(py_file, 'rb') as f:
            hasher.update(f.read())
    
    # Hash requirements file if it exists
    if Path(requirements_file).exists():
        with open(requirements_file, 'rb') as f:
            hasher.update(f.read())
    
    return hasher.hexdigest()

def install_dependencies(requirements_file, target_dir):
    """Install Python dependencies to target directory"""
    if not Path(requirements_file).exists():
        log(f"Requirements file not found: {requirements_file}")
        return False
    
    log(f"Installing dependencies from {requirements_file}")
    cmd = [
        sys.executable, "-m", "pip", "install",
        "-r", str(requirements_file),
        "-t", str(target_dir),
        "--quiet",
        "--no-compile",
        "--platform", "linux_x86_64",
        "--only-binary=:all:",
        "--no-deps"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        log("Dependencies installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        log(f"Dependency installation failed with platform-specific install, trying generic...")
        # Fallback to generic install
        cmd_fallback = [
            sys.executable, "-m", "pip", "install",
            "-r", str(requirements_file),
            "-t", str(target_dir),
            "--quiet",
            "--no-compile"
        ]
        try:
            subprocess.run(cmd_fallback, capture_output=True, text=True, check=True)
            log("Dependencies installed successfully (generic)")
            return True
        except subprocess.CalledProcessError as e2:
            log(f"Dependency installation failed: {e2.stderr}")
            return False

def copy_source_files(source_dir, target_dir):
    """Copy Python source files to target directory"""
    source_path = Path(source_dir)
    target_path = Path(target_dir)
    
    if not source_path.exists():
        log(f"Source directory not found: {source_dir}")
        return False
    
    log(f"Copying source files from {source_dir}")
    for py_file in source_path.glob("*.py"):
        shutil.copy2(py_file, target_path)
        log(f"Copied {py_file.name}")
    
    return True

def cleanup_package(target_dir):
    """Remove unnecessary files to reduce package size"""
    target_path = Path(target_dir)
    
    # Remove common unnecessary files/directories
    patterns_to_remove = [
        "**/__pycache__",
        "**/*.pyc",
        "**/*.pyo",
        "**/*.pyd",
        "**/.DS_Store",
        "**/test*",
        "**/*.dist-info",
        "**/*.egg-info"
    ]
    
    for pattern in patterns_to_remove:
        for item in target_path.glob(pattern):
            if item.is_dir():
                shutil.rmtree(item, ignore_errors=True)
            else:
                item.unlink(missing_ok=True)

def create_zip_package(source_dir, output_file):
    """Create ZIP package from source directory"""
    output_path = Path(output_file)
    source_path = Path(source_dir)
    
    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Remove existing package
    if output_path.exists():
        output_path.unlink()
    
    log(f"Creating ZIP package: {output_file}")
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for file_path in source_path.rglob('*'):
            if file_path.is_file():
                arcname = file_path.relative_to(source_path)
                zipf.write(file_path, arcname)
                
    # Check package size
    size_mb = output_path.stat().st_size / (1024 * 1024)
    log(f"Package created successfully: {size_mb:.1f}MB")
    
    if size_mb > 50:
        log("WARNING: Package size exceeds 50MB")
    
    return True

def main():
    """Main build function"""
    fan_root = get_fan_root()
    
    # Default paths relative to FAN-2025 root
    source_dir = fan_root / "applications" / "page-scraper" / "src"
    requirements_file = fan_root / "applications" / "page-scraper" / "requirements.txt"
    output_file = fan_root / "infrastructure" / "lambda_function.zip"
    
    # Override with environment variables if provided
    if "SOURCE_PATH" in os.environ:
        source_dir = Path(os.environ["SOURCE_PATH"])
    if "REQUIREMENTS_FILE" in os.environ:
        requirements_file = Path(os.environ["REQUIREMENTS_FILE"])
    if "OUTPUT_PATH" in os.environ:
        output_file = Path(os.environ["OUTPUT_PATH"])
    
    log(f"FAN-2025 Root: {fan_root}")
    log(f"Source directory: {source_dir}")
    log(f"Requirements file: {requirements_file}")
    log(f"Output file: {output_file}")
    
    # Calculate source hash for change detection
    source_hash = calculate_source_hash(source_dir, requirements_file)
    log(f"Source hash: {source_hash}")
    
    # Create temporary build directory
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Install dependencies
        if not install_dependencies(requirements_file, temp_path):
            log("Failed to install dependencies")
            return 1
        
        # Copy source files
        if not copy_source_files(source_dir, temp_path):
            log("Failed to copy source files")
            return 1
        
        # Cleanup unnecessary files
        cleanup_package(temp_path)
        
        # Create ZIP package
        if not create_zip_package(temp_path, output_file):
            log("Failed to create ZIP package")
            return 1
    
    log("Build completed successfully")
    
    # Output hash for Terraform
    print(json.dumps({"hash": source_hash}))
    return 0

if __name__ == "__main__":
    sys.exit(main())