#!/usr/bin/env bash
# Dependency Update Orchestrator - Check and update dependencies across all apps and tools
#
# This script discovers all apps and tools in the repository, detects their platform,
# and checks/updates dependencies using appropriate package managers.
#
# Usage:
#   ./update-dependencies.sh check                # Check for outdated dependencies
#   ./update-dependencies.sh update               # Update dependencies interactively
#   ./update-dependencies.sh update --all         # Update all dependencies automatically
#   ./update-dependencies.sh ditto                # Check Ditto SDK versions
#
# Exit codes:
#   0 - Success (all checks/updates completed)
#   1 - Failure (error occurred during execution)

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MANAGERS_DIR="$SCRIPT_DIR/dependency-managers"

# Source test helpers for consistent output formatting
source "$PROJECT_ROOT/.claude/scripts/testing/utils/test-helpers.sh"

# Parse command line arguments
MODE="${1:-check}"
AUTO_UPDATE=false
if [[ "${2:-}" == "--all" ]]; then
    AUTO_UPDATE=true
fi
JSON_OUTPUT=false

# Check for --json flag
if [[ "$2" == "--json" ]] || [[ "$3" == "--json" ]]; then
    JSON_OUTPUT=true
fi

# Detect CI environment
if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    IS_CI=true
else
    IS_CI=false
fi

# Validate mode
case "$MODE" in
    check|update|ditto)
        ;;
    *)
        echo "Usage: $0 {check|update|ditto} [--all] [--json]"
        echo ""
        echo "Modes:"
        echo "  check              Check for outdated dependencies (non-destructive)"
        echo "  update             Update dependencies interactively"
        echo "  update --all       Update all dependencies automatically"
        echo "  ditto              Check Ditto SDK versions across projects"
        echo ""
        echo "Options:"
        echo "  --json             Output in JSON format (for CI/CD integration)"
        echo ""
        echo "Environment Variables:"
        echo "  CI=true            Detected as CI environment"
        echo "  GITHUB_ACTIONS     Detected as GitHub Actions"
        exit 1
        ;;
esac

