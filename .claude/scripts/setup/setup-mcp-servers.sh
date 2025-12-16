#!/bin/bash

# MCP Servers Setup Script for Ditto Cookbook
# This script automatically configures Ditto and Flutter MCP servers for Claude Code

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect platform
OS_TYPE=$(uname -s)
ARCH_TYPE=$(uname -m)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Ditto Cookbook MCP Servers Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Platform: $OS_TYPE ($ARCH_TYPE)"
echo ""

# Check if Claude Code CLI is available
if ! command -v claude &> /dev/null; then
    echo -e "${RED}Error: Claude Code CLI not found${NC}"
    echo "Please install Claude Code first:"
    echo "  https://code.visualstudio.com/docs/copilot/customization/mcp-servers"
    exit 1
fi

echo -e "${GREEN}✓ Claude Code CLI found${NC}"
echo ""

# Function to check if MCP server is already configured
check_mcp_exists() {
    local server_name=$1
    if claude mcp list 2>/dev/null | grep -q "$server_name"; then
        return 0  # exists
    else
        return 1  # doesn't exist
    fi
}

# ============================================
# 1. Setup Ditto MCP Server
# ============================================
echo -e "${BLUE}[1/2]${NC} Setting up Ditto MCP server..."

if check_mcp_exists "Ditto"; then
    echo -e "${YELLOW}⚠ Ditto MCP server already configured${NC}"
    read -p "Do you want to reconfigure it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing Ditto MCP server..."
        claude mcp remove Ditto || true
    else
        echo "Skipping Ditto MCP setup"
        DITTO_SKIPPED=true
    fi
fi

if [ "$DITTO_SKIPPED" != true ]; then
    echo "Adding Ditto MCP server..."
    if claude mcp add --transport http Ditto https://docs.ditto.live/mcp; then
        echo -e "${GREEN}✓ Ditto MCP server configured successfully${NC}"
    else
        echo -e "${RED}✗ Failed to configure Ditto MCP server${NC}"
        exit 1
    fi
fi

echo ""

# ============================================
# 2. Setup Flutter MCP Server
# ============================================
echo -e "${BLUE}[2/2]${NC} Setting up Flutter MCP server..."

# Determine Flutter MCP binary name based on platform
FLUTTER_MCP_BINARY=""
FLUTTER_MCP_URL=""

case "$OS_TYPE" in
    Darwin)
        if [ "$ARCH_TYPE" = "arm64" ]; then
            FLUTTER_MCP_BINARY="flutter-mcp"
            FLUTTER_MCP_URL="https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-macos"
        else
            FLUTTER_MCP_BINARY="flutter-mcp"
            FLUTTER_MCP_URL="https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-macos-intel"
        fi
        ;;
    Linux)
        FLUTTER_MCP_BINARY="flutter-mcp"
        FLUTTER_MCP_URL="https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-linux"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        FLUTTER_MCP_BINARY="flutter-mcp.exe"
        FLUTTER_MCP_URL="https://github.com/flutter-mcp/flutter-mcp/releases/latest/download/flutter-mcp-windows.exe"
        ;;
    *)
        echo -e "${RED}Error: Unsupported platform: $OS_TYPE${NC}"
        exit 1
        ;;
esac

# Check if Flutter MCP server is already configured
if check_mcp_exists "FlutterDocs"; then
    echo -e "${YELLOW}⚠ Flutter MCP server already configured${NC}"
    read -p "Do you want to reconfigure it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing Flutter MCP server..."
        claude mcp remove FlutterDocs || true
    else
        echo "Skipping Flutter MCP setup"
        FLUTTER_SKIPPED=true
    fi
fi

