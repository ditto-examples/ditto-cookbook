#!/usr/bin/env bash
# Android Test Runner
#
# Execute tests for an Android application.
#
# Exit codes:
#   0 - Success (tests passed or no Android project found - skip)
#   1 - Failure (tests failed)

set -e

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"

APP_DIR="${1:-.}"

# Check for Android project markers
if [[ ! -f "$APP_DIR/build.gradle" ]] && [[ ! -f "$APP_DIR/build.gradle.kts" ]]; then
    print_warning "Not an Android project, skipping: $APP_DIR"
    exit 0  # Skip gracefully, don't fail
fi

# Find gradlew
GRADLEW="$APP_DIR/gradlew"
if [[ ! -f "$GRADLEW" ]]; then
    GRADLEW="$APP_DIR/../gradlew"
fi

if [[ ! -f "$GRADLEW" ]]; then
    print_warning "gradlew not found, skipping Android tests"
    exit 0  # Skip gracefully
fi

print_info "Running Android tests in $(basename "$APP_DIR")..."

# Run Android tests
if "$GRADLEW" test; then
    print_success "Android tests passed"
    exit 0
else
    print_error "Android tests failed"
    exit 1
fi
