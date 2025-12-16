#!/usr/bin/env bash
# Test Suite for Dependency Management System
#
# This script tests the dependency management infrastructure to ensure
# all components are properly configured and functional.
#
# Usage:
#   ./test-dependency-manager.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set +e  # Don't exit on error (we want to run all tests)

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/utils/test-helpers.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Run a test
run_test() {
    local test_name="$1"
    local test_command="$2"

    ((TESTS_RUN++))

    echo ""
    print_info "Test $TESTS_RUN: $test_name"

    if eval "$test_command" > /dev/null 2>&1; then
        print_success "PASS"
        ((TESTS_PASSED++))
    else
        print_error "FAIL"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
}

# Main test execution
main() {
    echo ""
    print_info "Dependency Management System - Test Suite"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Test 1: Check if main script exists and is executable
    run_test "Main script exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/update-dependencies.sh ]]"

    # Test 2: Check if Ditto version checker exists and is executable
    run_test "Ditto version checker exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/check-ditto-versions.sh ]]"

    # Test 3: Check if dependency managers directory exists
    run_test "Dependency managers directory exists" \
        "[[ -d $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers ]]"

    # Test 4: Check if Flutter dependency manager exists and is executable
    run_test "Flutter dependency manager exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers/flutter-deps.sh ]]"

    # Test 5: Check if Node.js dependency manager exists and is executable
    run_test "Node.js dependency manager exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers/node-deps.sh ]]"

    # Test 6: Check if Python dependency manager exists and is executable
    run_test "Python dependency manager exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers/python-deps.sh ]]"

    # Test 7: Check if iOS dependency manager exists and is executable
    run_test "iOS dependency manager exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers/ios-deps.sh ]]"

    # Test 8: Check if Android dependency manager exists and is executable
    run_test "Android dependency manager exists and is executable" \
        "[[ -x $PROJECT_ROOT/.claude/scripts/maintenance/dependency-managers/android-deps.sh ]]"

    # Test 9: Check if slash command documentation exists
    run_test "Slash command documentation exists" \
        "[[ -f $PROJECT_ROOT/.claude/commands/update-deps.md ]]"

    # Test 10: Check if comprehensive guide exists
    run_test "Comprehensive guide exists" \
        "[[ -f $PROJECT_ROOT/.claude/guides/dependency-management.md ]]"

    # Test 11: Test main script with no apps (should handle gracefully)
    run_test "Main script handles empty directories gracefully" \
        "$PROJECT_ROOT/.claude/scripts/maintenance/update-dependencies.sh check"

    # Test 12: Test Ditto version checker with no apps (should handle gracefully)
    run_test "Ditto version checker handles empty directories gracefully" \
        "$PROJECT_ROOT/.claude/scripts/maintenance/check-ditto-versions.sh"

    # Test 13: Check if CLAUDE.md includes dependency management section
    run_test "CLAUDE.md includes dependency management guidelines" \
        "grep -q 'Dependency Management' $PROJECT_ROOT/CLAUDE.md"

    # Test 14: Check if .claude/README.md references dependency management
    run_test ".claude/README.md references dependency management" \
        "grep -q 'update-deps' $PROJECT_ROOT/.claude/README.md"

    # Test 15: Check if JSON output option is supported
    run_test "Main script supports --json flag" \
        "grep -q '\\-\\-json' $PROJECT_ROOT/.claude/scripts/maintenance/update-dependencies.sh"

    # Test 16: Check if CI environment detection exists
    run_test "Main script detects CI environment" \
        "grep -q 'GITHUB_ACTIONS' $PROJECT_ROOT/.claude/scripts/maintenance/update-dependencies.sh"

    # Test 17: Check if documentation mentions CI/CD integration
    run_test "Documentation includes CI/CD integration guide" \
        "grep -q 'CI/CD Integration' $PROJECT_ROOT/.claude/guides/dependency-management.md"

    # Test 18: Check if exit codes are documented
    run_test "Documentation explains exit codes" \
        "grep -q 'Exit Codes' $PROJECT_ROOT/.claude/commands/update-deps.md"

    # Print summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Test Summary:"
    echo "  • Total tests: $TESTS_RUN"
    echo "  • Passed: $TESTS_PASSED"
    echo "  • Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        print_success "All tests passed!"
        echo ""
        echo "✓ Dependency management system is properly configured"
        echo ""
        exit 0
    else
        print_error "$TESTS_FAILED test(s) failed"
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  • $test"
        done
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
