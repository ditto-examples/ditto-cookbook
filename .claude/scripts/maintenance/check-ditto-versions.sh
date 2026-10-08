#!/usr/bin/env bash
# Ditto SDK Version Checker
#
# Checks Ditto SDK versions across all projects in the Ditto Cookbook repository.
# This is a HIGH PRIORITY feature for maintaining consistency across examples.
#
# Usage:
#   ./check-ditto-versions.sh
#
# Exit codes:
#   0 - Success (all versions checked, may have mismatches)
#   1 - Failure (error occurred during execution)

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source test helpers for consistent output formatting
source "$PROJECT_ROOT/.claude/scripts/testing/utils/test-helpers.sh"

# Ditto SDK package names by platform
declare -A DITTO_PACKAGES=(
    ["flutter"]="ditto_live"
    ["ios_cocoapods"]="Ditto"
    ["ios_swift"]="DittoSwift"
    ["android_gradle"]="com.ditto:ditto-kotlin"
    ["javascript_npm"]="@dittolive/ditto"
    ["python_pip"]="dittolive-ditto"
)

# Latest stable Ditto SDK release (verified on pub.dev and the release notes, 2026-10-08).
# Update this value when a new stable release is adopted.
RECOMMENDED_VERSION="5.1.0"

# Store found Ditto SDK references
declare -A found_versions

# Scan Flutter projects for Ditto SDK
scan_flutter_projects() {
    local search_path="$PROJECT_ROOT/apps/flutter"

    if [[ ! -d "$search_path" ]]; then
        return 0
    fi

    for app_dir in "$search_path"/*/ ; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi

        local pubspec="$app_dir/pubspec.yaml"
        if [[ ! -f "$pubspec" ]]; then
            continue
        fi

        # Extract Ditto version from pubspec.yaml
        local ditto_version=$(grep -E "^\s*ditto_live:" "$pubspec" | sed -E 's/.*:\s*[^0-9]*(.*)/\1/' | tr -d ' ' || echo "")

        if [[ -n "$ditto_version" ]]; then
            local app_name=$(basename "$app_dir")
            found_versions["flutter:$app_name"]="$ditto_version"
        fi
    done
}

# Scan iOS projects for Ditto SDK (CocoaPods)
scan_ios_projects() {
    local search_path="$PROJECT_ROOT/apps/ios"

    if [[ ! -d "$search_path" ]]; then
        return 0
    fi

    for app_dir in "$search_path"/*/ ; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi

        local podfile="$app_dir/Podfile"
        if [[ ! -f "$podfile" ]]; then
            continue
        fi

        # Extract Ditto version from Podfile
        local ditto_version=$(grep -E "^\s*pod\s+['\"]DittoSwift" "$podfile" | sed -E "s/.*['\"][^'\"]*['\"].*['\"]([^'\"]+)['\"].*/\1/" || echo "")

        if [[ -n "$ditto_version" ]]; then
            local app_name=$(basename "$app_dir")
            found_versions["ios:$app_name"]="$ditto_version"
        fi
    done
}

# Scan Android projects for Ditto SDK (Gradle)
scan_android_projects() {
    local search_path="$PROJECT_ROOT/apps/android"

    if [[ ! -d "$search_path" ]]; then
        return 0
    fi

    for app_dir in "$search_path"/*/ ; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi

        # Check build.gradle
        for gradle_file in "$app_dir/build.gradle" "$app_dir/build.gradle.kts" "$app_dir/app/build.gradle" "$app_dir/app/build.gradle.kts"; do
            if [[ ! -f "$gradle_file" ]]; then
                continue
            fi

            # Extract Ditto version
            local ditto_version=$(grep -E "com\.ditto:ditto-kotlin:" "$gradle_file" | sed -E "s/.*:([0-9]+\.[0-9]+\.[0-9]+[^'\"]*).*/\1/" || echo "")

            if [[ -n "$ditto_version" ]]; then
                local app_name=$(basename "$app_dir")
                found_versions["android:$app_name"]="$ditto_version"
                break
            fi
        done
    done
}

# Scan web/Node.js projects for Ditto SDK
scan_web_projects() {
    local search_path="$PROJECT_ROOT/apps/web"

    if [[ ! -d "$search_path" ]]; then
        return 0
    fi

    for app_dir in "$search_path"/*/ ; do
        if [[ ! -d "$app_dir" ]]; then
            continue
        fi

        local package_json="$app_dir/package.json"
        if [[ ! -f "$package_json" ]]; then
            continue
        fi

        # Extract Ditto version from package.json
        local ditto_version=$(grep -E "\"@dittolive/ditto\":" "$package_json" | sed -E 's/.*"([^"]+)".*/\1/' || echo "")

        if [[ -n "$ditto_version" ]]; then
            local app_name=$(basename "$app_dir")
            found_versions["web:$app_name"]="$ditto_version"
        fi
    done
}

