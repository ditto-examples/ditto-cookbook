#!/bin/bash

# Architecture Documentation Check Script
# Verifies that architecture documentation is up-to-date with code changes

set -eo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Architecture Documentation Check ===${NC}\n"

# Get the repository root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# Initialize counters
WARNINGS=0
INFO=0

# Function to check if architecture documentation exists for a directory
check_architecture_doc() {
    local dir=$1
    local type=$2  # "app" or "tool"

    if [ ! -f "$dir/ARCHITECTURE.md" ]; then
        echo -e "${YELLOW}⚠ Warning: Missing ARCHITECTURE.md in $dir${NC}"
        echo -e "  ${BLUE}ℹ Create one using: cp docs/ARCHITECTURE_TEMPLATE.md $dir/ARCHITECTURE.md${NC}"
        ((WARNINGS++))
        return 1
    fi

    return 0
}

# Function to check if architecture doc was updated recently
check_architecture_freshness() {
    local dir=$1
    local arch_file="$dir/ARCHITECTURE.md"

    if [ ! -f "$arch_file" ]; then
        return 1
    fi

    # Get last modified time of ARCHITECTURE.md
    local arch_modified=$(stat -f %m "$arch_file" 2>/dev/null || stat -c %Y "$arch_file" 2>/dev/null || echo 0)

    # Get last modified time of source files (excluding tests)
    local latest_source=0

    # Find source files (adjust patterns based on your tech stack)
    while IFS= read -r -d '' file; do
        local file_modified=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
        if [ "$file_modified" -gt "$latest_source" ]; then
            latest_source=$file_modified
        fi
    done < <(find "$dir" -type f \( -name "*.dart" -o -name "*.js" -o -name "*.ts" -o -name "*.py" \) ! -path "*/test/*" ! -path "*/.*" -print0 2>/dev/null)

    # If source files are newer than architecture doc
    if [ "$latest_source" -gt "$arch_modified" ] && [ "$latest_source" -ne 0 ]; then
        echo -e "${YELLOW}⚠ Warning: ARCHITECTURE.md in $dir may be outdated${NC}"
        echo -e "  ${BLUE}ℹ Source files modified after architecture documentation${NC}"
        ((WARNINGS++))
        return 1
    fi

    return 0
}