if [ "$FLUTTER_SKIPPED" != true ]; then
    # Determine installation directory
    INSTALL_DIR="/usr/local/bin"
    FLUTTER_MCP_PATH="$INSTALL_DIR/$FLUTTER_MCP_BINARY"

    # Check if binary already exists
    if [ -f "$FLUTTER_MCP_PATH" ]; then
        echo -e "${YELLOW}Flutter MCP binary already exists at $FLUTTER_MCP_PATH${NC}"
        read -p "Do you want to download the latest version? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            SKIP_DOWNLOAD=true
        fi
    fi

    # Download Flutter MCP binary
    if [ "$SKIP_DOWNLOAD" != true ]; then
        echo "Downloading Flutter MCP binary..."
        TEMP_FILE=$(mktemp)

        if curl -L "$FLUTTER_MCP_URL" -o "$TEMP_FILE"; then
            chmod +x "$TEMP_FILE"

            # Try to move to /usr/local/bin
            if sudo mv "$TEMP_FILE" "$FLUTTER_MCP_PATH" 2>/dev/null; then
                echo -e "${GREEN}✓ Flutter MCP binary installed to $FLUTTER_MCP_PATH${NC}"
            else
                # Fallback to local directory
                LOCAL_DIR="$HOME/.local/bin"
                mkdir -p "$LOCAL_DIR"
                mv "$TEMP_FILE" "$LOCAL_DIR/$FLUTTER_MCP_BINARY"
                FLUTTER_MCP_PATH="$LOCAL_DIR/$FLUTTER_MCP_BINARY"
                echo -e "${YELLOW}⚠ Installed to $FLUTTER_MCP_PATH (no sudo access)${NC}"
                echo -e "${YELLOW}  Make sure $LOCAL_DIR is in your PATH${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to download Flutter MCP binary${NC}"
            exit 1
        fi
    fi

    # Add Flutter MCP to Claude Code
    echo "Adding Flutter MCP server to Claude Code..."
    if claude mcp add --transport stdio FlutterDocs -- "$FLUTTER_MCP_PATH"; then
        echo -e "${GREEN}✓ Flutter MCP server configured successfully${NC}"
    else
        echo -e "${RED}✗ Failed to configure Flutter MCP server${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Show configured servers
echo "Configured MCP servers:"
claude mcp list

echo ""

# ============================================
# Record Setup Status
# ============================================
echo "📝 Recording MCP setup status..."

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
SETUP_FILE="$GIT_ROOT/.claude/settings.local.json"

# Function to safely extract JSON values
get_json_value() {
    local file=$1
    local key=$2
    if [[ -f "$file" ]]; then
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" | sed 's/.*:[[:space:]]*//;s/"//g;s/[[:space:]]*$//' | head -1
    fi
}

# Check if setup file exists and read existing values
if [[ -f "$SETUP_FILE" ]]; then
    CLAUDE_INSTALLED=$(get_json_value "$SETUP_FILE" "installed")
    CLAUDE_VERSION=$(get_json_value "$SETUP_FILE" "version")
    GIT_HOOKS_INSTALLED=$(get_json_value "$SETUP_FILE" "gitHooks")
    SETUP_COMPLETED=$(get_json_value "$SETUP_FILE" "completed")

    # Use existing values if they exist, otherwise detect current state
    CLAUDE_INSTALLED=${CLAUDE_INSTALLED:-true}
    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "unknown")
    else
        CLAUDE_VERSION=${CLAUDE_VERSION:-unknown}
    fi
    GIT_HOOKS_INSTALLED=${GIT_HOOKS_INSTALLED:-false}
    SETUP_COMPLETED=${SETUP_COMPLETED:-false}
else
    # Default values for new setup
    CLAUDE_INSTALLED=true
    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "unknown")
    else
        CLAUDE_VERSION="unknown"
    fi
    GIT_HOOKS_INSTALLED=false
    SETUP_COMPLETED=false
fi

# Create or update settings.local.json
cat > "$SETUP_FILE" << EOF
{
  "setup": {
    "completed": $SETUP_COMPLETED,
    "claudeCode": {
      "installed": $CLAUDE_INSTALLED,
      "version": "$CLAUDE_VERSION"
    },
    "mcp": {
      "configured": true
    },
    "gitHooks": {
      "installed": $GIT_HOOKS_INSTALLED
    },
    "setupDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

echo -e "${GREEN}✓${NC} Setup status recorded in .claude/settings.local.json"
echo ""

echo -e "${YELLOW}IMPORTANT: Restart Claude Code for changes to take effect${NC}"
echo ""

# Test instructions
echo "To test the configuration:"
echo "  1. Restart Claude Code"
echo "  2. Ask Claude: 'What are Ditto sync best practices?'"
echo "  3. Ask Claude: 'Show me Flutter StatefulWidget documentation'"
echo ""

# Optional: Check Dart version for future upgrade
echo -e "${BLUE}Info:${NC} Current Dart SDK version:"
dart --version 2>/dev/null || echo "  Dart SDK not found"
echo ""
echo "Note: Official Dart MCP server requires Dart 3.9+"
echo "      Current setup uses Flutter Documentation MCP (no version requirement)"
echo "      You can upgrade to Official Dart MCP after upgrading Dart SDK"
echo ""
echo "For more information:"
echo "  - Ditto MCP: .claude/guides/ditto-mcp-setup.md"
echo "  - Flutter MCP: .claude/guides/flutter-mcp-setup.md"
echo ""
