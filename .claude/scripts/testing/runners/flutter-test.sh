#!/usr/bin/env bash
# Flutter Test Runner - Execute tests for a Flutter application
#
# This script runs tests for a single Flutter app. It can be called directly
# or used by the test orchestrator for parallel execution.
#
# Usage:
#   ./flutter-test.sh <app-directory>
#
# Exit codes:
#   0 - Tests passed or no tests to run
#   1 - Tests failed or validation errors

set -e

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"

# Validate arguments
if [[ $# -lt 1 ]]; then
    print_error "Usage: $0 <app-directory>"
    exit 1
fi

APP_DIR="$1"
APP_NAME=$(get_app_name "$APP_DIR")

# Validate Flutter is available
if ! command -v flutter &> /dev/null; then
    print_error "Flutter not found in PATH"
    print_info "Install Flutter: https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Validate app directory exists
if [[ ! -d "$APP_DIR" ]]; then
    print_error "App directory not found: $APP_DIR"
    exit 1
fi

# Validate pubspec.yaml exists
if [[ ! -f "$APP_DIR/pubspec.yaml" ]]; then
    print_error "Not a Flutter app (missing pubspec.yaml): $APP_DIR"
    exit 1
fi

# Change to app directory
cd "$APP_DIR"

# Check if test directory exists
if [[ ! -d "test" ]]; then
    print_warning "No test directory found for $APP_NAME"
    print_info "Create test/ directory to add tests"
    exit 0  # Not a failure - just no tests to run
fi

# Print test start
print_info "Testing Flutter app: $APP_NAME"

# Run flutter pub get to ensure dependencies are available
if ! flutter pub get > /dev/null 2>&1; then
    print_error "Failed to get dependencies for $APP_NAME"
    exit 1
fi

# Run tests (no coverage per requirements)
if flutter test; then
    print_success "Tests passed: $APP_NAME"
    exit 0
else
    print_error "Tests failed: $APP_NAME"
    exit 1
fi
