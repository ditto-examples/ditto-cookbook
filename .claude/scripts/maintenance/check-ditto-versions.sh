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
    ["flutter"]="ditto_flutter"
    ["ios_cocoapods"]="Ditto"
    ["ios_swift"]="DittoSwift"
    ["android_gradle"]="live.ditto:ditto"
    ["javascript_npm"]="@dittolive/ditto"
    ["python_pip"]="ditto"
)

# Known stable versions (as of the search)
# SDK v4.12.x is the current stable release
# SDK v5 is in public preview
RECOMMENDED_VERSION_V4="4.12.4"
RECOMMENDED_VERSION_V5="5.0.0-preview.3"

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
        local ditto_version=$(grep -E "^\s*ditto_flutter:" "$pubspec" | sed -E 's/.*:\s*[^0-9]*(.*)/\1/' | tr -d ' ' || echo "")

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
        local ditto_version=$(grep -E "^\s*pod\s+['\"]Ditto" "$podfile" | sed -E "s/.*['\"][^'\"]*['\"].*['\"]([^'\"]+)['\"].*/\1/" || echo "")

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
            local ditto_version=$(grep -E "live\.ditto:ditto:" "$gradle_file" | sed -E "s/.*:([0-9]+\.[0-9]+\.[0-9]+[^'\"]*).*/\1/" || echo "")

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
        local ditto_version=$(grep -iE "^ditto(live)?==" "$requirements" | sed -E 's/.*==([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*).*/\1/' || echo "")

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

    # Check if it's v5 preview
    if [[ "$version" == *"preview"* ]]; then
        echo "preview"
    elif [[ "$major" == "5" ]]; then
        echo "preview"
    elif [[ "$major" == "4" ]]; then
        # Compare with recommended v4
        if [[ "$version" == "$RECOMMENDED_VERSION_V4" ]]; then
            echo "latest"
        else
            echo "outdated"
        fi
    elif [[ "$major" == "3" ]]; then
        echo "deprecated"
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
        echo "  • Consider standardizing on Ditto SDK v$RECOMMENDED_VERSION_V4 (stable)"
        echo "  • Or use v$RECOMMENDED_VERSION_V5 (preview) for all projects"
        echo ""
    else
        print_success "All projects use the same Ditto SDK version"
        echo ""
    fi

    # Print recommendations
    print_info "Ditto SDK Information:"
    echo ""
    echo "  Stable Release (Recommended for Production):"
    echo "    • SDK v4.12.x (latest: $RECOMMENDED_VERSION_V4)"
    echo "    • Full production support"
    echo "    • All platforms: Flutter, iOS, Android, JavaScript, Python"
    echo ""
    echo "  Preview Release (Public Preview):"
    echo "    • SDK v5.0.0-preview.x (latest: $RECOMMENDED_VERSION_V5)"
    echo "    • Subject to changes"
    echo "    • Limited platform support (check docs)"
    echo ""
    echo "  Documentation:"
    echo "    • Latest SDK: https://docs.ditto.live/sdk/latest"
    echo "    • v4 Release Notes: https://docs.ditto.live/sdk/latest/release-notes"
    echo "    • v5 Preview: https://docs.ditto.live/sdk/v5"
    echo ""
    echo "  Version Compatibility:"
    echo "    • v4 can sync with v3 or v5 (but not both simultaneously)"
    echo "    • Upgrade all devices to v4 before deploying v5"
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
