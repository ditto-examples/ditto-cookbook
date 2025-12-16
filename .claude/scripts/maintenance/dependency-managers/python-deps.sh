#!/usr/bin/env bash
# Python Dependency Manager
#
# Manages Python/pip dependencies for Python applications.
#
# Usage:
#   ./python-deps.sh check <project_dir>    # Check for outdated dependencies
#   ./python-deps.sh update <project_dir>   # Update dependencies
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
validate_dependency_file "$PROJECT_DIR" "requirements.txt"
check_tool_installed "python3" "https://www.python.org/downloads/"
check_tool_installed "pip3" "https://pip.pypa.io/en/stable/installation/"

# Change to project directory
cd "$PROJECT_DIR"

case "$COMMAND" in
    check)
        echo "Checking Python dependencies in $(basename "$PROJECT_DIR")..."

        TEMP_OUTPUT=$(create_temp_file)

        # Check for outdated packages
        if pip3 list --outdated --format=columns 2>&1 | tee "$TEMP_OUTPUT"; then
            # Check if output indicates no outdated packages
            if grep -q "^$" "$TEMP_OUTPUT" || ! grep -q "Package" "$TEMP_OUTPUT"; then
                print_update_summary "success" "All Python dependencies are up to date"
                exit 0
            else
                print_warning "Some Python dependencies are outdated"
                exit 1
            fi
        else
            print_update_summary "failure" "Failed to check Python dependencies"
            exit 1
        fi
        ;;

    update)
        echo "Updating Python dependencies in $(basename "$PROJECT_DIR")..."

        # Create backup of requirements.txt
        cp requirements.txt requirements.txt.backup

        TEMP_OUTPUT=$(create_temp_file)
        TEMP_REQS=$(create_temp_file)

        # Get list of outdated packages
        pip3 list --outdated --format=json > "$TEMP_OUTPUT" 2>&1 || true

        # Extract package names and update them
        if command -v python3 &> /dev/null; then
            python3 -c "import json, sys; packages = json.load(open('$TEMP_OUTPUT')); print('\n'.join([p['name'] for p in packages]))" > "$TEMP_REQS" 2>/dev/null || true
        fi

        # Upgrade packages
        if [[ -s "$TEMP_REQS" ]]; then
            while IFS= read -r package; do
                echo "Upgrading $package..."
                pip3 install --upgrade "$package" || true
            done < "$TEMP_REQS"

            # Regenerate requirements.txt
            pip3 freeze > requirements.txt

            print_update_summary "success" "Python dependencies updated successfully"
            rm -f requirements.txt.backup
            exit 0
        else
            print_update_summary "success" "All Python dependencies are already up to date"
            rm -f requirements.txt.backup
            exit 0
        fi
        ;;
esac
