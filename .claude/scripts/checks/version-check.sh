#!/bin/bash
# Automated version verification for Ditto Cookbook
# This script checks if developers are using correct tool versions
# and offers to fix them automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if .tool-versions exists
if [ ! -f "$PROJECT_ROOT/.tool-versions" ]; then
    print_error ".tool-versions not found"
    exit 0
fi

# Read expected versions
EXPECTED_FLUTTER=$(grep "^flutter" "$PROJECT_ROOT/.tool-versions" 2>/dev/null | awk '{print $2}')
EXPECTED_NODE=$(grep "^nodejs" "$PROJECT_ROOT/.tool-versions" 2>/dev/null | awk '{print $2}')
EXPECTED_PYTHON=$(grep "^python" "$PROJECT_ROOT/.tool-versions" 2>/dev/null | awk '{print $2}')

VERSION_MISMATCH=0

# Check Flutter version
if [ -n "$EXPECTED_FLUTTER" ]; then
    if command -v flutter &> /dev/null; then
        ACTUAL_FLUTTER=$(flutter --version 2>/dev/null | grep "Flutter" | awk '{print $2}')
        if [ "$ACTUAL_FLUTTER" != "$EXPECTED_FLUTTER" ]; then
            print_warning "Flutter version mismatch"
            echo "   Expected: $EXPECTED_FLUTTER"
            echo "   Actual:   $ACTUAL_FLUTTER"
            VERSION_MISMATCH=1
        else
            print_success "Flutter version correct: $ACTUAL_FLUTTER"
        fi
    else
        print_warning "Flutter not found in PATH"
        VERSION_MISMATCH=1
    fi
fi

# Check Node.js version
if [ -n "$EXPECTED_NODE" ]; then
    if command -v node &> /dev/null; then
        ACTUAL_NODE=$(node --version | sed 's/v//')
        if [ "$ACTUAL_NODE" != "$EXPECTED_NODE" ]; then
            print_warning "Node.js version mismatch"
            echo "   Expected: $EXPECTED_NODE"
            echo "   Actual:   $ACTUAL_NODE"
            VERSION_MISMATCH=1
        else
            print_success "Node.js version correct: $ACTUAL_NODE"
        fi
    else
        print_warning "Node.js not found in PATH"
        VERSION_MISMATCH=1
    fi
fi

# Check Python version
if [ -n "$EXPECTED_PYTHON" ]; then
    if command -v python &> /dev/null; then
        ACTUAL_PYTHON=$(python --version 2>&1 | awk '{print $2}')
        # Compare major.minor versions only (ignore patch)
        EXPECTED_PYTHON_SHORT=$(echo "$EXPECTED_PYTHON" | cut -d. -f1-2)
        ACTUAL_PYTHON_SHORT=$(echo "$ACTUAL_PYTHON" | cut -d. -f1-2)
        if [ "$ACTUAL_PYTHON_SHORT" != "$EXPECTED_PYTHON_SHORT" ]; then
            print_warning "Python version mismatch"
            echo "   Expected: $EXPECTED_PYTHON"
            echo "   Actual:   $ACTUAL_PYTHON"
            VERSION_MISMATCH=1
        else
            print_success "Python version correct: $ACTUAL_PYTHON"
        fi
    else
        print_warning "Python not found in PATH"
        VERSION_MISMATCH=1
    fi
fi

# If version mismatch detected, offer automatic fix
if [ $VERSION_MISMATCH -eq 1 ]; then
    echo ""
    print_warning "Version mismatch detected!"
    echo ""

    # Check if asdf is available
    if command -v asdf &> /dev/null; then
        print_info "asdf is available. Fixing versions automatically..."
        echo ""

        # Install missing plugins and versions
        cd "$PROJECT_ROOT"

        # Install plugins if needed
        if [ -n "$EXPECTED_FLUTTER" ] && ! asdf plugin list | grep -q flutter; then
            asdf plugin add flutter
        fi
        if [ -n "$EXPECTED_NODE" ] && ! asdf plugin list | grep -q nodejs; then
            asdf plugin add nodejs
        fi
        if [ -n "$EXPECTED_PYTHON" ] && ! asdf plugin list | grep -q python; then
            asdf plugin add python
        fi

        # Install versions
        asdf install

        print_success "Versions fixed automatically!"
        echo ""
        print_info "Please restart your terminal or run: source ~/.zshrc (or ~/.bashrc)"
        echo ""
    else
        print_error "asdf is not installed. Cannot fix versions automatically."
        echo ""
        print_info "To fix this issue, run:"
        print_info "  ./.claude/scripts/setup/setup-versions.sh"
        echo ""
        exit 1
    fi
else
    echo ""
    print_success "All tool versions are correct!"
    echo ""
fi

exit 0
