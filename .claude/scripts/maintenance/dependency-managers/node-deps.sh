#!/usr/bin/env bash
# Node.js Dependency Manager
#
# Manages Node.js/npm dependencies for web and Node.js applications.
# Supports npm, yarn, and pnpm package managers.
#
# Usage:
#   ./node-deps.sh check <project_dir>    # Check for outdated dependencies
#   ./node-deps.sh update <project_dir>   # Update dependencies
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
validate_dependency_file "$PROJECT_DIR" "package.json"
check_tool_installed "node" "https://nodejs.org/"

# Detect package manager (npm, yarn, or pnpm)
detect_package_manager() {
    if [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$PROJECT_DIR/yarn.lock" ]]; then
        echo "yarn"
    else
        echo "npm"
    fi
}

PACKAGE_MANAGER=$(detect_package_manager)

# Verify package manager is installed
check_tool_installed "$PACKAGE_MANAGER" "https://nodejs.org/"

# Change to project directory
cd "$PROJECT_DIR"

case "$COMMAND" in
    check)
        echo "Checking Node.js dependencies in $(basename "$PROJECT_DIR") using $PACKAGE_MANAGER..."

        case "$PACKAGE_MANAGER" in
            npm)
                if npm outdated; then
                    print_update_summary "success" "All npm dependencies are up to date"
                    exit 0
                else
                    # npm outdated exits with 1 if outdated packages exist
                    if [[ $? -eq 1 ]]; then
                        print_warning "Some npm dependencies are outdated"
                        exit 1
                    fi
                fi
                ;;
            yarn)
                TEMP_OUTPUT=$(create_temp_file)
                if yarn outdated 2>&1 | tee "$TEMP_OUTPUT"; then
                    print_update_summary "success" "All yarn dependencies are up to date"
                    exit 0
                else
                    print_warning "Some yarn dependencies are outdated"
                    exit 1
                fi
                ;;
            pnpm)
                TEMP_OUTPUT=$(create_temp_file)
                if pnpm outdated 2>&1 | tee "$TEMP_OUTPUT"; then
                    print_update_summary "success" "All pnpm dependencies are up to date"
                    exit 0
                else
                    print_warning "Some pnpm dependencies are outdated"
                    exit 1
                fi
                ;;
        esac
        ;;

    update)
        echo "Updating Node.js dependencies in $(basename "$PROJECT_DIR") using $PACKAGE_MANAGER..."

        case "$PACKAGE_MANAGER" in
            npm)
                if npm update; then
                    print_update_summary "success" "npm dependencies updated successfully"
                    exit 0
                else
                    print_update_summary "failure" "Failed to update npm dependencies"
                    exit 1
                fi
                ;;
            yarn)
                if yarn upgrade; then
                    print_update_summary "success" "yarn dependencies updated successfully"
                    exit 0
                else
                    print_update_summary "failure" "Failed to update yarn dependencies"
                    exit 1
                fi
                ;;
            pnpm)
                if pnpm update; then
                    print_update_summary "success" "pnpm dependencies updated successfully"
                    exit 0
                else
                    print_update_summary "failure" "Failed to update pnpm dependencies"
                    exit 1
                fi
                ;;
        esac
        ;;
esac
