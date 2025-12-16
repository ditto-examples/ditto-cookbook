#!/bin/bash
# Update Tool Versions Across Configuration Files
#
# This script updates tool versions in 3 configuration files:
# 1. .tool-versions (Primary - Single Source of Truth)
# 2. .fvm/fvm_config.json (Flutter FVM)
# 3. .nvmrc (Node.js nvm)
#
# Usage:
#   ./update-versions.sh <tool> <version>
#
# Examples:
#   ./update-versions.sh flutter 3.40.0
#   ./update-versions.sh nodejs 25.0.0
#   ./update-versions.sh python 3.15.0

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Parse arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <tool> <version>"
    echo ""
    echo "Examples:"
    echo "  $0 flutter 3.40.0"
    echo "  $0 nodejs 25.0.0"
    echo "  $0 python 3.15.0"
    exit 1
fi

TOOL=$1
VERSION=$2

# Validate tool
if [[ ! "$TOOL" =~ ^(flutter|nodejs|python)$ ]]; then
    print_error "Invalid tool: $TOOL"
    print_info "Valid tools: flutter, nodejs, python"
    exit 1
fi

echo ""
print_info "Updating $TOOL to version $VERSION..."
echo ""

cd "$PROJECT_ROOT"

# 1. Update .tool-versions
print_info "[1/3] Updating .tool-versions..."
if [ -f .tool-versions ]; then
    # Check if tool exists in file
    if grep -q "^$TOOL " .tool-versions; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed
            sed -i '' "s/^$TOOL .*/$TOOL $VERSION/" .tool-versions
        else
            # Linux sed
            sed -i "s/^$TOOL .*/$TOOL $VERSION/" .tool-versions
        fi
        print_success ".tool-versions updated: $TOOL $VERSION"
    else
        # Add new line
        echo "$TOOL $VERSION" >> .tool-versions
        print_success ".tool-versions updated: added $TOOL $VERSION"
    fi
else
    print_error ".tool-versions not found"
    exit 1
fi

# 2. Update .fvm/fvm_config.json (if Flutter)
if [ "$TOOL" = "flutter" ]; then
    print_info "[2/3] Updating .fvm/fvm_config.json..."
    if [ -f .fvm/fvm_config.json ]; then
        # Update flutterSdkVersion using jq if available, otherwise sed
        if command -v jq &> /dev/null; then
            TMP_FILE=$(mktemp)
            jq --arg ver "$VERSION" '.flutterSdkVersion = $ver' .fvm/fvm_config.json > "$TMP_FILE"
            mv "$TMP_FILE" .fvm/fvm_config.json
            print_success ".fvm/fvm_config.json updated: flutterSdkVersion = $VERSION"
        else
            # Fallback to sed
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/\"flutterSdkVersion\": \".*\"/\"flutterSdkVersion\": \"$VERSION\"/" .fvm/fvm_config.json
            else
                sed -i "s/\"flutterSdkVersion\": \".*\"/\"flutterSdkVersion\": \"$VERSION\"/" .fvm/fvm_config.json
            fi
            print_success ".fvm/fvm_config.json updated: flutterSdkVersion = $VERSION"
        fi
    else
        print_warning ".fvm/fvm_config.json not found - skipping"
    fi
else
    print_info "[2/3] Skipping .fvm/fvm_config.json (not updating Flutter)"
fi

# 3. Update .nvmrc (if Node.js)
if [ "$TOOL" = "nodejs" ]; then
    print_info "[3/3] Updating .nvmrc..."
    echo "$VERSION" > .nvmrc
    print_success ".nvmrc updated: $VERSION"
else
    print_info "[3/3] Skipping .nvmrc (not updating Node.js)"
fi

echo ""
print_success "Version update complete!"
echo ""

# Show summary
print_info "Updated files:"
if [ "$TOOL" = "flutter" ]; then
    echo "  • .tool-versions"
    echo "  • .fvm/fvm_config.json"
elif [ "$TOOL" = "nodejs" ]; then
    echo "  • .tool-versions"
    echo "  • .nvmrc"
else
    echo "  • .tool-versions"
fi
echo ""

# Suggest next steps
print_info "Next steps:"
echo "  1. Install new version: asdf install"
echo "  2. Verify: $TOOL --version"
echo "  3. Commit changes:"
echo "     git add .tool-versions"
if [ "$TOOL" = "flutter" ]; then
    echo "     git add .fvm/fvm_config.json"
elif [ "$TOOL" = "nodejs" ]; then
    echo "     git add .nvmrc"
fi
echo "     git commit -m \"Update $TOOL to $VERSION\""
echo "     git push"
echo ""
