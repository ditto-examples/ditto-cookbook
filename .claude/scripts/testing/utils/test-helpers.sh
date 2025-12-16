#!/usr/bin/env bash
# Test Helpers - Shared utility functions for test scripts
#
# This file provides common helper functions used across all test scripts.
# Source this file at the beginning of test runner scripts.

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Print functions with consistent formatting
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if directory is a valid app directory
is_valid_app_dir() {
    local dir=$1
    [[ -d "$dir" ]] && [[ "$(basename "$dir")" != "." ]] && [[ "$(basename "$dir")" != ".." ]]
}

# Get app name from path
get_app_name() {
    local app_path=$1
    basename "$app_path"
}

# Create temporary directory for logs
create_temp_dir() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        mktemp -d -t test-all
    else
        # Linux
        mktemp -d
    fi
}

# Cleanup temporary directory
cleanup_temp_dir() {
    local temp_dir=$1
    if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
    fi
}

# Detect operating system
detect_os() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

# Detect platform for a project directory
detect_platform() {
    local dir=$1

    # Flutter: check for pubspec.yaml
    [[ -f "$dir/pubspec.yaml" ]] && echo "flutter" && return 0

    # iOS Native: check for Package.swift or .xcodeproj
    if [[ -f "$dir/Package.Swift" ]]; then
        echo "ios" && return 0
    fi
    if ls "$dir"/*.xcodeproj &>/dev/null 2>&1; then
        echo "ios" && return 0
    fi

    # iOS CocoaPods: check for Podfile
    [[ -f "$dir/Podfile" ]] && echo "ios" && return 0

    # Android Native: check for build.gradle
    if [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
        echo "android" && return 0
    fi

    # Web/Node.js: check for package.json
    [[ -f "$dir/package.json" ]] && echo "node" && return 0

    # Python: check for requirements.txt
    [[ -f "$dir/requirements.txt" ]] && echo "python" && return 0

    echo "unknown" && return 1
}

# Error handling functions

# Die with error message and optional exit code
die() {
    print_error "$1"
    exit "${2:-1}"
}

# Require command exists
require_command() {
    local cmd=$1
    local install_url=$2
    if ! command -v "$cmd" &> /dev/null; then
        die "Required command not found: $cmd\nInstall: $install_url" 1
    fi
}

# Require file exists
require_file() {
    local file=$1
    local error_msg=${2:-"File not found: $file"}
    [[ -f "$file" ]] || die "$error_msg" 1
}

# Require directory exists
require_dir() {
    local dir=$1
    local error_msg=${2:-"Directory not found: $dir"}
    [[ -d "$dir" ]] || die "$error_msg" 1
}
