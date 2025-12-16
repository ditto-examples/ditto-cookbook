#!/usr/bin/env bash
# Web Test Runner
#
# Execute tests for a Web/Node.js application.
#
# Exit codes:
#   0 - Success (tests passed or no Web project found - skip)
#   1 - Failure (tests failed)

set -e

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"

APP_DIR="${1:-.}"

# Check for Web/Node.js project markers
if [[ ! -f "$APP_DIR/package.json" ]]; then
    print_warning "Not a Node.js/Web project, skipping: $APP_DIR"
    exit 0  # Skip gracefully
fi

print_info "Running Web tests in $(basename "$APP_DIR")..."

cd "$APP_DIR"

# Detect package manager and run tests
if [[ -f "pnpm-lock.yaml" ]]; then
    if pnpm test; then
        print_success "Web tests passed (pnpm)"
        exit 0
    else
        print_error "Web tests failed (pnpm)"
        exit 1
    fi
elif [[ -f "yarn.lock" ]]; then
    if yarn test; then
        print_success "Web tests passed (yarn)"
        exit 0
    else
        print_error "Web tests failed (yarn)"
        exit 1
    fi
else
    if npm test; then
        print_success "Web tests passed (npm)"
        exit 0
    else
        print_error "Web tests failed (npm)"
        exit 1
    fi
fi
