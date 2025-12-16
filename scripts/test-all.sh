#!/usr/bin/env bash
# Test All Apps - Execute tests across all applications in parallel
#
# This script runs tests for all applications in the repository in parallel.
# Tests execute with fail-fast behavior - the first failure stops all tests.
#
# Usage:
#   ./scripts/test-all.sh
#
# Exit codes:
#   0 - All tests passed or no apps to test
#   1 - One or more tests failed
#
# Examples:
#   ./scripts/test-all.sh              # Run all tests
#
# For more information, see:
#   - apps/flutter/README.md (Flutter-specific testing)
#   - .claude/scripts/testing/ (test infrastructure)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Get project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# Show header
echo ""
echo "🧪 Running Tests Across All Applications"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Delegate to orchestrator
exec "$PROJECT_ROOT/.claude/scripts/testing/test-orchestrator.sh" "$@"