# Discover all apps and tools
discover_projects() {
    local -n projects_ref=$1
    local search_dirs=("apps/flutter" "apps/ios" "apps/android" "apps/web" "tools")

    for search_dir in "${search_dirs[@]}"; do
        local search_path="$PROJECT_ROOT/$search_dir"

        if [[ ! -d "$search_path" ]]; then
            continue
        fi

        # Find all subdirectories
        for project_dir in "$search_path"/*/ ; do
            # Skip if not a valid directory
            if ! is_valid_app_dir "$project_dir"; then
                continue
            fi

            # Remove trailing slash
            project_dir="${project_dir%/}"

            # Detect platform
            local platform=$(detect_platform "$project_dir")

            # Skip if platform is unknown
            if [[ "$platform" == "unknown" ]]; then
                continue
            fi

            # Check if manager exists
            if [[ ! -f "$MANAGERS_DIR/${platform}-deps.sh" ]]; then
                print_warning "No dependency manager found for platform: $platform"
                continue
            fi

            # Add to projects list
            projects_ref["$project_dir"]="$platform"
        done
    done
}

# Print discovered projects
print_discovered_projects() {
    local -n projects_ref=$1

    echo ""
    print_info "Found ${#projects_ref[@]} project(s) with dependencies:"
    echo ""

    for project_dir in "${!projects_ref[@]}"; do
        local project_name=$(get_app_name "$project_dir")
        local platform="${projects_ref[$project_dir]}"
        echo "  • $project_name ($platform)"
    done
    echo ""
}

# Check dependencies for all projects
check_dependencies() {
    local -n projects_ref=$1
    local has_outdated=0
    declare -A outdated_projects

    # JSON output initialization
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"status":"checking","projects":['
    else
        print_info "Checking dependencies..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    local first_project=true
    for project_dir in "${!projects_ref[@]}"; do
        local platform="${projects_ref[$project_dir]}"
        local manager="$MANAGERS_DIR/${platform}-deps.sh"
        local project_name=$(get_app_name "$project_dir")

        if [[ "$JSON_OUTPUT" != "true" ]]; then
            echo "Checking $project_name ($platform)..."
            echo ""
        fi

        if "$manager" check "$project_dir" > /dev/null 2>&1; then
            if [[ "$JSON_OUTPUT" == "true" ]]; then
                [[ "$first_project" == "false" ]] && echo ","
                echo -n "{\"name\":\"$project_name\",\"platform\":\"$platform\",\"status\":\"up-to-date\"}"
                first_project=false
            else
                print_success "$project_name is up to date"
            fi
        else
            has_outdated=1
            outdated_projects["$project_name"]="$platform"
            if [[ "$JSON_OUTPUT" == "true" ]]; then
                [[ "$first_project" == "false" ]] && echo ","
                echo -n "{\"name\":\"$project_name\",\"platform\":\"$platform\",\"status\":\"outdated\"}"
                first_project=false
            else
                print_warning "$project_name has outdated dependencies"
            fi
        fi

        if [[ "$JSON_OUTPUT" != "true" ]]; then
            echo ""
        fi
    done

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "],"
        echo "\"summary\":{\"total\":${#projects_ref[@]},\"outdated\":$has_outdated,\"up_to_date\":$((${#projects_ref[@]} - has_outdated))},"
        echo "\"ci_environment\":$IS_CI}"
        echo "}"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        if [[ $has_outdated -eq 0 ]]; then
            print_success "All dependencies are up to date!"
        else
            print_warning "Found $has_outdated project(s) with outdated dependencies"
            echo ""
            print_info "Outdated projects:"
            for proj in "${!outdated_projects[@]}"; do
                echo "  • $proj (${outdated_projects[$proj]})"
            done
            echo ""
            print_info "Run './update-dependencies.sh update' to update them."
        fi
    fi

    return $has_outdated
}

# Update dependencies for all projects
update_dependencies() {
    local -n projects_ref=$1
    local auto_mode="$2"
    local updated_count=0
    local failed_count=0

    if [[ "$auto_mode" == true ]]; then
        print_info "Updating all dependencies automatically..."
    else
        print_info "Updating dependencies interactively..."
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for project_dir in "${!projects_ref[@]}"; do
        local platform="${projects_ref[$project_dir]}"
        local manager="$MANAGERS_DIR/${platform}-deps.sh"
        local project_name=$(get_app_name "$project_dir")

        echo "Updating $project_name ($platform)..."
        echo ""

        if [[ "$auto_mode" == true ]]; then
            # Automatic update
            if "$manager" update "$project_dir"; then
                print_success "$project_name updated successfully"
                ((updated_count++))
            else
                print_error "$project_name update failed"
                ((failed_count++))
            fi
        else
            # Interactive update
            read -p "Update $project_name? (y/N): " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if "$manager" update "$project_dir"; then
                    print_success "$project_name updated successfully"
                    ((updated_count++))
                else
                    print_error "$project_name update failed"
                    ((failed_count++))
                fi
            else
                print_info "Skipped $project_name"
            fi
        fi

        echo ""
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Summary:"
    echo "  • Updated: $updated_count"
    echo "  • Failed: $failed_count"
    echo "  • Skipped: $((${#projects_ref[@]} - updated_count - failed_count))"
    echo ""

    if [[ $failed_count -gt 0 ]]; then
        print_error "Some updates failed"
        return 1
    fi

    if [[ $updated_count -gt 0 ]]; then
        print_success "Dependencies updated successfully!"
        echo ""
        print_info "Next steps:"
        echo "  1. Review the changes in your version control"
        echo "  2. Run tests to verify compatibility: ./scripts/test-all.sh"
        echo "  3. Update documentation if needed"
    else
        print_info "No dependencies were updated"
    fi

    return 0
}

# Check Ditto SDK versions
check_ditto_versions() {
    local ditto_checker="$SCRIPT_DIR/check-ditto-versions.sh"

    if [[ ! -f "$ditto_checker" ]]; then
        print_error "Ditto SDK version checker not found: $ditto_checker"
        return 1
    fi

    print_info "Checking Ditto SDK versions across all projects..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    "$ditto_checker"
}

# Main execution
main() {
    echo ""
    print_info "Ditto Cookbook - Dependency Manager"
    echo ""

    case "$MODE" in
        ditto)
            # Special mode: check Ditto SDK versions only
            if check_ditto_versions; then
                exit 0
            else
                exit 1
            fi
            ;;
        check|update)
            # Discover projects
            print_info "Discovering projects..."

            declare -A projects
            discover_projects projects

            # Check if any projects found
            if [[ ${#projects[@]} -eq 0 ]]; then
                echo ""
                print_warning "No projects with dependencies found"
                echo ""
                print_info "Searched directories:"
                echo "  • apps/flutter/"
                echo "  • apps/ios/"
                echo "  • apps/android/"
                echo "  • apps/web/"
                echo "  • tools/"
                echo ""
                print_info "To add projects, create subdirectories with dependency files"
                echo "  (pubspec.yaml, package.json, requirements.txt, Podfile, build.gradle)"
                echo ""
                exit 0
            fi

            # Print discovered projects
            print_discovered_projects projects

            # Execute mode
            if [[ "$MODE" == "check" ]]; then
                # Check mode: exit 1 if outdated dependencies found (for CI/CD detection)
                if check_dependencies projects; then
                    exit 0  # All up to date
                else
                    exit 1  # Outdated dependencies found
                fi
            else
                # Update mode: exit 1 if update failed
                if update_dependencies projects "$AUTO_UPDATE"; then
                    exit 0  # Update successful
                else
                    exit 1  # Update failed
                fi
            fi
            ;;
    esac
}

# Run main function
main "$@"
