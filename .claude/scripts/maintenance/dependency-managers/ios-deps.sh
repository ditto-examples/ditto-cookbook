#!/usr/bin/env bash
# iOS Dependency Manager
#
# Manages iOS CocoaPods dependencies for iOS applications.
#
# Usage:
#   ./ios-deps.sh check <project_dir>    # Check for outdated dependencies
#   ./ios-deps.sh update <project_dir>   # Update dependencies
#
# Exit codes:
#   0 - Success (all up to date or updated successfully)
#   1 - Failure (outdated dependencies found or update failed)

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse arguments
COMMAND="${1:-check}"
PROJECT_DIR="${2:-.}"

# Validate inputs
validate_command "$COMMAND" "check" "update"
validate_project_dir "$PROJECT_DIR"
validate_dependency_file "$PROJECT_DIR" "Podfile"
check_tool_installed "pod" "https://guides.cocoapods.org/using/getting-started.html"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print_warning "iOS dependency management is only supported on macOS"
    print_info "Skipping iOS dependency check"
    exit 0
fi

# Change to project directory
cd "$PROJECT_DIR"

case "$COMMAND" in
    check)
        echo "Checking iOS CocoaPods dependencies in $(basename "$PROJECT_DIR")..."

        TEMP_OUTPUT=$(create_temp_file)

        # Check for outdated pods
        if pod outdated 2>&1 | tee "$TEMP_OUTPUT"; then
            if grep -q "All dependencies are up-to-date" "$TEMP_OUTPUT" || \
               grep -q "Nothing to update" "$TEMP_OUTPUT"; then
                print_update_summary "success" "All iOS dependencies are up to date"
                exit 0
            else
                print_warning "Some iOS dependencies are outdated"
                exit 1
            fi
        else
            print_update_summary "failure" "Failed to check iOS dependencies"
            exit 1
        fi
        ;;

    update)
        echo "Updating iOS CocoaPods dependencies in $(basename "$PROJECT_DIR")..."

        # Run pod update
        if pod update; then
            print_update_summary "success" "iOS dependencies updated successfully"
            exit 0
        else
            print_update_summary "failure" "Failed to update iOS dependencies"
            exit 1
        fi
        ;;
esac
