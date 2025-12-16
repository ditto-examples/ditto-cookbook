#!/usr/bin/env bash
# Flutter Dependency Manager
#
# Manages Flutter/Dart dependencies for Flutter applications.
#
# Usage:
#   ./flutter-deps.sh check <project_dir>    # Check for outdated dependencies
#   ./flutter-deps.sh update <project_dir>   # Update dependencies
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
validate_dependency_file "$PROJECT_DIR" "pubspec.yaml"
check_tool_installed "flutter" "https://flutter.dev/docs/get-started/install"

# Change to project directory
cd "$PROJECT_DIR"

case "$COMMAND" in
    check)
        echo "Checking Flutter dependencies in $(basename "$PROJECT_DIR")..."

        # Create temp file for output
        TEMP_OUTPUT=$(create_temp_file)

        # Run flutter pub outdated
        if flutter pub outdated --color 2>&1 | tee "$TEMP_OUTPUT"; then
            if is_up_to_date "$TEMP_OUTPUT"; then
                print_update_summary "success" "All Flutter dependencies are up to date"
                exit 0
            else
                echo ""
                print_warning "Some Flutter dependencies are outdated"
                exit 1
            fi
        else
            print_update_summary "failure" "Failed to check Flutter dependencies"
            exit 1
        fi
        ;;

    update)
        echo "Updating Flutter dependencies in $(basename "$PROJECT_DIR")..."

        # Run flutter pub upgrade
        if flutter pub upgrade; then
            print_update_summary "success" "Flutter dependencies updated successfully"

            # Run flutter pub get to ensure everything is resolved
            echo ""
            echo "Resolving dependencies..."
            flutter pub get

            print_update_summary "success" "Complete! Dependencies are now up to date"
            exit 0
        else
            print_update_summary "failure" "Failed to update Flutter dependencies"
            exit 1
        fi
        ;;
esac
