#!/usr/bin/env bash
# Common Dependency Manager Functions
#
# This library provides shared functionality for all platform-specific
# dependency managers. Source this file at the beginning of each
# platform manager script.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/common.sh"

# Get project root directory
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/../../.." && pwd
}

# Source test helpers for output formatting
PROJECT_ROOT=$(get_project_root)
source "$PROJECT_ROOT/.claude/scripts/testing/utils/test-helpers.sh"

# Temporary file management
TEMP_FILES=()

# Create temporary file with automatic cleanup tracking
create_temp_file() {
    local temp_file=$(mktemp)
    TEMP_FILES+=("$temp_file")
    echo "$temp_file"
}

# Cleanup all temporary files
cleanup_temp_files() {
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

# Set up automatic cleanup on script exit
trap cleanup_temp_files EXIT ERR INT TERM

# Validate command is one of the allowed commands
# Usage: validate_command "$cmd" "check" "update"
validate_command() {
    local cmd=$1
    shift
    local valid_cmds=("$@")

    for valid in "${valid_cmds[@]}"; do
        [[ "$cmd" == "$valid" ]] && return 0
    done

    # Build usage string
    local usage_str="${valid_cmds[0]}"
    for ((i=1; i<${#valid_cmds[@]}; i++)); do
        usage_str="$usage_str|${valid_cmds[$i]}"
    done

    echo "Usage: $0 {$usage_str} <project_dir>"
    exit 1
}

# Validate project directory exists
validate_project_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        print_error "Project directory not found: $dir"
        exit 1
    fi
}

# Validate dependency file exists in project directory
validate_dependency_file() {
    local dir=$1
    local file=$2
    if [[ ! -f "$dir/$file" ]]; then
        print_error "$file not found in $dir"
        exit 1
    fi
}

# Check if required tool is installed
check_tool_installed() {
    local tool=$1
    local install_url=$2
    if ! command -v "$tool" &> /dev/null; then
        print_error "$tool is not installed or not in PATH"
        echo "Please install $tool: $install_url"
        exit 1
    fi
}

# Print update summary with consistent formatting
print_update_summary() {
    local status=$1  # "success" or "failure"
    local message=$2

    echo ""
    if [[ "$status" == "success" ]]; then
        print_success "$message"
    else
        print_error "$message"
    fi
}

# Check if output contains "up to date" indicators
is_up_to_date() {
    local output_file=$1

    if grep -q "All dependencies are up to date" "$output_file" || \
       grep -q "No dependencies" "$output_file" || \
       grep -q "all dependencies up to date" "$output_file" || \
       grep -q "All packages are up-to-date" "$output_file"; then
        return 0
    fi
    return 1
}
