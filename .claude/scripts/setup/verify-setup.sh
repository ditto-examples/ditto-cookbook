#!/bin/bash

# Development Environment Setup Verification
# Checks the current setup status and provides recommendations

set -e

echo ""
echo "🔍 Development Environment Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
ALL_OK=true

# ============================================
# Check Setup File
# ============================================
if [[ ! -f "$SETUP_FILE" ]]; then
    echo -e "${YELLOW}⚠${NC}  Setup not completed"
    echo ""
    echo "Run the complete setup script:"
    echo "  ./.claude/scripts/setup/complete-setup.sh"
    echo ""
    exit 1
fi

# ============================================
# Parse and Display Status
# ============================================

# Function to safely extract JSON values (works without jq)
get_json_value() {
    local file=$1
    local key=$2
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$file" | sed 's/.*:[[:space:]]*//;s/"//g;s/[[:space:]]*$//'
}

SETUP_COMPLETED=$(get_json_value "$SETUP_FILE" "completed")
CLAUDE_INSTALLED=$(get_json_value "$SETUP_FILE" "installed")
CLAUDE_VERSION=$(get_json_value "$SETUP_FILE" "version")
MCP_CONFIGURED=$(get_json_value "$SETUP_FILE" "configured")
GIT_HOOKS_INSTALLED=$(get_json_value "$SETUP_FILE" "gitHooks")
SETUP_DATE=$(get_json_value "$SETUP_FILE" "setupDate")

echo "Setup Status:"
echo ""

# Overall Status
if [[ "$SETUP_COMPLETED" == "true" ]]; then
    echo -e "  Overall: ${GREEN}✓ Complete${NC}"
else
    echo -e "  Overall: ${YELLOW}⚠ Incomplete${NC}"
    ALL_OK=false
fi

# Git Hooks Status
echo -n "  Git Hooks: "
if [[ -x "$GIT_ROOT/.git/hooks/pre-commit" && -x "$GIT_ROOT/.git/hooks/commit-msg" && -x "$GIT_ROOT/.git/hooks/pre-push" ]]; then
    echo -e "${GREEN}✓ Installed and executable${NC}"
else
    echo -e "${RED}✗ Not properly installed${NC}"
    echo -e "     ${YELLOW}→${NC} Run: ./.claude/scripts/setup/setup-git-hooks.sh"
    ALL_OK=false
fi

# Claude Code Status
echo -n "  Claude Code: "
if command -v claude &> /dev/null; then
    CURRENT_VERSION=$(claude --version 2>&1 | head -1 || echo "unknown")
    echo -e "${GREEN}✓ Installed${NC} ($CURRENT_VERSION)"
else
    echo -e "${YELLOW}⚠ Not installed${NC}"
    echo -e "     ${YELLOW}→${NC} Recommended for this project"
    echo -e "     ${YELLOW}→${NC} Install from: https://claude.com/claude-code"
fi

# MCP Servers Status
echo -n "  MCP Servers: "
if [[ "$MCP_CONFIGURED" == "true" ]]; then
    echo -e "${GREEN}✓ Configured${NC}"

    # Verify actual MCP status if Claude is installed
    if command -v claude &> /dev/null; then
        if claude mcp list 2>/dev/null | grep -q "ditto\|flutter"; then
            echo -e "     ${GREEN}✓${NC} MCP servers are active"
        else
            echo -e "     ${YELLOW}⚠${NC} MCP servers configured but not detected"
            echo -e "     ${YELLOW}→${NC} Try restarting Claude Code"
        fi
    fi
else
    echo -e "${YELLOW}○ Not configured${NC} (optional)"
    if command -v claude &> /dev/null; then
        echo -e "     ${YELLOW}→${NC} Run: ./.claude/scripts/setup/setup-mcp-servers.sh"
    fi
fi

echo ""

# Setup Date
if [[ -n "$SETUP_DATE" ]]; then
    echo "Setup completed: $SETUP_DATE"
    echo ""
fi

# ============================================
# Additional Checks
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Additional Checks:"
echo ""

# Check .gitignore for settings.local.json
if grep -q "settings.local.json" "$GIT_ROOT/.gitignore" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} settings.local.json is properly gitignored"
else
    echo -e "${YELLOW}⚠${NC} settings.local.json should be in .gitignore"
    ALL_OK=false
fi

# Check if CLAUDE.md exists
if [[ -f "$GIT_ROOT/CLAUDE.md" ]]; then
    echo -e "${GREEN}✓${NC} Development guidelines (CLAUDE.md) present"
else
    echo -e "${YELLOW}⚠${NC} CLAUDE.md not found"
fi

# Check scripts are executable
SCRIPTS_OK=true
for script in setup-git-hooks.sh setup-mcp-servers.sh complete-setup.sh; do
    if [[ ! -x "$GIT_ROOT/.claude/scripts/setup/$script" ]]; then
        if [[ "$SCRIPTS_OK" == true ]]; then
            echo -e "${YELLOW}⚠${NC} Some setup scripts are not executable:"
            SCRIPTS_OK=false
        fi
        echo "     - $script"
    fi
done

if [[ "$SCRIPTS_OK" == true ]]; then
    echo -e "${GREEN}✓${NC} All setup scripts are executable"
fi

echo ""

# ============================================
# Recommendations
# ============================================
if [[ "$ALL_OK" == false ]] || [[ "$CLAUDE_INSTALLED" != "true" ]] || [[ "$MCP_CONFIGURED" != "true" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Recommendations:"
    echo ""

    if [[ "$SETUP_COMPLETED" != "true" ]]; then
        echo -e "${YELLOW}→${NC} Complete setup: ./.claude/scripts/setup/complete-setup.sh"
    fi

    if [[ ! -x "$GIT_ROOT/.git/hooks/pre-commit" ]]; then
        echo -e "${YELLOW}→${NC} Install Git Hooks: ./.claude/scripts/setup/setup-git-hooks.sh"
    fi

    if ! command -v claude &> /dev/null; then
        echo -e "${YELLOW}→${NC} Install Claude Code: https://claude.com/claude-code"
    fi

    if [[ "$MCP_CONFIGURED" != "true" ]] && command -v claude &> /dev/null; then
        echo -e "${YELLOW}→${NC} Configure MCP: ./.claude/scripts/setup/setup-mcp-servers.sh"
    fi

    echo ""
fi

# ============================================
# Summary
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$ALL_OK" == true ]] && [[ "$CLAUDE_INSTALLED" == "true" ]] && [[ "$MCP_CONFIGURED" == "true" ]]; then
    echo -e "${GREEN}✅ Your development environment is fully configured!${NC}"
    echo ""
    echo "You're ready to start developing."
else
    echo -e "${YELLOW}⚠ Your development environment has some recommendations${NC}"
    echo ""
    echo "You can still develop, but following the recommendations above"
    echo "will improve your experience."
fi

echo ""
echo "For more information:"
echo "  • Quick start: .claude/QUICK-START.md"
echo "  • Guidelines: CLAUDE.md"
echo "  • Git Hooks: .claude/guides/git-hooks.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Exit with appropriate code
if [[ "$ALL_OK" == true ]]; then
    exit 0
else
    exit 1
fi