# Function to check if architecture doc follows template structure
check_architecture_structure() {
    local arch_file=$1

    # Required sections in architecture documentation
    local required_sections=(
        "## Overview"
        "## Technology Stack"
        "## Project Structure"
        "## Core Components"
        "## Ditto Integration"
        "## Testing Strategy"
    )

    local missing_sections=()

    for section in "${required_sections[@]}"; do
        if ! grep -q "^${section}" "$arch_file"; then
            missing_sections+=("$section")
        fi
    done

    if [ ${#missing_sections[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ Warning: $arch_file missing recommended sections:${NC}"
        for section in "${missing_sections[@]}"; do
            echo -e "  - $section"
        done
        echo -e "  ${BLUE}ℹ Consider adding these sections for completeness${NC}"
        ((WARNINGS++))
        return 1
    fi

    return 0
}

# Function to update central architecture index
update_architecture_index() {
    local central_doc="docs/ARCHITECTURE.md"

    if [ ! -f "$central_doc" ]; then
        echo -e "${YELLOW}⚠ Warning: Central architecture documentation not found at $central_doc${NC}"
        ((WARNINGS++))
        return 1
    fi

    echo -e "${BLUE}ℹ Checking if central architecture index needs updating...${NC}"
    ((INFO++))

    # Create temporary directory for summaries
    mkdir -p docs/architecture

    # Generate summaries for apps
    if [ -d "apps" ]; then
        for app_dir in apps/*/; do
            if [ -d "$app_dir" ] && [ -f "$app_dir/ARCHITECTURE.md" ]; then
                local app_name=$(basename "$app_dir")
                local summary_file="docs/architecture/${app_name}-summary.md"

                # Extract overview section from ARCHITECTURE.md
                echo "# ${app_name} Architecture Summary" > "$summary_file"
                echo "" >> "$summary_file"
                sed -n '/## Overview/,/## /p' "$app_dir/ARCHITECTURE.md" | sed '$d' >> "$summary_file"

                echo -e "${GREEN}✓ Generated summary for app: ${app_name}${NC}"
            fi
        done
    fi

    # Generate summaries for tools
    if [ -d "tools" ]; then
        for tool_dir in tools/*/; do
            if [ -d "$tool_dir" ] && [ -f "$tool_dir/ARCHITECTURE.md" ]; then
                local tool_name=$(basename "$tool_dir")
                local summary_file="docs/architecture/${tool_name}-summary.md"

                # Extract overview section from ARCHITECTURE.md
                echo "# ${tool_name} Architecture Summary" > "$summary_file"
                echo "" >> "$summary_file"
                sed -n '/## Overview/,/## /p' "$tool_dir/ARCHITECTURE.md" | sed '$d' >> "$summary_file"

                echo -e "${GREEN}✓ Generated summary for tool: ${tool_name}${NC}"
            fi
        done
    fi

    return 0
}

echo -e "${BLUE}[1/4] Checking for architecture documentation in apps/${NC}"

if [ -d "apps" ]; then
    for app_dir in apps/*/; do
        if [ -d "$app_dir" ]; then
            app_name=$(basename "$app_dir")
            echo -e "\n  Checking: apps/$app_name"

            if check_architecture_doc "$app_dir" "app"; then
                echo -e "  ${GREEN}✓ ARCHITECTURE.md exists${NC}"
                check_architecture_freshness "$app_dir"
                check_architecture_structure "$app_dir/ARCHITECTURE.md"
            fi
        fi
    done
else
    echo -e "  ${BLUE}ℹ No apps directory found${NC}"
    ((INFO++))
fi

echo -e "\n${BLUE}[2/4] Checking for architecture documentation in tools/${NC}"

if [ -d "tools" ]; then
    for tool_dir in tools/*/; do
        if [ -d "$tool_dir" ]; then
            tool_name=$(basename "$tool_dir")
            echo -e "\n  Checking: tools/$tool_name"

            if check_architecture_doc "$tool_dir" "tool"; then
                echo -e "  ${GREEN}✓ ARCHITECTURE.md exists${NC}"
                check_architecture_freshness "$tool_dir"
                check_architecture_structure "$tool_dir/ARCHITECTURE.md"
            fi
        fi
    done
else
    echo -e "  ${BLUE}ℹ No tools directory found${NC}"
    ((INFO++))
fi

echo -e "\n${BLUE}[3/4] Updating central architecture index${NC}\n"
update_architecture_index

echo -e "\n${BLUE}[4/4] Checking for recent code changes without architecture updates${NC}\n"

# Check if there are staged or unstaged changes in apps/tools
if git diff --name-only HEAD 2>/dev/null | grep -E "^(apps|tools)/" | grep -v "ARCHITECTURE.md" > /dev/null; then
    echo -e "${YELLOW}⚠ Warning: Code changes detected in apps/tools${NC}"
    echo -e "  ${BLUE}ℹ Remember to update relevant ARCHITECTURE.md files${NC}"
    ((WARNINGS++))
fi

# Summary
echo -e "\n${BLUE}=== Architecture Check Summary ===${NC}"
echo -e "Warnings: $WARNINGS"
echo -e "Info: $INFO"

if [ $WARNINGS -gt 0 ]; then
    echo -e "\n${YELLOW}⚠ Architecture documentation may need attention${NC}"
    echo -e "${BLUE}ℹ This is informational only - your changes can proceed${NC}"
    echo -e "${BLUE}ℹ See docs/ARCHITECTURE_TEMPLATE.md for guidance${NC}"
fi

# Exit with success (non-blocking check)
exit 0
