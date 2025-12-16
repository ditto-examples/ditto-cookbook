#!/usr/bin/env bash
# Test Orchestrator - Coordinate parallel test execution across all apps
#
# This script discovers all apps in the repository, detects their platform,
# and runs tests in parallel with fail-fast behavior.
#
# Usage:
#   ./test-orchestrator.sh [options]
#
# Exit codes:
#   0 - All tests passed or no apps to test
#   1 - One or more tests failed

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUNNERS_DIR="$SCRIPT_DIR/runners"

# Source helpers
source "$SCRIPT_DIR/utils/test-helpers.sh"

# Create temporary directory for logs
TEMP_DIR=$(create_temp_dir)
trap "cleanup_temp_dir '$TEMP_DIR'" EXIT

# Discover all testable apps
discover_apps() {
    local -n apps_ref=$1
    local platform_dirs=("flutter" "ios" "android" "web")

    for platform_dir in "${platform_dirs[@]}"; do
        local search_path="$PROJECT_ROOT/apps/$platform_dir"

        if [[ ! -d "$search_path" ]]; then
            continue
        fi

        # Find all subdirectories (each is potentially an app)
        for app_dir in "$search_path"/*/ ; do
            # Skip if not a valid directory
            if ! is_valid_app_dir "$app_dir"; then
                continue
            fi

            # Remove trailing slash
            app_dir="${app_dir%/}"

            # Detect platform
            local platform=$(detect_platform "$app_dir")

            # Skip if platform is unknown
            if [[ "$platform" == "unknown" ]]; then
                continue
            fi

            # Check if runner exists
            if [[ ! -f "$RUNNERS_DIR/${platform}-test.sh" ]]; then
                print_warning "No test runner found for platform: $platform"
                continue
            fi

            # Add to apps list
            apps_ref["$app_dir"]="$platform"
        done
    done
}

# Print discovered apps
print_discovered_apps() {
    local -n apps_ref=$1

    echo ""
    print_info "Found ${#apps_ref[@]} testable application(s):"
    echo ""

    for app_dir in "${!apps_ref[@]}"; do
        local app_name=$(get_app_name "$app_dir")
        local platform="${apps_ref[$app_dir]}"
        echo "  • $app_name ($platform)"
    done
    echo ""
}

# Run tests in parallel with fail-fast
run_tests_parallel() {
    local -n apps_ref=$1

    # Track background processes
    declare -A test_pids
    declare -A pid_to_app
    local start_time=$(date +%s)
    local max_test_time=1800  # 30 minutes timeout

    print_info "Running tests in parallel..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Start all tests in background
    for app_dir in "${!apps_ref[@]}"; do
        local platform="${apps_ref[$app_dir]}"
        local runner="$RUNNERS_DIR/${platform}-test.sh"
        local app_name=$(get_app_name "$app_dir")

        # Run test in background, redirect output to log file
        "$runner" "$app_dir" > "$TEMP_DIR/${app_name}.log" 2>&1 &
        local pid=$!

        test_pids[$pid]=1
        pid_to_app[$pid]="$app_dir"
    done

    # Monitor processes with fail-fast
    local failed_app=""
    local failed_pid=""

    while [[ ${#test_pids[@]} -gt 0 ]]; do
        # Check for timeout
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -gt $max_test_time ]]; then
            echo ""
            print_error "Tests exceeded timeout of ${max_test_time}s"

            # Kill all remaining processes
            for pid in "${!test_pids[@]}"; do
                kill "$pid" 2>/dev/null || true
            done

            return 1
        fi

        # Check each process
        for pid in "${!test_pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                # Process finished
                wait "$pid"
                local exit_code=$?
                local app_dir="${pid_to_app[$pid]}"
                local app_name=$(get_app_name "$app_dir")

                if [[ $exit_code -ne 0 ]]; then
                    # Test failed - fail fast
                    failed_app="$app_name"
                    failed_pid="$pid"

                    # Kill all remaining processes
                    for other_pid in "${!test_pids[@]}"; do
                        if [[ "$other_pid" != "$pid" ]]; then
                            kill "$other_pid" 2>/dev/null || true
                        fi
                    done

                    # Clear test_pids to exit loop
                    test_pids=()
                    break
                fi

                # Remove from monitoring
                unset test_pids[$pid]
            fi
        done

        # Don't spin CPU - small sleep
        sleep 0.1
    done

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Handle failure
    if [[ -n "$failed_app" ]]; then
        print_error "Tests Failed: $failed_app"
        echo ""
        echo "Test output:"
        echo "══════════════════════════════════════════"
        cat "$TEMP_DIR/${failed_app}.log"
        echo "══════════════════════════════════════════"
        echo ""
        print_warning "Note: Remaining tests were cancelled (fail-fast mode)"
        echo ""
        echo "To run tests for a specific app:"
        local failed_app_dir="${pid_to_app[$failed_pid]}"
        echo "  cd $failed_app_dir"
        echo "  flutter test  # or appropriate test command for the platform"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        return 1
    fi

    # All tests passed
    echo "✅ All Tests Passed!"
    echo ""
    echo "Summary:"
    echo "  • Total apps tested: ${#apps_ref[@]}"
    echo "  • Passed: ${#apps_ref[@]}"
    echo "  • Failed: 0"
    echo "  • Duration: ${duration}s"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# Main execution
main() {
    # Discover apps
    print_info "Discovering applications..."

    declare -A apps_to_test
    discover_apps apps_to_test

    # Check if any apps found
    if [[ ${#apps_to_test[@]} -eq 0 ]]; then
        echo ""
        print_warning "No testable applications found"
        echo ""
        print_info "Searched directories:"
        echo "  • apps/flutter/"
        echo "  • apps/ios/"
        echo "  • apps/android/"
        echo "  • apps/web/"
        echo ""
        print_info "To add apps, create subdirectories under apps/<platform>/"
        echo ""
        exit 0
    fi

    # Print discovered apps
    print_discovered_apps apps_to_test

    # Run tests in parallel
    if run_tests_parallel apps_to_test; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
