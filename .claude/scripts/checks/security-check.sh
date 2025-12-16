#!/bin/bash

# Security Check Script - CI/CD Wrapper
# Sources post-task-check.sh and runs security check function only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the main check script to get functions and cached git info
source "$SCRIPT_DIR/post-task-check.sh"

# Run security check
echo "🔒 Running Security Checks..."
echo ""

run_security_check
RESULT=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $RESULT -gt 0 ]]; then
    echo "❌ Security Check Failed: $RESULT issue(s) found"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
else
    echo "✅ Security Check Passed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi
