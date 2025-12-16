#!/bin/bash

# Complete Development Environment Setup
# Unified setup script that configures everything at once

set -e

echo ""
echo "🚀 Complete Development Environment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script will set up your development environment:"
echo "  1. Tool version management (required)"
echo "  2. Git Hooks (required)"
echo "  3. Claude Code verification"
echo "  4. MCP servers (optional)"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get the root directory
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$GIT_ROOT" ]]; then
    echo -e "${RED}✗${NC} Not a git repository"
    exit 1
fi

SETUP_FILE="$GIT_ROOT/.claude/settings.local.json"
SCRIPTS_DIR="$GIT_ROOT/.claude/scripts"

# ============================================
# Step 1: Tool Version Management
# ============================================
echo -e "${BLUE}━━━ Step 1/4: Tool Version Management ━━━${NC}"
echo ""

VERSIONS_INSTALLED=false

echo "Setting up automated version management..."
echo "This ensures all developers use the same tool versions."
echo ""
read -p "Install and configure tool versions now? (y/n) " -n 1 -r
echo
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [[ -f "$SCRIPTS_DIR/setup/setup-versions.sh" ]]; then
        "$SCRIPTS_DIR/setup/setup-versions.sh"
        VERSIONS_INSTALLED=true
    else
        echo -e "${RED}✗${NC} Version setup script not found: $SCRIPTS_DIR/setup/setup-versions.sh"
        VERSIONS_INSTALLED=false
    fi
else
    echo -e "${YELLOW}→${NC} Skipped version setup"
    echo -e "${YELLOW}→${NC} You can run it later: $SCRIPTS_DIR/setup/setup-versions.sh"
    VERSIONS_INSTALLED=false
fi

echo ""

# ============================================
# Step 2: Git Hooks Installation
# ============================================
echo -e "${BLUE}━━━ Step 2/4: Git Hooks Installation ━━━${NC}"
echo ""

if [[ -f "$SCRIPTS_DIR/setup/setup-git-hooks.sh" ]]; then
    "$SCRIPTS_DIR/setup/setup-git-hooks.sh"
    GIT_HOOKS_INSTALLED=true
else
    echo -e "${RED}✗${NC} Setup script not found: $SCRIPTS_DIR/setup/setup-git-hooks.sh"
    GIT_HOOKS_INSTALLED=false
fi

echo ""

# ============================================
# Step 3: Claude Code Verification
# ============================================
echo -e "${BLUE}━━━ Step 3/4: Claude Code Verification ━━━${NC}"
echo ""

if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "unknown")
    echo -e "${GREEN}✓${NC} Claude Code detected: $CLAUDE_VERSION"
    CLAUDE_INSTALLED=true
else
    echo -e "${YELLOW}⚠${NC}  Claude Code not found"
    echo -e "${YELLOW}→${NC} Claude Code is recommended for this project"
    echo -e "${YELLOW}→${NC} Install from: https://claude.com/claude-code"
    echo ""
    echo "Continue without Claude Code? (development will still work)"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Install Claude Code and run this script again."
        exit 1
    fi
    CLAUDE_INSTALLED=false
    CLAUDE_VERSION="not_installed"
fi

echo ""

# ============================================
# Step 4: MCP Servers Setup (Optional)
# ============================================
echo -e "${BLUE}━━━ Step 4/4: MCP Servers Setup (Optional) ━━━${NC}"
echo ""

MCP_CONFIGURED=false

if [[ "$CLAUDE_INSTALLED" == true ]]; then
    echo "MCP servers enhance Claude Code with project-specific capabilities."
    echo "This step is optional but recommended."
    echo ""
    read -p "Configure MCP servers now? (y/n) " -n 1 -r
    echo
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "$SCRIPTS_DIR/setup/setup-mcp-servers.sh" ]]; then
            "$SCRIPTS_DIR/setup/setup-mcp-servers.sh"
            MCP_CONFIGURED=true
            echo ""
            echo -e "${GREEN}✓${NC} MCP servers configured"
            echo -e "${YELLOW}→${NC} Remember to restart Claude Code for changes to take effect"
        else
            echo -e "${YELLOW}⚠${NC}  MCP setup script not found"
            MCP_CONFIGURED=false
        fi
    else
        echo -e "${YELLOW}→${NC} Skipped MCP setup"
        echo -e "${YELLOW}→${NC} You can run it later: $SCRIPTS_DIR/setup/setup-mcp-servers.sh"
        MCP_CONFIGURED=false
    fi
else
    echo -e "${YELLOW}→${NC} Skipping MCP setup (Claude Code not installed)"
    MCP_CONFIGURED=false
fi

echo ""

# ============================================
# Record Setup Status
# ============================================
echo -e "${BLUE}━━━ Recording Setup Status ━━━${NC}"
echo ""

# Create settings.local.json with setup information
cat > "$SETUP_FILE" << EOF
{
  "setup": {
    "completed": true,
    "versions": {
      "installed": $VERSIONS_INSTALLED
    },
    "claudeCode": {
      "installed": $CLAUDE_INSTALLED,
      "version": "$CLAUDE_VERSION"
    },
    "mcp": {
      "configured": $MCP_CONFIGURED
    },
    "gitHooks": {
      "installed": $GIT_HOOKS_INSTALLED
    },
    "setupDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

echo -e "${GREEN}✓${NC} Setup status saved to .claude/settings.local.json"
echo ""

# ============================================
# Summary
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo ""
echo "Setup Summary:"
echo "  • Tool Versions: $([ "$VERSIONS_INSTALLED" = true ] && echo -e "${GREEN}✓ Installed${NC}" || echo -e "${YELLOW}○ Not configured${NC}")"
echo "  • Git Hooks: $([ "$GIT_HOOKS_INSTALLED" = true ] && echo -e "${GREEN}✓ Installed${NC}" || echo -e "${RED}✗ Failed${NC}")"
echo "  • Claude Code: $([ "$CLAUDE_INSTALLED" = true ] && echo -e "${GREEN}✓ Detected${NC}" || echo -e "${YELLOW}⚠ Not installed${NC}")"
echo "  • MCP Servers: $([ "$MCP_CONFIGURED" = true ] && echo -e "${GREEN}✓ Configured${NC}" || echo -e "${YELLOW}○ Not configured${NC}")"
echo ""

if [[ "$CLAUDE_INSTALLED" == true && "$MCP_CONFIGURED" == true ]]; then
    echo -e "${YELLOW}⚠ Important:${NC} Restart Claude Code to activate MCP servers"
    echo ""
fi

echo "Next steps:"
echo "  1. Read: CLAUDE.md for development guidelines"
echo "  2. Verify: Run ./.claude/scripts/setup/verify-setup.sh"
echo "  3. Test: Make a test commit to verify Git Hooks work"
echo "  4. Develop: Start coding with confidence!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
