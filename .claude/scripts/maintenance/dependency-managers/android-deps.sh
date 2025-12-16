#!/usr/bin/env bash
# Android Dependency Manager
#
# Manages Android Gradle dependencies for Android applications.
#
# Usage:
#   ./android-deps.sh check <project_dir>    # Check for outdated dependencies
#   ./android-deps.sh update <project_dir>   # Update dependencies
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

# Validate build.gradle or build.gradle.kts exists
if [[ ! -f "$PROJECT_DIR/build.gradle" ]] && [[ ! -f "$PROJECT_DIR/build.gradle.kts" ]]; then
    print_error "build.gradle or build.gradle.kts not found in $PROJECT_DIR"
    exit 1
fi

# Find gradlew
GRADLEW="$PROJECT_DIR/gradlew"
if [[ ! -f "$GRADLEW" ]]; then
    GRADLEW="$PROJECT_DIR/../gradlew"
fi

if [[ ! -f "$GRADLEW" ]]; then
    print_error "gradlew not found in project or parent directory"
    echo "Please ensure gradlew wrapper is present"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

case "$COMMAND" in
    check)
        echo "Checking Android Gradle dependencies in $(basename "$PROJECT_DIR")..."

        TEMP_OUTPUT=$(create_temp_file)

        # Check for outdated dependencies using Gradle
        if "$GRADLEW" dependencies --configuration releaseRuntimeClasspath 2>&1 | tee "$TEMP_OUTPUT"; then
            print_info "Android dependency check complete"
            print_warning "Manual review recommended - check output above"
            exit 1  # Conservative approach - assume outdated until manually verified
        else
            print_update_summary "failure" "Failed to check Android dependencies"
            exit 1
        fi
        ;;

    update)
        echo "Updating Android Gradle dependencies in $(basename "$PROJECT_DIR")..."

        print_warning "Android dependencies must be updated manually in build.gradle files"
        print_info "After updating, run: $GRADLEW dependencies to verify"
        exit 1
        ;;
esac