# Scan Python tools for Ditto SDK
scan_python_tools() {
    local search_path="$PROJECT_ROOT/tools"

    if [[ ! -d "$search_path" ]]; then
        return 0
    fi

    for tool_dir in "$search_path"/*/ ; do
        if [[ ! -d "$tool_dir" ]]; then
            continue
        fi

        local requirements="$tool_dir/requirements.txt"
        if [[ ! -f "$requirements" ]]; then
            continue
        fi

        # Extract Ditto version from requirements.txt
        local ditto_version=$(grep -iE "^dittolive-ditto==" "$requirements" | sed -E 's/.*==([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*).*/\1/' || echo "")

        if [[ -n "$ditto_version" ]]; then
            local tool_name=$(basename "$tool_dir")
            found_versions["python:$tool_name"]="$ditto_version"
        fi
    done
}

# Compare version with recommended
compare_version() {
    local version=$1
    local major=$(echo "$version" | cut -d. -f1)

    # Strip common range prefixes such as ^ or ~
    local plain="${version#[\^~]}"

    if [[ "$plain" == *"preview"* || "$plain" == *"dev"* || "$plain" == *"experimental"* ]]; then
        echo "preview"
    elif [[ "$plain" == "$RECOMMENDED_VERSION" ]]; then
        echo "latest"
    elif [[ "$major" =~ ^[\^~]?[0-9]+$ ]] && (( ${major#[\^~]} < 5 )); then
        echo "deprecated"
    elif [[ "$major" =~ ^[\^~]?[0-9]+$ ]]; then
        echo "outdated"
    else
        echo "unknown"
    fi
}

# Get color for version status
get_status_color() {
    local status=$1
    case "$status" in
        latest)
            echo "$GREEN"
            ;;
        preview)
            echo "$BLUE"
            ;;
        outdated)
            echo "$YELLOW"
            ;;
        deprecated)
            echo "$RED"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# Print detailed report
print_report() {
    echo ""
    print_info "Ditto SDK Version Report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ${#found_versions[@]} -eq 0 ]]; then
        print_warning "No Ditto SDK references found in the repository"
        echo ""
        print_info "This is expected if no apps have been created yet."
        echo ""
        return 0
    fi

    # Group by platform
    declare -A platforms
    for key in "${!found_versions[@]}"; do
        local platform=$(echo "$key" | cut -d: -f1)
        platforms["$platform"]=1
    done

    # Print by platform
    for platform in "${!platforms[@]}"; do
        echo ""
        print_info "Platform: $platform"
        echo ""

        for key in "${!found_versions[@]}"; do
            if [[ "$key" == "$platform:"* ]]; then
                local app_name=$(echo "$key" | cut -d: -f2)
                local version="${found_versions[$key]}"
                local status=$(compare_version "$version")
                local color=$(get_status_color "$status")

                echo -e "  • ${app_name}: ${color}${version}${NC} (${status})"
            fi
        done
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check for version consistency
    local unique_versions=$(printf '%s\n' "${found_versions[@]}" | sort -u | wc -l | tr -d ' ')

    if [[ $unique_versions -gt 1 ]]; then
        print_warning "Version Inconsistency Detected!"
        echo ""
        echo "Found $unique_versions different Ditto SDK versions across projects."
        echo ""
        print_info "Recommendation:"
        echo "  • Standardize all projects on Ditto SDK v$RECOMMENDED_VERSION"
        echo ""
    else
        print_success "All projects use the same Ditto SDK version"
        echo ""
    fi

    # Print recommendations
    print_info "Ditto SDK Information:"
    echo ""
    echo "  Recommended Release:"
    echo "    • Ditto SDK v$RECOMMENDED_VERSION (latest stable)"
    echo "    • Packages: Flutter ditto_live, Swift DittoSwift, Kotlin com.ditto:ditto-kotlin, JavaScript @dittolive/ditto"
    echo ""
    echo "  Documentation:"
    echo "    • Latest SDK: https://docs.ditto.live/sdk/latest"
    echo "    • What's New in v5: https://docs.ditto.live/sdk/latest/v5-whats-new"
    echo "    • Release Notes: https://docs.ditto.live/sdk/latest/release-notes"
    echo "    • Best practices: .claude/guides/best-practices/ditto.md"
    echo ""
    echo "  Version Compatibility:"
    echo "    • 5.1 peers sync with 5.0 peers and with v4 peers (4.11 or later)"
    echo "    • 5.1 changes the on-disk index format; downgrades must go through 5.0.2+ or 4.14.6+"
    echo ""
}

# Main execution
main() {
    echo ""
    print_info "Ditto Cookbook - SDK Version Checker (HIGH PRIORITY)"
    echo ""
    print_info "Scanning projects for Ditto SDK references..."
    echo ""

    # Scan all platforms
    scan_flutter_projects
    scan_ios_projects
    scan_android_projects
    scan_web_projects
    scan_python_tools

    # Print report
    print_report

    # Return success (even if inconsistencies found - this is informational)
    exit 0
}

# Run main function
main "$@"
