#!/bin/bash

# Language Check Script - CI/CD Wrapper
# Sources post-task-check.sh and runs language check function only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the main check script to get functions and cached git info
source "$SCRIPT_DIR/post-task-check.sh"

# Run language check
echo "🌐 Checking Language Compliance..."
echo ""

run_language_check
RESULT=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $RESULT -gt 0 ]]; then
    echo "⚠️  $RESULT file(s) contain non-English content"
    echo ""
    echo "Note: Non-English content is acceptable for:"
    echo "  • Test data and fixtures"
    echo "  • User-facing strings (with i18n)"
    echo "  • Example content"
    echo ""
    echo "All code, comments, and documentation should be in English."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
else
    echo "✅ All files use English"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi
