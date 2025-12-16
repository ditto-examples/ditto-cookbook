#!/usr/bin/env bash
# iOS Test Runner
#
# Execute tests for an iOS application.
#
# Exit codes:
#   0 - Success (tests passed or no iOS project found - skip)
#   1 - Failure (tests failed)

set -e

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"

APP_DIR="${1:-.}"

# Check for macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_warning "iOS tests require macOS, skipping"
    exit 0  # Skip gracefully on non-Mac systems
fi

# Check for iOS project markers
if [[ ! -f "$APP_DIR/Package.swift" ]] && ! ls "$APP_DIR"/*.xcodeproj &>/dev/null 2>&1; then
    print_warning "Not an iOS project, skipping: $APP_DIR"
    exit 0  # Skip gracefully
fi

print_info "Running iOS tests in $(basename "$APP_DIR")..."

# Swift Package
if [[ -f "$APP_DIR/Package.swift" ]]; then
    cd "$APP_DIR"
    if swift test; then
        print_success "iOS Swift Package tests passed"
        exit 0
    else
        print_error "iOS Swift Package tests failed"
        exit 1
    fi
fi

# Xcode project (requires scheme detection - currently skip)
if ls "$APP_DIR"/*.xcodeproj &>/dev/null 2>&1; then
    print_warning "Xcode project tests not yet implemented, skipping"
    print_info "To add support, detect test scheme and run: xcodebuild test"
    exit 0  # Skip gracefully for now
fi
